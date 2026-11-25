#!/usr/bin/env python3
"""Kinetune library import: loads the exercise library from the author's spreadsheet.

Usage:
    python db/library/import_library.py db/library/kinetune_library.xlsx [--dry-run] [--replace | --update]

Modes: (default) import into an empty library; --replace deletes the library
and imports again (refused while plans use it); --update applies the sheet to
an existing library by exercise name and keeps the ids that plans refer to.

Connection: DATABASE_URL (a libpq URL or "key=value" string). If it is not set,
the standard PG* variables are used (PGHOST, PGPORT, PGDATABASE, PGUSER,
PGPASSWORD). The role needs app_admin rights on the library tables (or owns them).

Everything runs in ONE transaction: on any problem nothing is written and all
problems are printed together (sheet, row, column, value). Sheet format,
validation and graph derivation: docs/database/library_import.md.

Exit codes: 0 = imported (or dry run passed), 1 = validation or database
errors (nothing written), 2 = the file or the database cannot be opened.
"""
from __future__ import annotations

import argparse
import difflib
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

import openpyxl
import psycopg

LIBRARY_SHEET = "Library"
PROGRESSIONS_SHEET = "Progressions (manual)"

# order used by the graph derivation (business rules v2, "Exercise graphs")
MODE_ORDER = {"dynamic": 0, "static": 1, "stato_dynamic": 2}
LOAD_ORDER = {"low": 1, "medium": 2, "high": 3}  # a joint that is not involved = 0
BALANCE_POSE = "balance"

REQUIRED_COLUMNS = ["Name", "Description", "Mode", "Starting pose", "Symmetric",
                    "Difficulty", "Rep duration (sec)", "Active"]
NUMBERED_COLUMNS = {
    "family": re.compile(r"^Family (\d+)$"),
    "compensation": re.compile(r"^Compensation exercise (\d+)$"),
    "main_joint": re.compile(r"^Main joint (\d+)$"),
    "secondary_joint": re.compile(r"^Secondary joint (\d+)$"),
    "main_muscle": re.compile(r"^Main muscle (\d+)$"),
    "secondary_muscle": re.compile(r"^Secondary muscle (\d+)$"),
}
LOAD_COLUMN = re.compile(r"^Load: (.+)$")
IGNORED_COLUMNS = {"Notes"}

MAX_EXERCISE_NAME = 120
MAX_FAMILY_NAME = 64
MAX_SMALLINT = 32767


# ---------------------------------------------------------------------------
# Problems (errors and warnings), reported together at the end
# ---------------------------------------------------------------------------

@dataclass
class Problem:
    level: str            # "ERROR" or "WARNING"
    sheet: str
    row: int | None
    column: str | None
    value: object
    message: str

    def __str__(self) -> str:
        where = [self.sheet]
        if self.row is not None:
            where.append(f"row {self.row}")
        if self.column is not None:
            where.append(f'column "{self.column}"')
        text = f"{self.level:<8}{', '.join(where)}"
        if self.value is not None:
            text += f", value {self.value!r}"
        return f"{text}: {self.message}"


class Report:
    def __init__(self) -> None:
        self.problems: list[Problem] = []

    def error(self, sheet, row, column, value, message) -> None:
        self.problems.append(Problem("ERROR", sheet, row, column, value, message))

    def warning(self, sheet, row, column, value, message) -> None:
        self.problems.append(Problem("WARNING", sheet, row, column, value, message))

    @property
    def errors(self) -> list[Problem]:
        return [p for p in self.problems if p.level == "ERROR"]

    @property
    def warnings(self) -> list[Problem]:
        return [p for p in self.problems if p.level == "WARNING"]

    def print(self) -> None:
        for p in self.errors + self.warnings:
            print(p)


# ---------------------------------------------------------------------------
# Data read from the sheet
# ---------------------------------------------------------------------------

@dataclass
class JointLink:
    is_primary: bool
    load_level: str | None = None


@dataclass
class Exercise:
    row: int
    name: str
    description: str | None = None
    families: list[str] = field(default_factory=list)
    mode: str | None = None
    starting_pose: str | None = None
    is_symmetric: bool | None = None
    difficulty: int | None = None
    rep_duration_sec: int | None = None
    compensations: list[str] = field(default_factory=list)
    is_active: bool = True
    joints: dict[str, JointLink] = field(default_factory=dict)     # joint name -> link
    muscles: dict[str, bool] = field(default_factory=dict)         # muscle name -> is_primary


@dataclass
class ManualProgression:
    row: int
    easier: str
    harder: str


@dataclass
class Reference:
    joints: dict[str, int]
    muscles: dict[str, int]
    modes: set[str]
    poses: set[str]


@dataclass
class Edges:
    family_pairs: set[frozenset]                  # pairs sharing a family (variations; not stored)
    progressions: dict[tuple[str, str], bool]     # (easier, harder) -> is_manual
    overridden: list[tuple[ManualProgression, tuple[str, str]]]


# ---------------------------------------------------------------------------
# Cell helpers
# ---------------------------------------------------------------------------

def clean(value):
    """Trim text, drop a leading apostrophe (text-formatted numbers), '' -> None."""
    if value is None:
        return None
    if isinstance(value, str):
        value = value.strip()
        if value.startswith("'"):
            value = value[1:].strip()
        return value or None
    return value


def as_text(value) -> str | None:
    value = clean(value)
    if value is None:
        return None
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return str(value)


def as_whole_number(value) -> int | None:
    """Whole number from an int, an integral float or a numeric string; None if not whole."""
    value = clean(value)
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value) if value.is_integer() else None
    if isinstance(value, str) and re.fullmatch(r"[+-]?\d+", value):
        return int(value)
    if isinstance(value, str) and re.fullmatch(r"[+-]?\d+\.0*", value):
        return int(float(value))
    return None


def as_yes_no(value) -> bool | None:
    value = clean(value)
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.lower() in ("yes", "no"):
        return value.lower() == "yes"
    return None


def as_code(value) -> str | None:
    """Sheet label -> enum code: lower case, spaces and hyphens -> '_' ('downward dog' -> 'downward_dog')."""
    text = as_text(value)
    if text is None:
        return None
    return re.sub(r"[\s\-]+", "_", text.lower())


def did_you_mean(name: str, known) -> str:
    match = difflib.get_close_matches(name, list(known), n=1, cutoff=0.6)
    return f' (did you mean "{match[0]}"?)' if match else ""


# ---------------------------------------------------------------------------
# Reading and validating the sheets
# ---------------------------------------------------------------------------

def read_library(wb, ref: Reference, report: Report) -> list[Exercise]:
    sheet = LIBRARY_SHEET
    if sheet not in wb.sheetnames:
        report.error(sheet, None, None, None, "sheet not found")
        return []
    ws = wb[sheet]
    rows = ws.iter_rows(values_only=True)
    header = next(rows, None)
    if header is None:
        report.error(sheet, 1, None, None, "the sheet is empty (header row expected)")
        return []

    # --- header ---
    col: dict[str, int] = {}
    numbered: dict[str, list[tuple[int, str, int]]] = defaultdict(list)   # kind -> [(number, header, idx)]
    load_cols: dict[str, tuple[str, int]] = {}                            # joint -> (header, idx)
    for idx, raw in enumerate(header):
        name = as_text(raw)
        if name is None:
            continue
        if name in col:
            report.error(sheet, 1, name, None, "duplicate column header")
            continue
        col[name] = idx
        if name in REQUIRED_COLUMNS or name in IGNORED_COLUMNS:
            continue
        for kind, pattern in NUMBERED_COLUMNS.items():
            m = pattern.match(name)
            if m:
                numbered[kind].append((int(m.group(1)), name, idx))
                break
        else:
            m = LOAD_COLUMN.match(name)
            if m:
                joint = m.group(1).strip()
                if joint not in ref.joints:
                    report.error(sheet, 1, name, None, f'unknown joint "{joint}" in a load column{did_you_mean(joint, ref.joints)}')
                else:
                    load_cols[joint] = (name, idx)
            else:
                report.warning(sheet, 1, name, None, "unknown column, ignored")
    for name in REQUIRED_COLUMNS:
        if name not in col:
            report.error(sheet, 1, name, None, "required column is missing")
    for kind, example in (("family", "Family 1"), ("main_joint", "Main joint 1"), ("main_muscle", "Main muscle 1")):
        if not numbered[kind]:
            report.error(sheet, 1, example, None, "required column group is missing")
    if report.errors:
        return []
    for kind in numbered:
        numbered[kind].sort()

    # --- rows ---
    exercises: list[Exercise] = []
    seen: dict[str, int] = {}              # lower-case name -> row
    data_cols = [i for n, i in col.items() if n not in IGNORED_COLUMNS]
    for r, values in enumerate(rows, start=2):
        values = list(values) + [None] * (len(header) - len(values))
        if all(clean(values[i]) is None for i in data_cols):
            continue                                    # empty row (Notes alone does not count)

        def cell(name):
            return values[col[name]]

        name = as_text(cell("Name"))
        if name is None:
            report.error(sheet, r, "Name", None, "name is required")
            continue
        ex = Exercise(row=r, name=name)
        if len(name) > MAX_EXERCISE_NAME:
            report.error(sheet, r, "Name", name, f"name is longer than {MAX_EXERCISE_NAME} characters")
        if name.lower() in seen:
            report.error(sheet, r, "Name", name, f"duplicate name (first used in row {seen[name.lower()]}); names are the reference key")
        else:
            seen[name.lower()] = r

        ex.description = as_text(cell("Description"))

        # families
        for _, header_name, idx in numbered["family"]:
            fam = as_text(values[idx])
            if fam is None:
                continue
            if len(fam) > MAX_FAMILY_NAME:
                report.error(sheet, r, header_name, fam, f"family name is longer than {MAX_FAMILY_NAME} characters")
            elif fam in ex.families:
                report.error(sheet, r, header_name, fam, "the same family is listed twice in this row")
            else:
                ex.families.append(fam)

        # mode, pose
        mode = as_code(cell("Mode"))
        if mode is None:
            report.error(sheet, r, "Mode", None, "mode is required")
        elif mode not in ref.modes:
            report.error(sheet, r, "Mode", cell("Mode"), f"unknown mode; allowed: {', '.join(sorted(ref.modes))}")
        else:
            ex.mode = mode
        pose = as_code(cell("Starting pose"))
        if pose is None:
            report.error(sheet, r, "Starting pose", None, "starting pose is required")
        elif pose not in ref.poses:
            report.error(sheet, r, "Starting pose", cell("Starting pose"),
                         f"unknown starting pose; allowed: {', '.join(sorted(p.replace('_', ' ') for p in ref.poses))}")
        else:
            ex.starting_pose = pose

        # symmetric, difficulty, rep duration, active
        sym = as_yes_no(cell("Symmetric"))
        if sym is None:
            report.error(sheet, r, "Symmetric", cell("Symmetric"), "must be yes or no")
        ex.is_symmetric = sym
        diff = as_whole_number(cell("Difficulty"))
        if diff is None or not 1 <= diff <= 3:
            report.error(sheet, r, "Difficulty", cell("Difficulty"), "must be 1, 2 or 3")
        else:
            ex.difficulty = diff
        rep = as_whole_number(cell("Rep duration (sec)"))
        raw_rep = clean(cell("Rep duration (sec)"))
        if raw_rep is None:
            report.error(sheet, r, "Rep duration (sec)", None, "rep duration is required")
        elif rep is None:
            report.error(sheet, r, "Rep duration (sec)", raw_rep, "must be a whole number of seconds (no fractions)")
        elif not 0 < rep <= MAX_SMALLINT:
            report.error(sheet, r, "Rep duration (sec)", raw_rep, "must be greater than 0")
        else:
            ex.rep_duration_sec = rep
        raw_active = clean(cell("Active"))
        if raw_active is not None:
            active = as_yes_no(raw_active)
            if active is None:
                report.error(sheet, r, "Active", raw_active, "must be yes, no or empty (empty = yes)")
            else:
                ex.is_active = active

        # compensations (names are checked once all exercises are known)
        for _, header_name, idx in numbered["compensation"]:
            comp = as_text(values[idx])
            if comp is None:
                continue
            if comp in ex.compensations:
                report.error(sheet, r, header_name, comp, "the same compensating exercise is listed twice in this row")
            else:
                ex.compensations.append(comp)

        # joints: main and secondary, then their loads
        unknown_joint = False
        for kind, is_primary in (("main_joint", True), ("secondary_joint", False)):
            for _, header_name, idx in numbered[kind]:
                joint = as_text(values[idx])
                if joint is None:
                    continue
                if joint not in ref.joints:
                    unknown_joint = True
                    report.error(sheet, r, header_name, joint, f"unknown joint{did_you_mean(joint, ref.joints)}")
                elif joint in ex.joints:
                    report.error(sheet, r, header_name, joint, "the same joint is listed twice in this row (main and secondary)")
                else:
                    ex.joints[joint] = JointLink(is_primary=is_primary)
        for joint, (header_name, idx) in load_cols.items():
            raw_load = clean(values[idx])
            if raw_load is None:
                continue
            load = as_code(raw_load)
            if load not in LOAD_ORDER:
                report.error(sheet, r, header_name, raw_load, "load must be low, medium or high")
            elif joint not in ex.joints:
                if unknown_joint:
                    continue          # already reported as an unknown joint name
                report.error(sheet, r, header_name, raw_load,
                             f'load is filled for the joint "{joint}", which is not listed as a main or secondary joint of this row')
            else:
                ex.joints[joint].load_level = load
        for joint, link in ex.joints.items():
            if link.load_level is None:
                header_name = load_cols.get(joint, (f"Load: {joint}", None))[0]
                if joint not in load_cols:
                    report.error(sheet, r, header_name, None, f'joint "{joint}" is listed, but the sheet has no load column for it')
                else:
                    report.error(sheet, r, header_name, None, f'joint "{joint}" is listed, but its load is empty')

        # muscles
        for kind, is_primary in (("main_muscle", True), ("secondary_muscle", False)):
            for _, header_name, idx in numbered[kind]:
                muscle = as_text(values[idx])
                if muscle is None:
                    continue
                if muscle not in ref.muscles:
                    report.error(sheet, r, header_name, muscle, f"unknown muscle{did_you_mean(muscle, ref.muscles)}")
                elif muscle in ex.muscles:
                    report.error(sheet, r, header_name, muscle, "the same muscle is listed twice in this row (main and secondary)")
                else:
                    ex.muscles[muscle] = is_primary

        # DQ09: a main joint or a main muscle (relaxation exercises have joints only)
        if not any(link.is_primary for link in ex.joints.values()) and not any(ex.muscles.values()):
            report.error(sheet, r, None, None, "the exercise needs at least one main joint or one main muscle")

        exercises.append(ex)

    if not exercises and not report.errors:
        report.error(sheet, None, None, None, "no exercises found")
    return exercises


def check_library_links(exercises: list[Exercise], report: Report) -> None:
    """Checks that need all rows: compensations and family sizes."""
    sheet = LIBRARY_SHEET
    by_name = {ex.name: ex for ex in exercises}
    comp_col = "Compensation exercise"
    for ex in exercises:
        for comp in ex.compensations:
            if comp == ex.name:
                report.error(sheet, ex.row, comp_col, comp, "an exercise cannot compensate itself")
            elif comp not in by_name:
                report.error(sheet, ex.row, comp_col, comp, f"compensating exercise is not in the Library sheet{did_you_mean(comp, by_name)}")
            elif not by_name[comp].is_active:
                report.error(sheet, ex.row, comp_col, comp, "compensating exercise is inactive (DQ27)")
    for ex in exercises:                                     # DQ26: no two-exercise loop
        for comp in ex.compensations:
            other = by_name.get(comp)
            if other is not None and ex.name in other.compensations and ex.row < other.row:
                report.error(sheet, other.row, comp_col, ex.name,
                             f'two-exercise compensation loop: "{ex.name}" (row {ex.row}) and "{other.name}" compensate each other (DQ26)')

    members: dict[str, list[Exercise]] = defaultdict(list)
    for ex in exercises:
        for fam in ex.families:
            members[fam].append(ex)
    for fam, exs in members.items():
        if len(exs) < 2:
            report.warning(sheet, exs[0].row, "Family", fam,
                           "family has only one exercise, so its member has no variations through it (check the spelling?) (DQ35)")
    for ex in exercises:
        if not ex.families:
            report.warning(sheet, ex.row, "Family 1", None, "exercise has no family: it can only be linked by manual progressions")


def read_progressions(wb, names: set[str], report: Report) -> list[ManualProgression]:
    sheet = PROGRESSIONS_SHEET
    if sheet not in wb.sheetnames:
        report.warning(sheet, None, None, None, "sheet not found: no manual progressions")
        return []
    ws = wb[sheet]
    result: list[ManualProgression] = []
    seen: dict[tuple[str, str], int] = {}
    for r, values in enumerate(ws.iter_rows(min_row=2, max_col=2, values_only=True), start=2):
        values = list(values) + [None] * (2 - len(values))
        easier, harder = as_text(values[0]), as_text(values[1])
        if easier is None and harder is None:
            continue
        ok = True
        for column, value in (("Easier exercise (A)", easier), ("Harder exercise (B)", harder)):
            if value is None:
                report.error(sheet, r, column, None, "both exercises are required")
                ok = False
            elif value not in names:
                report.error(sheet, r, column, value, f"exercise is not in the Library sheet{did_you_mean(value, names)}")
                ok = False
        if not ok:
            continue
        if easier == harder:
            report.error(sheet, r, None, easier, "an exercise cannot be a progression of itself")
            continue
        if (easier, harder) in seen:
            report.warning(sheet, r, None, f"{easier} -> {harder}", f"duplicate of row {seen[(easier, harder)]}, ignored")
            continue
        seen[(easier, harder)] = r
        result.append(ManualProgression(r, easier, harder))
    return result


# ---------------------------------------------------------------------------
# Graph derivation (business rules v2, "Exercise graphs")
# ---------------------------------------------------------------------------

def compare(a: Exercise, b: Exercise) -> tuple[set[str], set[str]]:
    """Attributes by which B is harder / easier than A."""
    harder: set[str] = set()
    easier: set[str] = set()

    def side(attribute: str, va, vb) -> None:
        if vb > va:
            harder.add(attribute)
        elif vb < va:
            easier.add(attribute)

    side("difficulty", a.difficulty, b.difficulty)
    side("mode", MODE_ORDER[a.mode], MODE_ORDER[b.mode])
    side("balance", a.starting_pose == BALANCE_POSE, b.starting_pose == BALANCE_POSE)
    for joint in set(a.joints) | set(b.joints):
        la = LOAD_ORDER[a.joints[joint].load_level] if joint in a.joints else 0
        lb = LOAD_ORDER[b.joints[joint].load_level] if joint in b.joints else 0
        side("joint load", la, lb)
    return harder, easier


def is_complete(ex: Exercise) -> bool:
    """All attributes the derivation compares are valid (rows with errors are skipped)."""
    return (ex.mode is not None and ex.difficulty is not None and ex.starting_pose is not None
            and all(link.load_level is not None for link in ex.joints.values()))


def derive_edges(exercises: list[Exercise], manual: list[ManualProgression], report: Report) -> Edges:
    by_name = {ex.name: ex for ex in exercises}
    members: dict[str, list[str]] = defaultdict(list)
    for ex in exercises:
        if not is_complete(ex):
            continue
        for fam in ex.families:
            members[fam].append(ex.name)

    family_pairs: set[frozenset] = set()
    progressions: dict[tuple[str, str], bool] = {}
    for names in members.values():
        for i, name_a in enumerate(names):
            for name_b in names[i + 1:]:
                pair = frozenset((name_a, name_b))
                if pair in family_pairs:
                    continue                      # same result in every shared family
                family_pairs.add(pair)            # a variation, implicitly through the family
                harder, easier = compare(by_name[name_a], by_name[name_b])
                if harder and not easier:
                    progressions[(name_a, name_b)] = False
                elif easier and not harder:
                    progressions[(name_b, name_a)] = False

    overridden: list[tuple[ManualProgression, tuple[str, str]]] = []
    for mp in manual:
        reverse = (mp.harder, mp.easier)
        if reverse in progressions:
            if progressions[reverse]:
                report.error(PROGRESSIONS_SHEET, mp.row, None, f"{mp.easier} -> {mp.harder}",
                             "the opposite manual progression is also listed (that is a cycle)")
                continue
            del progressions[reverse]                     # expert judgement wins
            overridden.append((mp, reverse))
        progressions[(mp.easier, mp.harder)] = True

    cycle = find_cycle(progressions)
    if cycle:
        rows = sorted(mp.row for mp in manual if any(
            (mp.easier, mp.harder) == (cycle[i], cycle[i + 1]) for i in range(len(cycle) - 1)))
        report.error(PROGRESSIONS_SHEET, rows[0] if rows else None, None, " -> ".join(cycle),
                     f"manual progressions create a cycle (rows {', '.join(map(str, rows)) or '-'})")
    return Edges(family_pairs, progressions, overridden)


def find_cycle(progressions: dict[tuple[str, str], bool]) -> list[str] | None:
    graph: dict[str, list[str]] = defaultdict(list)
    for easier, harder in progressions:
        graph[easier].append(harder)
    state: dict[str, int] = {}             # 1 = on the current path, 2 = done
    for start in list(graph):
        if state.get(start):
            continue
        path = [start]
        stack = [iter(graph[start])]
        state[start] = 1
        while stack:
            nxt = next(stack[-1], None)
            if nxt is None:
                state[path.pop()] = 2
                stack.pop()
            elif state.get(nxt) == 1:
                return path[path.index(nxt):] + [nxt]
            elif not state.get(nxt):
                state[nxt] = 1
                path.append(nxt)
                stack.append(iter(graph[nxt]))
    return None


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

def load_reference(cur) -> Reference:
    cur.execute("SELECT name, id FROM joint")
    joints = dict(cur.fetchall())
    cur.execute("SELECT name, id FROM muscle")
    muscles = dict(cur.fetchall())
    cur.execute("SELECT unnest(enum_range(NULL::exercise_mode))::text")
    modes = {r[0] for r in cur.fetchall()}
    cur.execute("SELECT unnest(enum_range(NULL::starting_pose))::text")
    poses = {r[0] for r in cur.fetchall()}
    if not joints or not muscles:
        raise RuntimeError("reference data (joints, muscles) is missing: run the migrations first")
    return Reference(joints, muscles, modes, poses)


def lock_library(cur) -> int:
    """One import at a time; returns the number of exercises already in the library."""
    cur.execute("LOCK TABLE exercise IN SHARE ROW EXCLUSIVE MODE")
    cur.execute("SELECT count(*) FROM exercise")
    return cur.fetchone()[0]


def clear_links(cur, exercise_ids: list[int] | None = None) -> None:
    """Graph edges (always all: they are derived) and the junction rows of the
    given exercises (None = all), which are then rebuilt from the sheet."""
    cur.execute("DELETE FROM exercise_relation")
    for table in ("exercise_compensation", "exercise_family_member", "exercise_joint", "exercise_muscle"):
        if exercise_ids is None:
            cur.execute(f"DELETE FROM {table}")
        else:
            cur.execute(f"DELETE FROM {table} WHERE exercise_id = ANY (%s)", (exercise_ids,))


def prepare_replace(cur, count: int, replace: bool) -> str | None:
    """Default and --replace modes. Returns the reason to stop, or None."""
    if count == 0:
        return None
    if not replace:
        return (f"the library already has {count} exercises; use --update to apply the sheet "
                "to it, or --replace to delete it and import again")
    cur.execute("SELECT count(*), count(DISTINCT plan_id) FROM plan_item")
    items, plans = cur.fetchone()
    if items:
        return (f"--replace refused: {items} plan items in {plans} plans reference the library; "
                "use --update instead (it keeps the exercises that plans use)")
    clear_links(cur)
    cur.execute("DELETE FROM exercise")
    cur.execute("DELETE FROM exercise_family")
    return None


def check_update(cur, exercises: list[Exercise], report: Report) -> None:
    """--update: changes the sheet may not make to exercises that plans already use."""
    cur.execute("""SELECT DISTINCT e.name
                     FROM plan_item pi JOIN exercise e ON e.id = pi.exercise_id
                    WHERE pi.side <> 'both'""")
    one_sided = {r[0] for r in cur.fetchall()}
    for ex in exercises:
        if ex.is_symmetric and ex.name in one_sided:
            report.error(LIBRARY_SHEET, ex.row, "Symmetric", "yes",
                         "the exercise is planned for one side (left/right) in existing plans, "
                         "so it cannot become symmetric (DQ25)")


def write_exercises(cur, exercises: list[Exercise]) -> tuple[dict[str, int], dict[str, int], dict[str, int]]:
    """Insert (or, with update, upsert by name) families and exercises. Returns name -> id maps and counts."""
    counts = {"added": 0, "changed": 0, "unchanged": 0, "deleted": 0, "deactivated": 0}

    cur.execute("SELECT name, id FROM exercise_family")
    family_ids: dict[str, int] = dict(cur.fetchall())
    for ex in exercises:
        for fam in ex.families:
            if fam not in family_ids:
                cur.execute("INSERT INTO exercise_family (name) VALUES (%s) RETURNING id", (fam,))
                family_ids[fam] = cur.fetchone()[0]

    cur.execute("SELECT name, id FROM exercise")
    existing: dict[str, int] = dict(cur.fetchall())
    ids: dict[str, int] = {}
    for ex in exercises:
        values = (ex.description, ex.mode, ex.starting_pose, ex.is_symmetric,
                  ex.difficulty, ex.rep_duration_sec, ex.is_active)
        if ex.name in existing:
            ids[ex.name] = existing[ex.name]
            cur.execute(
                """UPDATE exercise
                      SET (description, mode, starting_pose, is_symmetric, difficulty, rep_duration_sec, is_active)
                        = (%s, %s, %s, %s, %s, %s, %s)
                    WHERE id = %s
                      AND (description, mode, starting_pose, is_symmetric, difficulty, rep_duration_sec, is_active)
                          IS DISTINCT FROM (%s, %s::exercise_mode, %s::starting_pose, %s, %s, %s, %s)""",
                values + (ids[ex.name],) + values)
            counts["changed" if cur.rowcount else "unchanged"] += 1
        else:
            cur.execute(
                """INSERT INTO exercise (description, mode, starting_pose, is_symmetric,
                                         difficulty, rep_duration_sec, is_active, name)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id""",
                values + (ex.name,))
            ids[ex.name] = cur.fetchone()[0]
            counts["added"] += 1

    return ids, family_ids, counts


def remove_missing(cur, ids: dict[str, int], counts: dict[str, int], report: Report) -> None:
    """--update: exercises that are no longer in the sheet. Deleted if nothing
    refers to them; otherwise deactivated and kept with their joints, muscles,
    families and compensations, so old plans can still be checked (BR1–BR9)."""
    cur.execute("""SELECT e.id, e.name, e.is_active,
                          EXISTS (SELECT 1 FROM plan_item pi WHERE pi.exercise_id = e.id)
                          OR EXISTS (SELECT 1 FROM recommendation r WHERE r.candidate_exercise_id = e.id)
                     FROM exercise e
                    WHERE NOT (e.id = ANY (%s))""", (list(ids.values()),))
    for ex_id, name, is_active, used in cur.fetchall():
        if used:
            if is_active:
                cur.execute("UPDATE exercise SET is_active = false WHERE id = %s", (ex_id,))
                counts["deactivated"] += 1
                report.warning(LIBRARY_SHEET, None, "Name", name,
                               "the exercise is no longer in the sheet but plans or recommendations use it: "
                               "deactivated (kept with its joints and muscles)")
        else:
            # a kept (deactivated) exercise may still list it as a compensation
            cur.execute("DELETE FROM exercise_compensation WHERE compensation_exercise_id = %s", (ex_id,))
            cur.execute("DELETE FROM exercise WHERE id = %s", (ex_id,))
            counts["deleted"] += 1


def write_links(cur, exercises: list[Exercise], ids: dict[str, int], family_ids: dict[str, int],
                edges: Edges, ref: Reference) -> None:
    cur.executemany(
        "INSERT INTO exercise_family_member (exercise_id, family_id) VALUES (%s, %s)",
        [(ids[ex.name], family_ids[fam]) for ex in exercises for fam in ex.families])
    cur.executemany(
        "INSERT INTO exercise_joint (exercise_id, joint_id, is_primary, load_level) VALUES (%s, %s, %s, %s)",
        [(ids[ex.name], ref.joints[j], link.is_primary, link.load_level)
         for ex in exercises for j, link in ex.joints.items()])
    cur.executemany(
        "INSERT INTO exercise_muscle (exercise_id, muscle_id, is_primary) VALUES (%s, %s, %s)",
        [(ids[ex.name], ref.muscles[m], primary) for ex in exercises for m, primary in ex.muscles.items()])
    cur.executemany(
        "INSERT INTO exercise_compensation (exercise_id, compensation_exercise_id) VALUES (%s, %s)",
        [(ids[ex.name], ids[c]) for ex in exercises for c in ex.compensations])

    # only progressions are stored; variations come from family membership
    cur.executemany(
        """INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, type, is_manual)
           VALUES (%s, %s, 'progression', %s)""",
        sorted((ids[e], ids[h], manual) for (e, h), manual in edges.progressions.items()))


def summarize(cur, exercises: list[Exercise], edges: Edges,
              counts: dict[str, int], update: bool) -> dict[str, int]:
    # variation pairs as the database sees them (view over family membership)
    cur.execute("""SELECT count(DISTINCT (exercise_id, variation_id)) / 2,
                          (SELECT count(*) FROM exercise_relation r
                            WHERE EXISTS (SELECT 1 FROM v_exercise_variation v
                                           WHERE v.exercise_id = r.from_exercise_id
                                             AND v.variation_id = r.to_exercise_id))
                     FROM v_exercise_variation""")
    variation_pairs, in_both = cur.fetchone()
    summary = {
        "exercises in the sheet": len(exercises),
        "  of them inactive": sum(not ex.is_active for ex in exercises),
    }
    if update:
        summary.update({
            "  added": counts["added"],
            "  changed": counts["changed"],
            "  unchanged": counts["unchanged"],
            "not in the sheet: deleted": counts["deleted"],
            "not in the sheet: deactivated (used)": counts["deactivated"],
        })
    summary.update({
        "families": len({fam for ex in exercises for fam in ex.families}),
        "family memberships": sum(len(ex.families) for ex in exercises),
        "joint links": sum(len(ex.joints) for ex in exercises),
        "muscle links": sum(len(ex.muscles) for ex in exercises),
        "compensations": sum(len(ex.compensations) for ex in exercises),
        "variation pairs (shared family, not stored)": variation_pairs,
        "automatic progressions": sum(not m for m in edges.progressions.values()),
        "manual progressions": sum(edges.progressions.values()),
        "  of them replacing an automatic one": len(edges.overridden),
        "pairs in both graphs": in_both,
    })
    return summary


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import the Kinetune exercise library from the spreadsheet (.xlsx).")
    parser.add_argument("file", type=Path, help="library workbook, e.g. db/library/kinetune_library.xlsx")
    parser.add_argument("--dry-run", action="store_true", help="validate and print the summary, write nothing")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--replace", action="store_true",
                      help="delete the library and import again (refused if any plan uses its exercises)")
    mode.add_argument("--update", action="store_true",
                      help="apply the sheet to the existing library by exercise name; keeps ids used by plans")
    args = parser.parse_args(argv)

    try:
        wb = openpyxl.load_workbook(args.file, read_only=True, data_only=True)
    except Exception as exc:                                  # noqa: BLE001 - any read error stops here
        print(f"ERROR   cannot open {args.file}: {exc}")
        return 2

    try:
        conn = psycopg.connect(os.environ.get("DATABASE_URL", ""))
    except psycopg.Error as exc:
        print(f"ERROR   cannot connect to the database: {exc}")
        return 2

    report = Report()
    summary: dict[str, int] | None = None
    stop_reason: str | None = None
    edges: Edges | None = None
    try:
        with conn, conn.transaction() as tx, conn.cursor() as cur:
            cur.execute("SET LOCAL search_path TO kinetune")
            ref = load_reference(cur)
            exercises = read_library(wb, ref, report)
            check_library_links(exercises, report)
            manual = read_progressions(wb, {ex.name for ex in exercises}, report)
            edges = derive_edges(exercises, manual, report)
            count = lock_library(cur)
            if args.update:
                check_update(cur, exercises, report)
            if report.errors:
                raise psycopg.Rollback(tx)
            if not args.update:
                stop_reason = prepare_replace(cur, count, args.replace)
                if stop_reason:
                    raise psycopg.Rollback(tx)
            ids, family_ids, counts = write_exercises(cur, exercises)
            if args.update:
                clear_links(cur, list(ids.values()))
                remove_missing(cur, ids, counts, report)
            else:
                clear_links(cur)              # leftovers of a library emptied by hand
            write_links(cur, exercises, ids, family_ids, edges, ref)
            # families that are no longer used by any exercise
            cur.execute("""DELETE FROM exercise_family f
                            WHERE NOT EXISTS (SELECT 1 FROM exercise_family_member m WHERE m.family_id = f.id)""")
            summary = summarize(cur, exercises, edges, counts, args.update)
            if args.dry_run:
                raise psycopg.Rollback(tx)
    except psycopg.Error as exc:
        diag = exc.diag
        detail = f" (constraint {diag.constraint_name})" if diag and diag.constraint_name else ""
        report.print()
        print(f"ERROR   database: {diag.message_primary if diag and diag.message_primary else exc}{detail}")
        print("Nothing was written.")
        return 1
    except RuntimeError as exc:
        print(f"ERROR   {exc}")
        return 2
    finally:
        wb.close()

    report.print()
    if report.errors or stop_reason:
        if stop_reason:
            print(f"ERROR   {stop_reason}")
        print(f"{len(report.errors) + bool(stop_reason)} error(s), {len(report.warnings)} warning(s). Nothing was written.")
        return 1

    for mp, (e, h) in edges.overridden:
        print(f"INFO    {PROGRESSIONS_SHEET}, row {mp.row}: manual {mp.easier} -> {mp.harder} replaces automatic {e} -> {h}")
    action = "updated" if args.update else "imported"
    title = f"Dry run passed, library would be {action} (nothing written)" if args.dry_run else f"Library {action}"
    print(f"{title}. {len(report.warnings)} warning(s).")
    width = max(len(k) for k in summary)
    for key, value in summary.items():
        print(f"  {key:<{width}}  {value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

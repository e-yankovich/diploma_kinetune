# Kinetune — Exercise Library Import

The exercise library is kept by the author in a spreadsheet. The import script loads it into the database and builds the two exercise graphs: the **variation graph** is the family membership itself (a star around each family, nothing stored per pair), and the **progression graph** is derived from exercise attributes and stored as directed edges.

| | |
|---|---|
| Script | `db/library/import_library.py` (Python, openpyxl + psycopg) |
| Input | The workbook `db/library/kinetune_library.xlsx` (sheets "Library" and "Progressions (manual)") |
| Writes | `exercise`, `exercise_family`, `exercise_family_member`, `exercise_joint`, `exercise_muscle`, `exercise_compensation`, `exercise_relation` (progressions only) |
| Needs | Migrations applied (reference data: joints, muscles); a role with `app_admin` rights on the library tables (`kinetune_admin`) |
| Transaction | One. Any problem → nothing is written and **all** problems are printed together |

---

## 1. Running the import

### 1.1 With Docker Compose (recommended)

From the repository root, after `docker compose up -d` (database + migrations):

```bash
# validate only, write nothing
docker compose --profile import run --rm import-library /data/kinetune_library.xlsx --dry-run

# import into an empty library
docker compose --profile import run --rm import-library

# apply a changed sheet to the existing library (keeps the exercises plans use)
docker compose --profile import run --rm import-library /data/kinetune_library.xlsx --update

# delete the library and import again (refused if any plan uses its exercises)
docker compose --profile import run --rm import-library /data/kinetune_library.xlsx --replace
```

The service `import-library` uses the `migrate` image, mounts `db/library/` read-only at `/data` and connects as **`kinetune_admin`**: a login role that holds the group `app_admin` (library and reference data, no DDL; password `ADMIN_PASSWORD` in `.env`). It starts only after `migrate` has finished.

### 1.2 Without Docker

```bash
pip install -r db/requirements.txt
DATABASE_URL="postgresql://<role>@localhost:5432/kinetune" \
  python db/library/import_library.py db/library/kinetune_library.xlsx --dry-run
```

`DATABASE_URL` may be a libpq URL or a `key=value` string. If it is not set, the standard libpq variables are used (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`), so a password never has to be written into a URL.

### 1.3 Options and exit codes

| Option | Effect |
|---|---|
| (none) | Import into an **empty** library. If the library already has exercises, the script stops. |
| `--update` | Apply the sheet to the existing library, matching exercises **by name** (section 1.5). Exercise ids are kept, so plans and recommendations stay valid. |
| `--replace` | Delete the library rows (exercises, families, joint/muscle links, compensations, relations) and import again, in the same transaction. Refused if any `plan_item` references an exercise. |
| `--dry-run` | Run everything (validation, derivation, inserts, database constraints) and roll back. Prints the summary. Can be combined with `--update` or `--replace`. |

`--update` and `--replace` cannot be used together.

| Exit code | Meaning |
|---|---|
| 0 | Imported, or dry run passed |
| 1 | Validation or database errors; nothing written |
| 2 | The file or the database cannot be opened, or reference data is missing |

### 1.4 Exporting the sheet

Keep the workbook as `.xlsx` (File → Download → Microsoft Excel in Google Sheets, or Save As `.xlsx` in Excel/LibreOffice) and put it in `db/library/`. Formulas are read as their last calculated values. The workbook is not part of the Docker image; it is mounted when the import runs.

### 1.5 Updating a library that plans already use (`--update`)

Once the coach has built plans, the library cannot be deleted (`--replace` is refused), but the sheet can still change. `--update` applies it in one transaction:

| Sheet vs database | What happens |
|---|---|
| Exercise in both (same name) | Its attributes are updated **in place**; the id stays, so plan items and recommendations keep pointing to it. Its joints, muscles, families and compensations are rebuilt from the sheet. |
| Exercise only in the sheet | Inserted (new id). |
| Exercise only in the database, **not used** by any plan item or recommendation | Deleted. |
| Exercise only in the database, **used** | Deactivated (`is_active = false`, warning) and kept with its joints, muscles, families and compensations, so old plans and sessions can still be checked (BR1–BR9). It is never offered as a candidate. If it comes back to the sheet later, it is matched by name and reactivated by the sheet. |
| Families | New names are created; families left without members are deleted. |
| Progression edges | Always rebuilt from the sheet (they are derived data). An exercise that is not in the sheet gets no edges. Variations need no rebuild: they follow the family membership. |

Rules that protect existing plans:
- An exercise that existing plans use with `side` left/right cannot become symmetric (DQ25): error, nothing written.
- Renaming an exercise in the sheet means a new exercise: the old name is deleted, or deactivated if it is used.
- Changing an exercise changes the calculated values (duration, plan check) of the plans that use it; the library is the single source of exercise data (data dictionary §7).

The summary also shows how many exercises were added, changed, unchanged, deleted and deactivated.

---

## 2. Sheet format

### 2.1 Sheet "Library"

Header in row 1, one exercise per row. Empty rows are skipped (a row with only Notes counts as empty). Text is trimmed; a leading apostrophe (a number stored as text, e.g. `'1`) is removed. Column order does not matter; columns are found by their header.

| Column(s) | Meaning → database | Rules |
|---|---|---|
| Name | `exercise.name` | Required, unique (also ignoring case), ≤ 120 characters. **The reference key** for compensations and manual progressions. |
| Description | `exercise.description` | Optional |
| Family 1–3 | Family names → `exercise_family` (created if new) + `exercise_family_member` | Optional; the same family twice in a row is an error |
| Mode | `exercise.mode` | `dynamic`, `static` or `stato_dynamic` |
| Starting pose | `exercise.starting_pose` | Sheet labels with spaces become enum codes: `downward dog` → `downward_dog`, `front split` → `front_split`. Allowed: seated, standing, balance, quadruped, downward dog, supine, prone, kneeling, front split. |
| Symmetric | `exercise.is_symmetric` | `yes` / `no` |
| Difficulty | `exercise.difficulty` | 1, 2 or 3 (text `'1` is accepted) |
| Rep duration (sec) | `exercise.rep_duration_sec` | Whole number > 0; fractions are rejected |
| Compensation exercise 1–4 | Exercise names → `exercise_compensation` | Must exist in the sheet and be active; not the exercise itself |
| Active | `exercise.is_active` | `yes` or empty → true; `no` → false |
| Main joint 1–2 | Joint names → `exercise_joint` (`is_primary = true`) | Names as in the reference data (lower case) |
| Secondary joint 1–3 | Joint names → `exercise_joint` (`is_primary = false`) | |
| Load: *joint* (11 columns: cervical spine, shoulder, elbow, wrist, fingers, thoracic spine, lumbar spine, hip, knee, ankle, foot) | `exercise_joint.load_level` for that joint | `low` / `medium` / `high`; filled exactly for the listed joints |
| Main muscle 1–4 | Muscle names → `exercise_muscle` (`is_primary = true`) | The stretched (target) muscle |
| Secondary muscle 1–3 | Muscle names → `exercise_muscle` (`is_primary = false`) | |
| Notes | — | Ignored |

The numbers in the column names exist only for the sheet. In the database each filled cell becomes one row of a junction table; only main vs secondary (`is_primary`) is stored.

### 2.2 Sheet "Progressions (manual)"

| Column | Meaning |
|---|---|
| A — Easier exercise (A) | Exercise name |
| B — Harder exercise (B) | Exercise name |
| C — Check, D — Notes | Ignored (C is a check formula in the sheet) |

Each filled row becomes a progression A → B with `is_manual = true`. Rows with both A and B empty are skipped; an empty sheet is fine. If the sheet is missing, the import warns and continues.

### 2.3 Sheet "Body parts"

Not imported: body areas, joints and muscles are reference data loaded by migration 0002 (`test_data.md` §1). The import only checks that every joint and muscle name used in "Library" exists in the database.

---

## 3. Validation

All problems are collected and printed together, each with sheet, row, column and value, for example:

```text
ERROR   Library, row 4, column "Main joint 1", value 'ankel': unknown joint (did you mean "ankle"?)
ERROR   Library, row 6, column "Load: knee", value 'medium': load is filled for the joint "knee", which is not listed as a main or secondary joint of this row
WARNING Library, row 47, column "Family", value 'hip mobility': family has only one exercise, so its member has no variations through it (check the spelling?) (DQ35)
```

| Check | Level |
|---|---|
| Required columns present; no duplicate headers; unknown columns | error / warning (unknown column) |
| Name missing, too long, or duplicated | error |
| Family name too long; unknown mode, starting pose, joint or muscle; bad yes/no, difficulty or rep duration (incl. fractions) | error |
| The same family, joint or muscle twice in one row (joint/muscle: main and secondary) | error |
| A load filled for a joint that is not listed; a listed joint without a load | error |
| Neither a main joint nor a main muscle (DQ09). Relaxation exercises with main joints at `low` load and no muscles are valid. | error |
| Compensation: name not in the sheet, the exercise itself, an inactive exercise (DQ27), a two-exercise loop A ↔ B (DQ26) | error |
| Manual progression: name not in the sheet, A = B, one side empty, the opposite manual progression also listed, a cycle with all progressions | error |
| A family with fewer than 2 exercises (DQ35) — often a typo in the family name | warning |
| An exercise without a family (it can only be linked by manual progressions) | warning |
| Duplicate manual progression row | warning (ignored) |

After validation the rows are inserted; the database constraints (CHECK, UNIQUE, FK, the unique index per pair and type) are the final guarantee. A database error is printed with the constraint name and the whole import is rolled back.

Finally, inside the same transaction, the import runs `db/checks/data_quality_checks.sql` on the written data. An **error** row of a library check (DQ09, DQ10, DQ12, DQ14, DQ26, DQ27, DQ34) is printed as `ERROR   database checks, column "DQxx": …` and rolls the whole import back. Warning rows are not repeated here; run the checks file to see them.

---

## 4. Graph derivation

Business rules v2, "Exercise graphs". The two graphs are independent, a pair of exercises can be in both, and they are stored in two different structures:

| Graph | Meaning | Storage |
|---|---|---|
| Variation graph | Similarity: "another execution of the same movement", any level | A **star around each family** (bipartite exercise — family graph): `exercise_family` + `exercise_family_member`. Two exercises are variations **iff they share a family**. Nothing is stored per pair; the view `v_exercise_variation` lists the pairs. |
| Progression graph | Difficulty: "B is a harder version of A" | Directed edges in `exercise_relation` (`type = 'progression'`, `is_manual`) |

**Harder by an attribute.** Exercise B is harder than A by an attribute if:
- **difficulty**: B's difficulty is higher;
- **mode**: B's mode is later in the order dynamic < static < stato_dynamic;
- **balance**: B's starting pose is `balance` and A's is not;
- **joint load**: B has a higher load (low < medium < high) on some joint than A; a joint that A does not involve counts as no load.

B is *easier* by an attribute in the opposite cases. One attribute can make B both harder and easier (e.g. a higher load on the knee and a lower load on the hip).

**For every pair (A, B) that shares at least one family:**
1. the pair is a **variation**, implicitly through the family (no row is written);
2. **in addition**, if B is harder by at least one attribute and easier by none → a stored **progression** A → B (`is_manual = false`); in the opposite case → B → A;
3. harder by one attribute and easier by another → variation only.

The result depends only on the two exercises, so a pair that shares two families gets at most one progression. "Harder" is a strict comparison, so automatic progressions never form a cycle.

**Manual progressions** (sheet "Progressions (manual)") add a progression A → B with `is_manual = true`; if the two exercises share a family, they stay variations as well.
- Same direction as an automatic progression → the existing edge is marked manual (one progression per pair).
- Opposite direction → the manual edge replaces the automatic one (expert judgement wins); the import prints an `INFO` line.
- A manual progression that would create a cycle (with all progressions, automatic and manual) is an error.

Example (family "ankle mobility"): every pair is a variation; in addition Ankle Circles – Seated → Ankle Circles – Standing is a progression (balance on one leg). Ankle Circles – Standing and Ankle Flexion and Extension – Standing are a variation only: the standing circles need balance, the flexion/extension puts a load on the foot.

**How the backend searches candidates** (BR11; for reference): variations = members of the original's families (one hop through the family, no recursion); regressions = progressions followed backwards, up to 2 steps, with a cycle guard; a progression of the original (a harder version) is never offered, even if it is also a variation.

**Summary.** At the end the script prints: exercises (and inactive; with `--update` also added, changed, unchanged, deleted, deactivated), families, family memberships, joint links, muscle links, compensations, variation pairs (counted from `v_exercise_variation`, not stored), automatic progressions, manual progressions (and how many replace an automatic one), and pairs in both graphs.

---

## 5. Current library (import of 25 Nov 2026)

99 exercises (all active), 20 families, 150 family memberships, 228 joint links, 223 muscle links, 69 compensations; 595 variation pairs (derived from the families, not stored); 255 automatic progressions and 0 manual progressions stored in `exercise_relation`; all 255 progression pairs are also variations. Warnings: the families "hip mobility" and "wrist mobility" have one exercise each; this is intended by the author (DQ35 stays a warning).

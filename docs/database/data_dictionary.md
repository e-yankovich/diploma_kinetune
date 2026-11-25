# Kinetune — Data Dictionary

DBMS: PostgreSQL 18 · OLTP · normalised to 3NF · all objects in schema `kinetune` · DDL: `db/01_schema.sql`, `db/02_triggers.sql` (migration 0001) · v0.6

---

## 1. Conventions

| Topic | Convention |
|---|---|
| Names | `snake_case`, singular table names (`exercise`, not `exercises`). `app_user` is used because `user` is a reserved word in PostgreSQL. Junction tables are named `<owner>_<target>` (`exercise_muscle`). |
| Primary keys | Surrogate `id`, `GENERATED ALWAYS AS IDENTITY`. `smallint` for small reference tables, `integer` elsewhere. Junction tables use a composite PK of their two FKs. Exception: `rule.id` is set explicitly (1–11 = BR1–BR11). |
| Foreign keys | `<referenced_table>_id`. Every FK has an explicit `ON DELETE` rule (§5). |
| Time | `timestamptz`, stored in UTC and shown to the coach in Europe/Vilnius time. Creation time defaults to `now()`. |
| Text | `varchar(n)` where a length limit is part of the rule (names, e-mail), `text` for free text. |
| Enumerations | PostgreSQL `ENUM` types for small value sets fixed by the thesis (§3). Lists that the coach or the author may extend (body areas, muscles, joints) are tables. |
| Booleans | Always `NOT NULL` with a default, so a boolean never has a third "unknown" state. |
| Enforcement codes | **C** = constraint (PK/FK/UNIQUE/CHECK/NOT NULL) · **T** = trigger or DB function · **A** = application (API validation) · **Q** = data-quality check query, run in tests and after imports |

---

## 2. Layers and subject areas

**Layers.** The database has one layer: the operational core (OLTP). The application writes to it directly, and there are no raw, staging or analytical copies of the data. Reasons:

- The volume is small (one coach, about 100 exercises, a few hundred sessions per year at most).
- All reporting (KPIs K1–K4) can be computed from the same tables with views, so a separate analytical layer is not justified.
- Reference data is loaded by a migration (SQL in Git). The exercise library is loaded from the author's spreadsheet export by the library import script (`db/library/`, see `library_import.md`), which validates every row before it writes anything. These files act as the "source" layer outside the database.

**Subject areas** (logical grouping within the core):

| Area | Tables | Written by | Sensitivity |
|---|---|---|---|
| Reference | `body_area`, `muscle`, `joint`, `rule` | Migration 0002 (`03_reference_data.sql`) | None |
| Exercise library | `exercise`, `exercise_muscle`, `exercise_joint`, `exercise_family`, `exercise_family_member`, `exercise_compensation`, `exercise_relation` | Library import (author's spreadsheet) | None |
| Access control | `app_user`, `role`, `permission`, `role_permission`, `user_role` | Seed files; admin UI | `app_user`: **personal data** (e-mail, password hash) |
| Planning | `plan`, `plan_item`; views `v_plan_item`, `v_session_plan` (§7) | Coach UI | None |
| Sessions and participant input | `session`, `checkin`, `checkin_discomfort`, `feedback` | Coach UI; participant forms (anonymous) | Check-ins: **anonymous health-related answers** (no identifiers stored) |
| Recommendations | `recommendation`, `recommendation_decision` | Recommendation engine; coach UI | Derived from aggregated check-ins |

### Expected volumes

| Table | Expected rows (first year) |
|---|---|
| `body_area` | 10 (7 in the check-in) |
| `muscle` | 28 |
| `joint` | 11 |
| `rule` | 11 |
| `exercise` | ~100 (99 in the current library) |
| `exercise_muscle`, `exercise_joint` | ~230 each |
| `exercise_family` | ~20 |
| `exercise_family_member` | ~150 |
| `exercise_compensation` | ~70 |
| `exercise_relation` | ~250 (progressions only; ~600 variation pairs are derived from families, not stored) |
| `app_user` | 1–2 (the author can hold both roles in one account) |
| `role` | 2 (3 when `client` is added) |
| `permission` | 10–15 |
| `role_permission` | 15–25 |
| `user_role` | 1–3 |
| `plan` | 10–30 |
| `plan_item` | 15–25 per plan |
| `session` | up to ~150 (3 in the pilot) |
| `checkin` | up to ~8 per session (groups of 5–8) |
| `checkin_discomfort` | 0–3 per check-in |
| `feedback` | 0–8 per session |
| `recommendation` | 0–5 per session |

---

## 3. Enumerated types

| Type | Values | Meaning |
|---|---|---|
| `phase` | `warm_up`, `main`, `cool_down` | Part of the class a plan item belongs to |
| `exercise_mode` | `dynamic`, `static`, `stato_dynamic` | How the exercise is performed. `dynamic`: continuous movement (BR2: only these in the warm-up; BR4: only these count as the dynamic exercise that must precede a static one). `static`: holding a position (BR4; BR5: static ≤ 40 % of the main part). `stato_dynamic`: a hold combined with small movements; not allowed in the warm-up (BR2), does not count as dynamic in BR4 and is not counted as static in BR5. Order used by the graph derivation: dynamic < static < stato_dynamic (§4.2). |
| `starting_pose` | `seated`, `standing`, `balance`, `quadruped`, `downward_dog`, `supine`, `prone`, `kneeling`, `front_split` | Starting position, as used in the library. Only `balance` has a meaning in the rules: BR9/BR10 (balance exercises are affected by low energy or poor sleep), BR11 (the cascade looks for a candidate without balance) and the graph derivation (balance makes an exercise harder). The other values are for display and filtering. |
| `side` | `left`, `right`, `both` | Which side a plan item is performed on. `both`: both sides within one item. An asymmetric exercise can also be planned as two items, `left` and `right` (BR7). |
| `relation_type` | `progression` | Type of a stored graph edge. Only `progression` exists: a harder version (the target is harder by at least one attribute and easier by none, or a manual progression); the reverse direction is a regression. Variations are **not** stored as edges: two exercises are variations iff they share a family (`v_exercise_variation`, §7). One pair can be both (shared family + progression). Criteria in §4.2. |
| `load_level` | `low`, `medium`, `high` | How much an exercise loads a joint (`exercise_joint.load_level`). BR9/BR10 react to `high`; the BR11 cascade looks for no load, then a lower load; the graph derivation compares loads (§4.2). |
| `energy_level` | `low`, `normal`, `high` | Self-rated energy in the check-in. `low` is the low-energy factor of BR9/BR10. |
| `plan_status` | `draft`, `completed`, `reviewed` | `draft`: the coach is building the plan. `completed`: the coach finished building it (a target duration is required). `reviewed`: the BR1–BR8 check was run on the plan and the coach reviewed the result. Allowed transitions: draft → completed → reviewed, and back to `draft` from any status. Any change to the plan or its items moves it back to `draft` (**T**). Details in §4.4. |
| `session_status` | `open`, `closed`, `reviewed`, `done` | `open`: check-in link accepts answers. `closed`: the coach closed the check-in (US3.2), entered the number of participants present, and recommendations are generated. `reviewed`: the coach has decided on every recommendation and the concrete plan was checked again with BR1–BR8. `done`: the class took place and attendance has been entered. Allowed transitions: open → closed → reviewed → done. Details in §4.5. |
| `recommendation_form` | `alternative`, `replacement` | What the triggered rule called for: BR9 alternative (shown next to the original), BR10 replacement |
| `explanation_source` | `template`, `llm` | Where the explanation text came from. `template` is also the fallback when the LLM fails (NFR9). |
| `decision_type` | `accepted`, `declined` | The coach's response to a recommendation. Warnings (BR11) are decided too: `accepted` = the coach applies the general advice, `declined` = not. |

---

## 4. Tables

Column legend: **Null** = whether NULL is allowed · **Key**: PK, FK → table, UQ = unique.

### 4.1 Reference

#### `body_area`
A body part. It consists of muscles and joints, which link check-in discomfort to exercises. Only the body parts marked `is_in_checkin` are shown in the check-in form.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `code` | varchar(32) | no | UQ | | Stable machine code, e.g. `lower_back`, `knee`. Lower-case letters and `_` only: CHECK `code ~ '^[a-z_]+$'`. |
| `name_en` | varchar(64) | no | | | Label on the English participant form |
| `name_ru` | varchar(64) | no | | | Label on the Russian participant form |
| `is_in_checkin` | boolean | no | | `false` | `true` = shown in the check-in form. Joints of body parts outside the check-in never trigger BR9/BR10. |

Data quality: every area has at least one muscle or joint (**Q**, DQ10); every area in the check-in has at least one joint (**Q**, DQ34). Both labels are non-empty after trimming (**C**: CHECK `btrim(name_en) <> ''`, same for `name_ru`).

#### `muscle`
| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `name` | varchar(64) | no | UQ | | English name in lower case, e.g. `hamstrings`. The library import matches muscles by this name. |
| `body_area_id` | smallint | no | FK → `body_area` | | The area this muscle belongs to (exactly one) |

#### `joint`
| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `name` | varchar(64) | no | UQ | | English name in lower case, e.g. `knee`. The library import matches joints by this name. |
| `body_area_id` | smallint | no | FK → `body_area` | | The area this joint belongs to (exactly one) |

#### `rule`
The business rules BR1–BR11 from thesis Table 2.7. Recommendations refer to the rule that produced them.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | (set explicitly) | 1–11, equal to the BR number. CHECK `id BETWEEN 1 AND 11`. |
| `description` | text | no | | | The rule's logic (business rules v2) |
| `explanation` | text | no | | | Template explanation shown to the coach with a recommendation, with placeholders the backend fills (e.g. `{exercise}`, `{body_area}`, `{share}`). Also used as the fallback when the LLM fails. |

Data quality: exactly 11 rows, ids 1–11 (**Q**, DQ14). The texts are loaded by migration 0002; the full list is in `test_data.md` §1.

**Placeholders in `explanation`.** The backend replaces them; a template never contains participant data, only counts and names from the library.

| Placeholder | Filled with | Used by |
|---|---|---|
| `{exercise}` | Name of the exercise in the plan | BR2–BR7, BR9–BR11 |
| `{phase}` | warm-up / main part / cool-down | BR3, BR7 |
| `{problem}` | Short description of what is wrong (e.g. "the cool-down is missing", "none follows", "the nearest one comes 7 exercises later") | BR1, BR6 |
| `{mode}` | static / stato-dynamic | BR2 |
| `{share}` | Percentage, rounded to a whole number | BR5, BR9, BR10 |
| `{options}` | Names of the acceptable compensating exercises | BR6 |
| `{side}` | left / right | BR7 |
| `{plan_minutes}`, `{target_minutes}` | Calculated plan duration and `plan.target_duration_min` | BR8 |
| `{affected}`, `{base}` | Participants who reported the factor; the base (participants present, or check-ins if higher) | BR9, BR10 |
| `{factor}` | "discomfort in the {body area}", "low energy" or "poor sleep" | BR9–BR11 |
| `{candidate}` | Name of the proposed exercise | BR9, BR10 |
| `{reason}` | Why the candidate fits, from the cascade step: e.g. "same level, another execution", "a gentler version of the same stretch", "no load on the knee", "no balance needed" | BR9, BR10 |

### 4.2 Exercise library

#### `exercise`
| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `name` | varchar(120) | no | UQ | | English name shown in the coach UI |
| `description` | text | yes | | | Execution notes |
| `mode` | exercise_mode | no | | | Dynamic, static or stato-dynamic (BR2, BR4, BR5) |
| `starting_pose` | starting_pose | no | | | One of the nine library poses (§3); only `balance` is used by the rules |
| `is_symmetric` | boolean | no | | `true` | `true` when both sides do the same movement at the same time, and for exercises whose name says "Alternating" or "Side-to-Side" (one item covers both sides). `false` = asymmetric: performed on one side and then the other, and both sides must be done in the same phase (BR7). |
| `difficulty` | smallint | no | | | 1 = easy, 2 = medium, 3 = hard. CHECK `difficulty BETWEEN 1 AND 3`. |
| `rep_duration_sec` | smallint | no | | | Whole seconds for **one** repetition (library values: 2, 4, 15). For a static exercise one repetition = one hold. CHECK `> 0`. Item durations are calculated from it (§7). |
| `is_active` | boolean | no | | `true` | Soft delete. Inactive exercises stay in old plans and recommendations but cannot be added to new plans or offered as candidates. |
| `created_at` | timestamptz | no | | `now()` | |

Data quality: every active exercise has at least one main joint or main muscle (**Q**, DQ09); relaxation exercises have main joints with a `low` load and no muscles, which is valid. As a warning, every active exercise has at least one main joint (**Q**, DQ28). New plan items and candidates use active exercises only (**A**, DQ16). The name is unique and is the reference key of the library sheet (compensations, manual progressions).

#### `exercise_muscle`
Which muscles an exercise works (M:N).

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `exercise_id` | integer | no | PK, FK → `exercise` | | |
| `muscle_id` | smallint | no | PK, FK → `muscle` | | |
| `is_primary` | boolean | no | | `false` | `true` = main muscle = the muscle that is **stretched** (the target of the exercise), not the one that does the work; `false` = secondary. BR11 requires a candidate to share at least one main muscle. |

#### `exercise_joint`
Which joints an exercise involves (M:N), and how much it loads each of them.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `exercise_id` | integer | no | PK, FK → `exercise` | | |
| `joint_id` | smallint | no | PK, FK → `joint` | | |
| `is_primary` | boolean | no | | `false` | `true` = a main joint of the exercise, i.e. what the exercise is "about". Used for sorting, filtering and display in the library. Not used by the rules. |
| `load_level` | load_level | no | | | How much the exercise loads this joint: `low`, `medium` or `high`. Filled for every listed joint, main or secondary; a joint that is not listed is not involved. |

`is_primary` and `load_level` are independent. Example: a deep lunge has the hip as its main joint, but it also puts a high load on the knee. Its knee row is `is_primary = false`, `load_level = 'high'`.

How the rules use `load_level` (main and secondary joints alike):
- **BR9 / BR10**: an exercise needs attention when participants report discomfort in a body part and the exercise has `load_level = 'high'` on a joint of that body part.
- **BR11 cascade**: first a candidate with no load on the joint(s) of that body part (no row), then one with a lower load, then any regression.
- **Graph derivation**: a higher load on some joint makes an exercise harder (below).

Both values are assigned by the coach when compiling the library. They are expert estimates, the same approach as `exercise.difficulty` (1–3).

#### `exercise_family`
A movement family: exercises that can stand in for each other, e.g. "ankle mobility" = ankle circles and ankle flexion/extension, seated and standing. Entered by the coach in the library sheet (columns "Family 1–3"); created by the library import.

**The variation graph is stored here, as a star around each family** (a bipartite graph exercise — family): `exercise_family` is the hub, `exercise_family_member` the spokes. Two exercises are variations **iff they share a family**. Pairwise variation edges are not stored: they would be fully derivable from the membership (redundant data, update anomalies). The view `v_exercise_variation` (§7) lists the pairs when they are needed (explanations, debugging).

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `name` | varchar(64) | no | UQ | | CHECK `btrim(name) <> ''`. A reference table, so a typo cannot create a second family. |

Data quality: a family should have at least 2 exercises (**Q**, DQ35, warning). A family with one exercise is allowed in the MVP: its member has no variations through it. Members should share at least one main muscle (BR11).

#### `exercise_family_member`
Which families an exercise belongs to (M:N). An exercise may belong to up to three families (a limit of the sheet, not of the database).

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `exercise_id` | integer | no | PK, FK → `exercise` | | |
| `family_id` | smallint | no | PK, FK → `exercise_family` | | |

Index: (`family_id`), for "members of family X" in the candidate search.

#### `exercise_compensation`
The acceptable compensating exercises of an exercise (BR6, M:N). **BR6 is satisfied if any one of the listed exercises follows** the exercise before the end of class; if none does, the warning lists them as options. An exercise without rows needs no compensation. Compensation is set only where it is really needed (all difficulty-3 exercises and static difficulty-2 exercises, with exceptions decided by the author), because every listed exercise always carries the requirement.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `exercise_id` | integer | no | PK, FK → `exercise` | | The exercise that needs compensation |
| `compensation_exercise_id` | integer | no | PK, FK → `exercise` | | One acceptable compensating exercise. CHECK `exercise_id <> compensation_exercise_id`. |

Index: (`compensation_exercise_id`), for "which exercises does X compensate" and the RESTRICT check on delete.
Data quality: no two-exercise loop, i.e. A compensated by B and B compensated by A (**Q**, DQ26); a compensating exercise is active (**Q**, DQ27). In the sheet: columns "Compensation exercise 1–4" (exercise names); the import writes one row per filled cell.

#### `exercise_relation`
The **progression graph**: directed edges easier → harder, used to find regressions (`WITH RECURSIVE`, depth ≤ 2). It is one of the two exercise graphs of the thesis; they describe two **independent** relations over the same exercises and are stored in two different structures:
- **Variation graph** (similarity, undirected): "another execution of the same movement", at any level. Stored as a star around each family (`exercise_family` + `exercise_family_member`), not in this table.
- **Progression graph** (difficulty, directed): "B is a harder version of A". Stored here. Followed backwards it gives regressions; steps along it are levels.

**One pair can be in both graphs** (a shared family and a progression edge). Example: Ankle Circles Seated and Ankle Circles Standing are variations (same family) **and** Standing is a progression of Seated (balance on one leg). Ankle Circles Standing and Ankle Flexion and Extension Standing are only variations. The search combines the graphs: "same level" = a variation with no progression in either direction; "a gentler version of the same stretch" = a variation that is also a regression; "an easier exercise from another family" = a manual regression only.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `from_exercise_id` | integer | no | FK → `exercise` | | The easier exercise |
| `to_exercise_id` | integer | no | FK → `exercise` | | The harder exercise. CHECK `from_exercise_id <> to_exercise_id` (no self-loops). |
| `type` | relation_type | no | | `progression` | Always `progression` (the only value) |
| `is_manual` | boolean | no | | `false` | `false` = derived by the library import from attributes; `true` = a manual progression from the sheet "Progressions (manual)". Needed for the "no bridges" rule of BR11. |

Every edge is directed.

**How the graphs are derived** (business rules v2, "Exercise graphs"; details in `library_import.md`). Exercise B is **harder than A by an attribute** if: B's `difficulty` is higher; or B's `mode` is later in the order dynamic < static < stato_dynamic; or B's `starting_pose` is `balance` and A's is not; or B has a higher `load_level` on some joint than A (a joint A does not involve counts as no load). For every pair (A, B) that shares at least one family:
- the pair is a **variation**, implicitly through the family (nothing is stored per pair);
- **in addition**, if B is harder than A by at least one attribute and easier by none → a stored **progression** A → B (`is_manual = false`);
- harder by one attribute and easier by another → variation only (the levels cannot be compared).

"Harder" is a strict comparison, so derived progressions never form a cycle. **Manual progressions** (`is_manual = true`) cover what the attributes cannot detect (expert judgement, links between families). If the two exercises share a family, they stay variations as well. If the attributes say the opposite direction, the manual edge replaces the derived progression (expert judgement wins), so a pair never has progressions in both directions (DQ36).

**Candidate search** (BR11; implemented by the backend):
- **variations** = members of the original's families: one hop through the family, no recursion;
- **regressions** = progressions followed backwards, up to 2 steps, with a cycle guard;
- a candidate is **never a progression of the original** (a harder version), even if it is also a variation;
- **no bridges**: a candidate shares a family with the original or is linked to it by manual progressions. With the star storage this holds by construction for variations (one step through the hub, never two); the recursion is needed only for chains of progressions.

Keys and indexes: unique index `uq_exercise_relation_pair_type` on (`LEAST(from_exercise_id, to_exercise_id)`, `GREATEST(from_exercise_id, to_exercise_id)`, `type`): at most one progression per pair, whatever the direction (DQ36); it includes UNIQUE (`from_exercise_id`, `to_exercise_id`, `type`). Index (`to_exercise_id`) for the backward search (regressions); index (`from_exercise_id`, `type`) for the forward direction (future "harder alternatives").

Data quality:
- Progression edges form no cycle: an exercise cannot be harder than itself through a chain (**Q**, DQ12).
- For a progression edge, the target's difficulty is greater than or equal to the source's (**Q**, DQ17).
- No duplicate progression and no progressions in both directions (A → B together with B → A) (**C**, unique index, DQ36).

### 4.3 Access control

Role-based access control (RBAC): a user has one or more roles, a role has a set of permissions, and the API checks the permission behind each endpoint (**A**). The database stores the model and its integrity rules; it does not decide access per request.

These are **application roles** (who may do what in the platform). They are separate from **PostgreSQL roles** (`app_read`, `app_write`, `migrator`, …), which control what the backend's database connections may do and are described in `security_and_access.md`.

#### `app_user`
Every account that logs in: coaches and admins now, clients later. **Personal data.**

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `email` | varchar(254) | no | UQ | | Login. Stored in lower case so uniqueness is case-insensitive: CHECK `email = lower(email)`. Format is checked by the API (**A**). |
| `password_hash` | text | no | | | argon2id hash. The plain password is never stored or logged. |
| `display_name` | varchar(80) | no | | | Shown in the UI. CHECK `btrim(display_name) <> ''`. |
| `is_active` | boolean | no | | `true` | `false` = the account cannot log in. Used instead of deleting a user who owns plans or sessions. |
| `created_at` | timestamptz | no | | `now()` | |
| `last_login_at` | timestamptz | yes | | | Updated on successful login; NULL = never logged in |

#### `role`
| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `code` | varchar(32) | no | UQ | | Stable code used by the application: `coach`, `admin` (later `client`). CHECK `code ~ '^[a-z_]+$'`. |
| `name` | varchar(64) | no | | | Label shown in the admin UI |
| `description` | text | yes | | | |

#### `permission`
One action on one resource.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `code` | varchar(64) | no | UQ | | `<resource>.<action>`, e.g. `plan.write`. CHECK `code ~ '^[a-z_]+\.[a-z_]+$'`. The API refers to permissions by code. |
| `description` | text | no | | | What the permission allows |

#### `role_permission`
Which permissions each role has (M:N).

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `role_id` | smallint | no | PK, FK → `role` | | |
| `permission_id` | smallint | no | PK, FK → `permission` | | |

#### `user_role`
Which roles each user has (M:N). One person can be both coach and admin.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `user_id` | integer | no | PK, FK → `app_user` | | |
| `role_id` | smallint | no | PK, FK → `role` | | |
| `granted_at` | timestamptz | no | | `now()` | |
| `granted_by` | integer | yes | FK → `app_user` | | Admin who granted the role; NULL for the seed/bootstrap admin. Must hold the `admin` role (**T**, DQ23). |

Index: (`role_id`), for "who holds role X" (last-admin and coach-role checks).

#### Seed: roles and permissions

| Permission | Allows | coach | admin |
|---|---|:-:|:-:|
| `library.read` | View exercises, muscles, joints, relations | ✓ | ✓ |
| `library.write` | Add, edit or deactivate exercises and relations | | ✓ |
| `plan.read` | View own plans | ✓ | |
| `plan.write` | Create, edit, delete own plans | ✓ | |
| `session.manage` | Create sessions, share and close the check-in, enter attendance | ✓ | |
| `checkin.read_summary` | View aggregated check-in results of own sessions | ✓ | |
| `recommendation.decide` | Accept or decline recommendations | ✓ | |
| `feedback.read` | View feedback of own sessions | ✓ | |
| `report.read` | View KPI reports of own sessions | ✓ | |
| `user.manage` | Create, deactivate users; reset passwords | | ✓ |
| `role.manage` | Grant and revoke roles | | ✓ |
| `reference.write` | Edit body areas, muscles, joints, rule texts | | ✓ |

Notes:
- "Own" (plans, sessions) is checked by the API by comparing `coach_id` with the logged-in user.
- The admin does not see check-ins, feedback or recommendations. These are the coach's working data, so they are not needed for administration (data minimisation).
- **Adding the `client` role later** needs only new rows in `role`, `permission` and `role_permission`, plus new tables for whatever clients own (e.g. a link between a client account and their check-ins). Today check-ins are anonymous, so a client account would also need a new consent and legal basis (thesis 2.8).

### 4.4 Planning

#### `plan`
The **blueprint** of a class, built by the coach. It is checked with BR1–BR8 (the plan check) and reviewed by the coach before it can be used in a session.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `coach_id` | integer | no | FK → `app_user` | | Owner. The user must hold the `coach` role (**T**, DQ21). |
| `title` | varchar(120) | no | | | CHECK `btrim(title) <> ''` |
| `notes` | text | yes | | | |
| `target_duration_min` | smallint | yes | | | Planned length of the class in minutes. BR8 compares it with the calculated plan duration (±5 min); BR8 is skipped while it is empty. CHECK `target_duration_min > 0`. May be NULL only while the plan is a draft: CHECK `status = 'draft' OR target_duration_min IS NOT NULL` (DQ29). |
| `status` | plan_status | no | | `draft` | See below (**T**, DQ29) |
| `created_at` | timestamptz | no | | `now()` | |
| `updated_at` | timestamptz | no | | `now()` | Updated by a trigger on every change to the plan or its items (**T**) |

**Plan status.**
- A new plan starts as `draft` (**T**).
- `draft` → `completed`: the coach has finished building the plan. A target duration is required.
- `completed` → `reviewed`: the BR1–BR8 check was run on the blueprint and the coach reviewed its result. The rules are warnings and the coach decides (thesis 2.5), so the database does not enforce the rules themselves. It only enforces the order of the statuses.
- Any status → `draft`: the coach reopens the plan.
- **Any change** to the plan's items (insert, update, delete) or to a plan field (title, notes, target duration, owner) moves a `completed` or `reviewed` plan back to `draft`, because the check has to be run again (**T**). If one statement changes a field and the status together, the field change wins and the plan becomes `draft`.
- A session can be created only from a `reviewed` plan (**T**, DQ30).

**Lock.** As soon as any session uses a plan (in any session status), the plan is **locked** (**T**, DQ31): its items and all its fields (title, notes, target duration, status) can no longer change; only the technical `updated_at` is maintained. The plan of a past or running class therefore never changes afterwards. To change a locked plan, the coach duplicates it with `duplicate_plan()` (§7) and edits the copy, which starts as a new `draft`. `plan_is_locked(plan_id)` tells the UI whether a plan is locked. A locked plan is always `reviewed`, because sessions are created only from reviewed plans.

#### `plan_item`
One exercise in a plan, at a given position within a phase.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `plan_id` | integer | no | FK → `plan` | | |
| `exercise_id` | integer | no | FK → `exercise` | | |
| `phase` | phase | no | | | |
| `position` | smallint | no | | | Order within the phase, starting at 1. CHECK `position >= 1`. |
| `side` | side | no | | `both` | Left, right or both. For a symmetric exercise it must be `both` (**T**, DQ25). |
| `reps_count` | smallint | no | | | Number of repetitions: **per side** for an asymmetric exercise, **total** for a symmetric one (including "Alternating" / "Side-to-Side" exercises). For a static exercise: number of holds. No default: the coach enters it. CHECK `reps_count > 0`. |

The duration of an item is **calculated, not stored** (3NF): `reps_count × exercise.rep_duration_sec`, doubled when the exercise is asymmetric (`is_symmetric = false`) and `side = 'both'` (both sides in one item). The formula exists once, in `item_duration_sec()` (§7). The plan duration for BR8 is the sum over `v_plan_item`.

Keys: UQ (`plan_id`, `phase`, `position`), `DEFERRABLE INITIALLY DEFERRED` so items can be reordered within one transaction.
Data quality: positions within a phase are continuous 1..n with no gaps (**A**, checked by **Q**, DQ13). Each plan has at least one item in the `main` phase before it can be used in a session (**A**). Items of a locked plan cannot be inserted, changed or deleted (**T**, DQ31).

### 4.5 Sessions and participant input

#### `session`
One class. A session is the **concrete plan** of that class: the blueprint (`plan_id`) + the coach's decisions on this session's recommendations + metadata (time, group, check-ins, attendance). Nothing from the plan is copied: the concrete plan is calculated by the view `v_session_plan` (§7). It owns the check-in link.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `coach_id` | integer | no | FK → `app_user` | | Must be the plan's owner (**T**, DQ08) and hold the `coach` role (**T**, DQ21) |
| `plan_id` | integer | no | FK → `plan` | | Must be a `reviewed` plan when the session is created (**T**, DQ30). The plan is locked from then on (DQ31). |
| `group_name` | varchar(80) | no | | | Free label, e.g. "Tuesday evening". CHECK `btrim(group_name) <> ''`. |
| `starts_at` | timestamptz | no | | | Planned start of the class |
| `status` | session_status | no | | `open` | A new session starts as `open`; only forward transitions open → closed → reviewed → done (**T**, DQ04). See below. |
| `checkin_token` | varchar(43) | no | UQ | | Random 32-byte value, base64url-encoded. It is the check-in link (`<site>/checkin/<token>`); the QR code is drawn from the link by the frontend, so neither is stored. Not guessable and not derived from the id. CHECK `checkin_token ~ '^[A-Za-z0-9_-]{43}$'`. |
| `checkin_closed_at` | timestamptz | yes | | | Set when the coach closes the check-in. CHECK `(status = 'open') = (checkin_closed_at IS NULL)` (DQ04). |
| `participants_present` | smallint | yes | | | Entered by the coach when closing the check-in (participants present at that moment); the base for the BR9/BR10 shares, K2 and K4. CHECK `>= 0`. Required from `closed` on: CHECK `status = 'open' OR participants_present IS NOT NULL` (DQ05). It can be corrected later. |
| `created_at` | timestamptz | no | | `now()` | |

Indexes: (`starts_at`) for the session list and per-period KPIs; (`plan_id`) for the plan lock check.

**Session status `reviewed`.** The coach moves a session from `closed` to `reviewed` when they have decided on **every** recommendation of the session (warnings are decided too, see `decision_type`) and the concrete plan has been checked again with BR1–BR8. A trigger rejects `reviewed` while any recommendation has no decision (**T**, DQ32); a session with no recommendations can be marked `reviewed` right away. This status is **not stored derived data**: it records a step the coach took (the session review), and the trigger only checks that the step is allowed. Whether the BR1–BR8 re-check was run is checked by the backend, which sets the status only after running it.

#### `checkin`
One anonymous pre-class answer. There is no link to a person, IP address or device.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `session_id` | integer | no | FK → `session` | | Accepted only while the session is `open` (**T**, DQ03) |
| `energy` | energy_level | no | | | Self-rated energy: `low`, `normal` or `high` (as in the thesis). **"Low energy" in BR9/BR10 = `energy = 'low'`.** |
| `poor_sleep` | boolean | no | | | `true` = slept badly last night. The participant form defaults it to `false` (the thesis treats the question as optional; not answered = no poor sleep). |
| `language` | char(2) | no | | | Form language. CHECK `IN ('en', 'ru')`. |
| `submitted_at` | timestamptz | no | | `now()` | |

Index: (`session_id`) for the per-session aggregates.
Data quality: the number of check-ins may be higher than `participants_present` (someone checked in but did not come). This is allowed but reported by a check query, because it pushes K2 above 100 % (**Q**, DQ15).


#### `checkin_discomfort`
The body areas a participant marked as uncomfortable (0..n per check-in). Only body areas with `is_in_checkin = true` are offered by the form (**A**).

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `checkin_id` | integer | no | PK, FK → `checkin` | | |
| `body_area_id` | smallint | no | PK, FK → `body_area` | | |

#### `feedback`
Voluntary, anonymous feedback after class (E6, Should). The base for K4.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `session_id` | integer | no | FK → `session` | | Accepted only after the session is `closed` or `done` (**T**) |
| `rating` | smallint | no | | | 1 = very bad … 5 = very good. CHECK `BETWEEN 1 AND 5`. |
| `comment` | text | yes | | | Free text, max 1000 characters (CHECK `char_length(comment) <= 1000`). It may contain identifying details typed by the participant; the form asks participants not to include names. |
| `submitted_at` | timestamptz | no | | `now()` | |

### 4.6 Recommendations

#### `recommendation`
A suggestion generated for one plan item when the check-in is closed.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `session_id` | integer | no | FK → `session` | | |
| `plan_item_id` | integer | no | FK → `plan_item` | | Must belong to the session's plan (**T**, DQ01) |
| `rule_id` | smallint | no | FK → `rule` | | The BR that fired |
| `form` | recommendation_form | no | | | What the rule called for: alternative or replacement |
| `is_warning` | boolean | no | | `false` | `true` = no suitable substitute was found; the coach gets general advice instead. CHECK `is_warning = (candidate_exercise_id IS NULL)`. |
| `candidate_exercise_id` | integer | yes | FK → `exercise` | | The proposed substitute. NULL exactly when `is_warning`. Must differ from the plan item's exercise (**T**, DQ02). |
| `affected_count` | smallint | no | | | Number of check-ins that triggered the rule. CHECK `>= 0`. |
| `explanation` | text | no | | | Text shown to the coach. CHECK `btrim(explanation) <> ''`. |
| `explanation_source` | explanation_source | no | | | `llm`, or `template` (including the fallback when the LLM fails or is slower than 5 s) |
| `created_at` | timestamptz | no | | `now()` | |

Index: (`session_id`).
Data quality: recommendations are created only when the session is no longer `open` (**A**, DQ06).

#### `recommendation_decision`
The coach's accept/decline decision, at most one per recommendation (1:1). The accept rate is K3.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `recommendation_id` | integer | no | PK, FK → `recommendation` | | PK and FK at the same time, which enforces 1:1 |
| `decision` | decision_type | no | | | |
| `decided_at` | timestamptz | no | | `now()` | Not earlier than the recommendation's `created_at` (**T**, DQ07) |

A recommendation with no decision row has not been answered yet. Warnings (BR11) get a decision like any other recommendation, so a session can be marked `reviewed` only when every row has one (DQ32).

At most one replacement can be accepted per plan item and session (**T**, DQ33), so the concrete plan has exactly one exercise per item. Accepting an alternative does not change the concrete plan; it is shown next to the original.

---

## 5. Relationships and delete behaviour

The rule: deleting a session removes everything collected for it (supports data minimisation); reference and library data cannot be deleted while in use (exercises are deactivated instead).

| Child.column | Parent | ON DELETE | Reason |
|---|---|---|---|
| `muscle.body_area_id`, `joint.body_area_id` | `body_area` | RESTRICT | Reference data in use |
| `exercise_muscle.exercise_id`, `exercise_joint.exercise_id`, `exercise_family_member.exercise_id`, `exercise_compensation.exercise_id` | `exercise` | CASCADE | Junction rows belong to the exercise |
| `exercise_compensation.compensation_exercise_id` | `exercise` | RESTRICT | An exercise listed as a compensation cannot be deleted; deactivate it instead |
| `exercise_family_member.family_id` | `exercise_family` | RESTRICT | A family with members cannot be deleted |
| `exercise_muscle.muscle_id` | `muscle` | RESTRICT | Reference data in use |
| `exercise_joint.joint_id` | `joint` | RESTRICT | Reference data in use |
| `exercise_relation.from_/to_exercise_id` | `exercise` | CASCADE | An edge is meaningless without both ends |
| `plan.coach_id`, `session.coach_id` | `app_user` | RESTRICT | A user who owns data cannot be deleted; deactivate instead (`is_active = false`) |
| `role_permission.role_id` | `role` | CASCADE | The role's permission list goes with the role |
| `role_permission.permission_id` | `permission` | CASCADE | A removed permission is removed from all roles |
| `user_role.user_id` | `app_user` | CASCADE | Role assignments go with the user |
| `user_role.role_id` | `role` | RESTRICT | A role still assigned to users cannot be deleted |
| `user_role.granted_by` | `app_user` | SET NULL | The assignment stays valid if the granting admin is removed |
| `plan_item.plan_id` | `plan` | CASCADE | Items belong to the plan |
| `plan_item.exercise_id` | `exercise` | RESTRICT | Use `is_active = false` instead |
| `session.plan_id` | `plan` | RESTRICT | Keeps session history interpretable; the plan is also locked (DQ31) |
| `checkin.session_id`, `feedback.session_id`, `recommendation.session_id` | `session` | CASCADE | Session data is deleted together with the session |
| `checkin_discomfort.checkin_id` | `checkin` | CASCADE | |
| `checkin_discomfort.body_area_id` | `body_area` | RESTRICT | |
| `recommendation.plan_item_id` | `plan_item` | RESTRICT | Keeps history. Items of a plan with sessions cannot be deleted anyway (plan lock, DQ31). |
| `recommendation.rule_id` | `rule` | RESTRICT | |
| `recommendation.candidate_exercise_id` | `exercise` | RESTRICT | |
| `recommendation_decision.recommendation_id` | `recommendation` | CASCADE | 1:1 dependent |

---

## 6. Data quality expectations

Data quality is grouped by dimension. Single-table rules are listed in §4. The rules below either span tables or need a check query. "Severity" says what happens on a violation: **error** = the write is rejected or the test fails; **warning** = reported, data accepted.

| ID | Dimension | Expectation | Enforced | Severity |
|---|---|---|---|---|
| DQ01 | Consistency | `recommendation.plan_item_id` belongs to the plan of `recommendation.session_id` | T | error |
| DQ02 | Validity | A candidate differs from the exercise it replaces | T | error |
| DQ03 | Timeliness | Check-ins (and their discomfort rows) are accepted only while the session is `open` | T | error |
| DQ04 | Consistency | `checkin_closed_at` is set exactly when the status is not `open` (C); a new session starts `open` and the status moves only open → closed → reviewed → done (T) | C + T | error |
| DQ05 | Completeness | `participants_present` is filled from `closed` on (entered when the check-in is closed) | C | error |
| DQ06 | Timeliness | Recommendations are created only after the check-in is closed | A | error |
| DQ07 | Consistency | A decision is not earlier than its recommendation | T | error |
| DQ08 | Consistency | A session's coach is the owner of its plan | T | error |
| DQ09 | Completeness | Every active exercise has at least one main joint or main muscle | Q | error (library import fails) |
| DQ10 | Completeness | Every body area has at least one muscle or joint | Q | error (seed fails) |
| DQ11 | Completeness | Every active exercise used in plans has at least one variation (a family with another member) or one regression, so a substitute can be searched for | Q | warning |
| DQ12 | Validity | Progression edges contain no cycles | Q | error |
| DQ13 | Consistency | Plan item positions in a phase are continuous 1..n | A + Q | warning |
| DQ14 | Completeness | `rule` holds exactly BR1–BR11 | Q | error |
| DQ15 | Plausibility | Check-ins per session ≤ `participants_present` | Q | warning (flag for K2) |
| DQ16 | Validity | New plan items and candidates reference active exercises only (A); plans that use an exercise deactivated later are reported (Q) | A + Q | error (A) / warning (Q) |
| DQ17 | Validity | A progression target is not easier than its source | Q | warning |
| DQ18 | Uniqueness | No duplicate names or codes in reference and library tables | C (UNIQUE) | error |
| DQ19 | Referential integrity | No orphan rows: every FK value exists in its parent | C (FK) | error |
| DQ20 | Privacy | No column stores a participant's name, contact, IP address or device id. Personal data exists only in `app_user`. | Design review + Q (column-name scan in tests) | error |
| DQ21 | Consistency | `plan.coach_id` and `session.coach_id` refer to a user holding the `coach` role | T | error |
| DQ22 | Availability | At least one active user with the `admin` role always exists: the last admin role cannot be revoked and the last admin cannot be deactivated | T | error |
| DQ23 | Consistency | `user_role.granted_by` (if set) refers to a user holding the `admin` role | T | error |
| DQ24 | Completeness | Every role has at least one permission; the seed matrix above matches the database | Q | error (seed fails) |
| DQ25 | Consistency | A plan item of a symmetric exercise has `side = 'both'` | T | error |
| DQ26 | Validity | `exercise_compensation` has no two-exercise loop (A compensated by B and B by A) | Q | error (library import fails) |
| DQ27 | Validity | Every compensating exercise in `exercise_compensation` is active | Q | error (library import fails) |
| DQ28 | Completeness | Every active exercise has at least one primary joint | Q | warning |
| DQ29 | Consistency | A new plan starts as `draft`; plan status moves draft → completed → reviewed (or back to `draft`); a plan that is not a draft has `target_duration_min`; any change to the plan or its items moves it back to `draft` | C + T | error |
| DQ30 | Consistency | A session is created only from a `reviewed` plan (T); a plan used by a session is `reviewed` (Q) | T + Q | error |
| DQ31 | Immutability | A plan used by any session is locked: its items and fields do not change | T | error |
| DQ32 | Completeness | A session becomes `reviewed` only when every recommendation has a decision | T | error |
| DQ33 | Consistency | At most one accepted replacement per plan item and session | T | error |
| DQ34 | Completeness | Every body area shown in the check-in (`is_in_checkin`) has at least one joint | Q | error (seed fails) |
| DQ35 | Completeness | Every exercise family has at least 2 exercises (a family with one exercise is allowed in the MVP; reported only) | Q | warning |
| DQ36 | Consistency | At most one progression per pair of exercises: no duplicate edge, no progressions in both directions | C (unique index) | error |

Check queries (Q) are kept in Git next to the migrations and run (a) in the automated tests, (b) after every library import, and (c) before the pilot.

---

## 7. Calculated data: views and functions

Derived values are calculated when they are read, not stored (3NF). Each formula exists once, in the database, so the backend does not repeat it.

| Object | Kind | Returns | Used for |
|---|---|---|---|
| `item_duration_sec(reps_count, rep_duration_sec, is_symmetric, side)` | function, IMMUTABLE | Item duration in seconds: `reps_count × rep_duration_sec`, × 2 if `is_symmetric = false` and `side = 'both'` | The only implementation of the duration formula; used by both views |
| `v_plan_item` | view | Items of a **blueprint**: `plan_id`, `plan_item_id`, `seq`, `phase`, `position`, `exercise_id`, `side`, `reps_count`, `duration_sec` | Plan check BR1–BR8 on the blueprint (plan review); plan duration for BR8 = `sum(duration_sec)` |
| `v_exercise_variation` | view | Variation pairs: `exercise_id`, `variation_id`, `family_id` — different exercises that share a family, both directions, one row per shared family | The variation graph as pairs (explanations, debugging). The candidate search reads `exercise_family_member` directly (one hop). |
| `v_session_plan` | view | Items of the **concrete plan of a session**: `session_id`, `plan_id`, `plan_item_id`, `seq`, `phase`, `position`, `exercise_id` (effective, after accepted replacements), `original_exercise_id`, `is_replaced`, `replacement_recommendation_id`, `alternative_exercise_ids` (accepted alternatives, shown next to the original), `side`, `reps_count`, `duration_sec` (of the effective exercise) | Session view (US5.2); BR1–BR8 check on the concrete plan (session review) |
| `plan_is_locked(plan_id)` | function | `true` when any session uses the plan | Lock trigger (DQ31); the UI shows a locked plan as read-only and offers "duplicate" |
| `duplicate_plan(plan_id, title = NULL)` | function | Id of a new `draft` plan with the same coach, notes, target duration and items. Default title: `<title> (copy)`. Raises `P0002` if the plan does not exist. | Changing a locked plan (T9). Runs with the caller's rights; the API checks that the caller owns the plan. |

**How the concrete plan is built** (`v_session_plan`), per plan item of the session's plan, in class order:
- an accepted **replacement** (BR10) swaps the item's exercise for the candidate;
- accepted **alternatives** (BR9) are listed next to the original; the item keeps its exercise;
- **warnings** (BR11) and declined recommendations change nothing.

`seq` is the position of the item in the whole class (1..n over phase, then position). BR6 ("more than five exercises later") uses it.

**One plan check for both lists (note for the backend).** The BR1–BR8 check is written once, as a function over a **list of items** (exercise, phase, position, side, duration). The backend runs the same function on `v_plan_item` (blueprint, plan review) and on `v_session_plan` with `exercise_id` (concrete plan, session review). It never reads durations from anywhere else.

**Library changes.** Durations and the plan check are calculated from the current exercise library (`rep_duration_sec`, `is_symmetric`, `mode`). If the author changes an exercise, the calculated values of old plans and sessions change too. This is intended: the library is the single source of exercise data.

---

## 8. KPI notes

| KPI | Calculated from | Note |
|---|---|---|
| K2 | `count(checkin) / participants_present` per session | Base: `participants_present`; if it is NULL or lower than the number of check-ins, the number of check-ins (thesis 2.5) |
| K3 | `count(decision = 'accepted') / count(decisions)` | Counted over **decided** recommendations only (rows in `recommendation_decision`); warnings are included, as in the thesis (every suggestion is accepted or declined). Undecided recommendations are left out. Target ≥ 60 %; absolute numbers if fewer than 10. |
| K4 | `count(feedback) / participants_present` per session | Same base as K2. Target ≥ 15 % |

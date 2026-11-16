# Kinetune — Data Dictionary

DBMS: PostgreSQL 18 · OLTP · normalised to 3NF · all objects in schema `kinetune` · DDL: `db/01_schema.sql`, `db/02_triggers.sql`

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

- The volume is small (one coach, about 50 exercises, a few hundred sessions per year at most).
- All reporting (KPIs K1–K4) can be computed from the same tables with views, so a separate analytical layer is not justified.
- Reference data and the exercise library are loaded from version-controlled seed files (CSV/SQL) in Git. Those files act as the "source" layer outside the database.

If the library import later needs validation of raw CSV rows, a `staging` schema can be added in front of the library tables without changing the core.

**Subject areas** (logical grouping within the core):

| Area | Tables | Written by | Sensitivity |
|---|---|---|---|
| Reference | `body_area`, `muscle`, `joint`, `rule` | Seed files (author) | None |
| Exercise library | `exercise`, `exercise_muscle`, `exercise_joint`, `exercise_relation` | Seed files (author) | None |
| Access control | `app_user`, `role`, `permission`, `role_permission`, `user_role` | Seed files; admin UI | `app_user`: **personal data** (e-mail, password hash) |
| Planning | `plan`, `plan_item` | Coach UI | None |
| Sessions and participant input | `session`, `checkin`, `checkin_discomfort`, `feedback` | Coach UI; participant forms (anonymous) | Check-ins: **anonymous health-related answers** (no identifiers stored) |
| Recommendations | `recommendation`, `recommendation_decision` | Recommendation engine; coach UI | Derived from aggregated check-ins |

### Expected volumes

| Table | Expected rows (first year) |
|---|---|
| `body_area` | 8–12 |
| `muscle` | 20–30 |
| `joint` | 10–15 |
| `rule` | 11 |
| `exercise` | 30–50 |
| `exercise_muscle`, `exercise_joint` | 100–200 each |
| `exercise_relation` | 50–150 |
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
| `exercise_mode` | `dynamic`, `static`, `stato_dynamic` | How the exercise is performed. `dynamic`: continuous movement (BR2: only these in the warm-up; BR4). `static`: holding a position (BR4; BR5: static ≤ 35 % of the main part). `stato_dynamic`: a hold combined with small movements. |
| `starting_pose` | `seated`, `standing`, `lying`, `balance` | Starting position. `balance` marks exercises that need balance (BR9: risky in the first quarter of class after low energy or poor sleep; BR11: a candidate must remove this factor). |
| `side` | `left`, `right`, `both` | Which side a plan item is performed on. `both`: both sides within one item. An asymmetric exercise can also be planned as two items, `left` and `right` (BR7). |
| `relation_type` | `variation`, `progression` | `variation`: different execution, same difficulty. `progression`: the target exercise is harder; the reverse direction is a regression. |
| `session_status` | `open`, `closed`, `done` | `open`: check-in link accepts answers. `closed`: the coach closed the check-in (US3.2) and recommendations are generated. `done`: the class took place and attendance has been entered. Allowed transitions: open → closed → done. |
| `recommendation_form` | `alternative`, `replacement` | What the triggered rule called for: BR9 alternative (shown next to the original), BR10 replacement |
| `explanation_source` | `template`, `llm` | Where the explanation text came from. `template` is also the fallback when the LLM fails (NFR9). |
| `decision_type` | `accepted`, `declined` | The coach's response to a recommendation |

---

## 4. Tables

Column legend: **Null** = whether NULL is allowed · **Key**: PK, FK → table, UQ = unique.

### 4.1 Reference

#### `body_area`
An area of the body that participants can report as uncomfortable in the check-in. It consists of muscles and joints, which link discomfort to exercises.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `code` | varchar(32) | no | UQ | | Stable machine code, e.g. `lower_back`, `knees`. Lower-case letters and `_` only: CHECK `code ~ '^[a-z_]+$'`. |
| `name_en` | varchar(64) | no | | | Label on the English participant form |
| `name_ru` | varchar(64) | no | | | Label on the Russian participant form |

Data quality: every area has at least one muscle or joint (**Q**, DQ10). Both labels are non-empty after trimming (**C**: CHECK `btrim(name_en) <> ''`, same for `name_ru`).

#### `muscle`
| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `name` | varchar(64) | no | UQ | | English name, e.g. `hamstrings` |
| `body_area_id` | smallint | no | FK → `body_area` | | The area this muscle belongs to (exactly one) |

#### `joint`
| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | identity | |
| `name` | varchar(64) | no | UQ | | English name, e.g. `knee` |
| `body_area_id` | smallint | no | FK → `body_area` | | The area this joint belongs to (exactly one) |

#### `rule`
The business rules BR1–BR11 from thesis Table 2.7. Recommendations refer to the rule that produced them.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | smallint | no | PK | (set explicitly) | 1–11, equal to the BR number. CHECK `id BETWEEN 1 AND 11`. |
| `description` | text | no | | | The rule's logic as worded in the thesis |
| `explanation` | text | no | | | Template explanation shown to the coach with a recommendation. Also used as the fallback when the LLM fails. |

Data quality: exactly 11 rows, ids 1–11 (**Q**, DQ14).

### 4.2 Exercise library

#### `exercise`
| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `name` | varchar(120) | no | UQ | | English name shown in the coach UI |
| `description` | text | yes | | | Execution notes |
| `mode` | exercise_mode | no | | | Dynamic, static or stato-dynamic (BR2, BR4, BR5) |
| `starting_pose` | starting_pose | no | | | Seated, standing, lying or balance (BR9, BR11) |
| `is_symmetric` | boolean | no | | `true` | `false` = asymmetric: performed on each side separately, and both sides must be done in the same phase (BR7) |
| `required_compensation_id` | integer | yes | FK → `exercise` | | The exercise that must follow this one before the end of class (BR6), e.g. a back extension after a deep forward fold. NULL = no compensation needed. CHECK `required_compensation_id <> id`. Must be an active exercise (**Q**, DQ27). |
| `difficulty` | smallint | no | | | 1 = easy, 2 = medium, 3 = hard. CHECK `difficulty BETWEEN 1 AND 3`. |
| `default_duration_sec` | integer | no | | | Suggested duration when added to a plan. CHECK `> 0`. |
| `is_active` | boolean | no | | `true` | Soft delete. Inactive exercises stay in old plans and recommendations but cannot be added to new plans or offered as candidates. |
| `created_at` | timestamptz | no | | `now()` | |

Data quality: every active exercise has at least one primary muscle or primary joint (**Q**, DQ09). New plan items and candidates use active exercises only (**A**, DQ16). Compensation links contain no two-exercise loop, i.e. A requires B and B requires A (**Q**, DQ26).

#### `exercise_muscle`
Which muscles an exercise works (M:N).

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `exercise_id` | integer | no | PK, FK → `exercise` | | |
| `muscle_id` | smallint | no | PK, FK → `muscle` | | |
| `is_primary` | boolean | no | | `false` | `true` = main target of the exercise; `false` = secondary |

#### `exercise_joint`
Which joints an exercise loads (M:N). Same structure as `exercise_muscle`.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `exercise_id` | integer | no | PK, FK → `exercise` | | |
| `joint_id` | smallint | no | PK, FK → `joint` | | |
| `is_primary` | boolean | no | | `false` | `true` = the joint carries the main load |

#### `exercise_relation`
Edges of the exercise graph, used to find substitute candidates (`WITH RECURSIVE`, depth ≤ 2).

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `from_exercise_id` | integer | no | FK → `exercise` | | Source exercise |
| `to_exercise_id` | integer | no | FK → `exercise` | | Target exercise. CHECK `from_exercise_id <> to_exercise_id` (no self-loops). |
| `type` | relation_type | no | | | Variation or progression |
| `is_directed` | boolean | no | | `true` | `true`: the edge is followed only from → to. `false`: it is followed both ways. Undirected edges are stored once: CHECK `is_directed OR from_exercise_id < to_exercise_id`. |

Keys and indexes: UQ (`from_exercise_id`, `to_exercise_id`, `type`). Index (`from_exercise_id`, `type`) for the forward search; index (`to_exercise_id`) for the backward search over undirected edges.

Data quality:
- Progression edges form no cycle: an exercise cannot be harder than itself through a chain (**Q**, DQ12).
- For a progression edge, the target's difficulty is greater than or equal to the source's (**Q**, DQ17).
- A variation is expected to be undirected; a directed variation is reported for review (**Q**, warning only).

### 4.3 Access control

Role-based access control (RBAC): a user has one or more roles, a role has a set of permissions, and the API checks the permission behind each endpoint (**A**). The database stores the model and its integrity rules; it does not decide access per request.

These are **application roles** (who may do what in the platform). They are separate from **PostgreSQL roles** (`app_read`, `app_write`, `migrator`, …), which control what the backend's database connections may do and are described in the security documentation.

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
A reusable class plan (template).

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `coach_id` | integer | no | FK → `app_user` | | Owner. The user must hold the `coach` role (**T**, DQ21). |
| `title` | varchar(120) | no | | | CHECK `btrim(title) <> ''` |
| `notes` | text | yes | | | |
| `created_at` | timestamptz | no | | `now()` | |
| `updated_at` | timestamptz | no | | `now()` | Updated by a trigger on every change to the plan or its items (**T**) |

#### `plan_item`
One exercise in a plan, at a given position within a phase.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `plan_id` | integer | no | FK → `plan` | | |
| `exercise_id` | integer | no | FK → `exercise` | | |
| `phase` | phase | no | | | |
| `position` | smallint | no | | | Order within the phase, starting at 1. CHECK `position >= 1`. |
| `duration_sec` | integer | no | | | CHECK `> 0`. Summed for the plan's total duration (BR8). |
| `side` | side | no | | `both` | Left, right or both. For a symmetric exercise it must be `both` (**T**, DQ25). |
| `reps_count` | smallint | yes | | | Number of repetitions (per side if `side` is `left` or `right`). NULL for exercises measured only by hold time. CHECK `reps_count > 0`. |

Keys: UQ (`plan_id`, `phase`, `position`), `DEFERRABLE INITIALLY DEFERRED` so items can be reordered within one transaction.
Data quality: positions within a phase are continuous 1..n with no gaps (**A**, checked by **Q**, DQ13). Each plan has at least one item in the `main` phase before it can be used in a session (**A**).

### 4.5 Sessions and participant input

#### `session`
One class held with a given plan. It owns the check-in link.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `coach_id` | integer | no | FK → `app_user` | | Must be the plan's owner (**T**, DQ08) and hold the `coach` role (**T**, DQ21) |
| `plan_id` | integer | no | FK → `plan` | | |
| `group_name` | varchar(80) | no | | | Free label, e.g. "Tuesday evening". CHECK `btrim(group_name) <> ''`. |
| `starts_at` | timestamptz | no | | | Planned start of the class |
| `status` | session_status | no | | `open` | A new session starts as `open`; only forward transitions open → closed → done (**T**) |
| `checkin_token` | varchar(43) | no | UQ | | Random 32-byte value, base64url-encoded, used in the check-in link and QR code. Not guessable and not derived from the id. CHECK `checkin_token ~ '^[A-Za-z0-9_-]{43}$'`. |
| `checkin_closed_at` | timestamptz | yes | | | Set when the coach closes the check-in. CHECK `(status = 'open') = (checkin_closed_at IS NULL)` (DQ04). |
| `participants_present` | smallint | yes | | | Entered by the coach after class; the base for K2 and K4. CHECK `>= 0`. Required once `status = 'done'`: CHECK `status <> 'done' OR participants_present IS NOT NULL` (DQ05). |
| `created_at` | timestamptz | no | | `now()` | |

Index: (`starts_at`) for the session list and per-period KPIs.

#### `checkin`
One anonymous pre-class answer. There is no link to a person, IP address or device.

| Column | Type | Null | Key | Default | Description and rules |
|---|---|---|---|---|---|
| `id` | integer | no | PK | identity | |
| `session_id` | integer | no | FK → `session` | | Accepted only while the session is `open` (**T**, DQ03) |
| `energy` | smallint | no | | | Self-rated energy, 1 = very low … 5 = very high. CHECK `BETWEEN 1 AND 5`. |
| `poor_sleep` | boolean | no | | | `true` = slept badly last night |
| `language` | char(2) | no | | | Form language. CHECK `IN ('en', 'ru')`. |
| `submitted_at` | timestamptz | no | | `now()` | |

Index: (`session_id`) for the per-session aggregates.
Data quality: the number of check-ins may be higher than `participants_present` (someone checked in but did not come). This is allowed but reported by a check query, because it pushes K2 above 100 % (**Q**, DQ15).

#### `checkin_discomfort`
The body areas a participant marked as uncomfortable (0..n per check-in).

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

A recommendation with no decision row has not been answered yet.

---

## 5. Relationships and delete behaviour

The rule: deleting a session removes everything collected for it (supports data minimisation); reference and library data cannot be deleted while in use (exercises are deactivated instead).

| Child.column | Parent | ON DELETE | Reason |
|---|---|---|---|
| `muscle.body_area_id`, `joint.body_area_id` | `body_area` | RESTRICT | Reference data in use |
| `exercise.required_compensation_id` | `exercise` | RESTRICT | Self-reference; exercises are deactivated, not deleted |
| `exercise_muscle.exercise_id`, `exercise_joint.exercise_id` | `exercise` | CASCADE | Junction rows belong to the exercise |
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
| `session.plan_id` | `plan` | RESTRICT | Keeps session history interpretable |
| `checkin.session_id`, `feedback.session_id`, `recommendation.session_id` | `session` | CASCADE | Session data is deleted together with the session |
| `checkin_discomfort.checkin_id` | `checkin` | CASCADE | |
| `checkin_discomfort.body_area_id` | `body_area` | RESTRICT | |
| `recommendation.plan_item_id` | `plan_item` | RESTRICT | Keeps history (see §7) |
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
| DQ04 | Consistency | `checkin_closed_at` is set exactly when the status is not `open` | C | error |
| DQ05 | Completeness | `participants_present` is filled once the session is `done` | C | error |
| DQ06 | Timeliness | Recommendations are created only after the check-in is closed | A | error |
| DQ07 | Consistency | A decision is not earlier than its recommendation | T | error |
| DQ08 | Consistency | A session's coach is the owner of its plan | T | error |
| DQ09 | Completeness | Every active exercise has at least one primary muscle or primary joint | Q | error (library import fails) |
| DQ10 | Completeness | Every body area has at least one muscle or joint | Q | error (seed fails) |
| DQ11 | Completeness | Every active exercise used in plans has at least one relation edge, so a substitute can be searched for | Q | warning |
| DQ12 | Validity | Progression edges contain no cycles | Q | error |
| DQ13 | Consistency | Plan item positions in a phase are continuous 1..n | A + Q | warning |
| DQ14 | Completeness | `rule` holds exactly BR1–BR11 | Q | error |
| DQ15 | Plausibility | Check-ins per session ≤ `participants_present` | Q | warning (flag for K2) |
| DQ16 | Validity | New plan items and candidates reference active exercises only | A | error |
| DQ17 | Validity | A progression target is not easier than its source | Q | warning |
| DQ18 | Uniqueness | No duplicate names or codes in reference and library tables | C (UNIQUE) | error |
| DQ19 | Referential integrity | No orphan rows: every FK value exists in its parent | C (FK) | error |
| DQ20 | Privacy | No column stores a participant's name, contact, IP address or device id. Personal data exists only in `app_user`. | Design review + Q (column-name scan in tests) | error |
| DQ21 | Consistency | `plan.coach_id` and `session.coach_id` refer to a user holding the `coach` role | T | error |
| DQ22 | Availability | At least one active user with the `admin` role always exists: the last admin role cannot be revoked and the last admin cannot be deactivated | T | error |
| DQ23 | Consistency | `user_role.granted_by` (if set) refers to a user holding the `admin` role | T | error |
| DQ24 | Completeness | Every role has at least one permission; the seed matrix above matches the database | Q | error (seed fails) |
| DQ25 | Consistency | A plan item of a symmetric exercise has `side = 'both'` | T | error |
| DQ26 | Validity | Compensation links have no two-exercise loop (A requires B and B requires A) | Q | error (library import fails) |
| DQ27 | Validity | A required compensation exercise is active | Q | error (library import fails) |

Check queries (Q) are kept in Git next to the migrations and run (a) in the automated tests, (b) after every library import, and (c) before the pilot.

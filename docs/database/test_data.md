# Kinetune — Reference and Test Data

This page lists the data that every database gets from the migrations (reference data, §1) and the test/demo dataset loaded on top of it (§2).

| Data | Loaded by | When |
|---|---|---|
| Reference data (§1) | Migration 0002 (`db/03_reference_data.sql`) | Every database, by `alembic upgrade head` |
| Exercise library | Library import (`db/library/`) | After the migrations, from the author's spreadsheet |
| Test data (§2) | `db/seed/test_data.sql` (Compose service `seed-test`, profile `test`) | Only on test/demo databases, after the library import |

---

## 1. Reference data (migration 0002)

Ids are set explicitly, so tests and seed files can refer to them; the identity sequences are moved past the last id. Names of joints and muscles are lower-case English: the library import matches them by name.

### 1.1 Body areas, joints and muscles

Source: the "Body parts" sheet of the library spreadsheet. Every joint and every muscle belongs to exactly one body area. `is_in_checkin` = the body area is shown in the check-in form; only these body areas can trigger BR9/BR10.

| id | code | name_en | name_ru | In check-in | Joints | Muscles |
|---|---|---|---|:-:|---|---|
| 1 | `head_neck` | Head and neck | Голова и шея | yes | cervical spine | upper traps, side of neck, front of neck |
| 2 | `shoulder_girdle` | Shoulder girdle | Плечевой пояс | yes | shoulder | delts, chest, rotator cuff |
| 3 | `arm` | Arm | Рука | no | elbow | biceps, triceps, forearm flexors, forearm extensors |
| 4 | `wrists_hands` | Wrists and hands | Запястья и кисти | yes | wrist, fingers | finger flexors |
| 5 | `upper_back` | Upper back | Верхняя часть спины | no | thoracic spine | lats, mid back |
| 6 | `lower_back` | Lower back | Поясница | yes | lumbar spine | back extensors, side of lower back |
| 7 | `abdomen` | Abdomen | Живот | no | — | abs, obliques |
| 8 | `pelvis_hips` | Pelvis and hips | Таз и бёдра | yes | hip | glutes, outer hip, deep hip rotators, hip flexors, quads, hamstrings, inner thigh |
| 9 | `knee` | Knee | Колено | yes | knee | — |
| 10 | `ankle_foot` | Ankle and foot | Голеностоп и стопа | yes | ankle, foot | calves, shin, peroneals, sole of foot |

Totals: 10 body areas (7 in the check-in), 11 joints (ids 1–11 in the order of the table), 28 muscles (ids 1–28 in the order of the table).

Checks that hold on this data: every body area has a muscle or a joint (DQ10); every body area in the check-in has a joint (DQ34). Abdomen has muscles only, so it cannot be in the check-in; knee has a joint only.

### 1.2 Roles and permissions

Two application roles: `coach` (id 1) and `admin` (id 2), with 12 permissions. The matrix is in the data dictionary, §4.3 ("Seed: roles and permissions"). The admin has no access to check-ins, feedback or recommendations (data minimisation).

### 1.3 Business rules BR1–BR11

Wording from the business rules v2 (`docs/business-rules.md`, author's file). `explanation` is the template shown to the coach; the placeholders are described in the data dictionary, §4.1.

| id | Rule (short) | Explanation template |
|---|---|---|
| 1 | Three phases in this order: warm-up, main part, cool-down | The plan needs a warm-up, a main part and a cool-down, in this order: {problem}. |
| 2 | Warm-up: only dynamic exercises (no stato-dynamic) | "{exercise}" is {mode} and is placed in the warm-up; the warm-up contains only dynamic exercises. |
| 3 | No difficulty-3 exercise in the warm-up or cool-down | "{exercise}" is a high-difficulty exercise placed in the {phase}. |
| 4 | Every static exercise has an earlier dynamic exercise (mode `dynamic`; stato-dynamic does not count) for the same joint, muscle or body part (earlier phase or earlier in the same phase) | No dynamic exercise for the same joint, muscle or body part comes before the static exercise "{exercise}". |
| 5 | Static ≤ 40 % of the main part; stato-dynamic is not static | Static exercises make up {share}% of the main part (limit 40%). |
| 6 | An exercise that needs compensation is followed by **any one** of its compensating exercises; more than five exercises later → suggest moving it closer | "{exercise}" needs a compensating exercise later in the class: {problem}. Options: {options}. |
| 7 | An asymmetric exercise on both sides in the same phase | "{exercise}" is planned only for the {side} side in the {phase}. |
| 8 | Calculated duration within ±5 min of the target | The plan lasts {plan_minutes} min; the target is {target_minutes} min (allowed difference: 5 min). |
| 9 | Alternative (from 1 participant up to < 50 % of the base, per factor): low energy / poor sleep → balance and difficulty-3 exercises; discomfort in a body part → exercises with a high load on a joint of it | {affected} of {base} participants ({share}%) reported {factor}. "{candidate}" is offered next to "{exercise}" for those who need it: {reason}. |
| 10 | Replacement for the whole group (≥ 50 % of the base and ≥ 2 participants), same conditions as BR9 | {affected} of {base} participants ({share}%) reported {factor}. Replacing "{exercise}" with "{candidate}" for the whole group is suggested: {reason}. |
| 11 | Candidate: same main muscle, shared family or manual progressions, same place, keeps BR1–BR8; never a progression (harder version) of the original; cascade, on each step first a same-level variation, then a regression; otherwise a warning with general advice | No suitable substitute for "{exercise}" was found in the library ({factor}). Consider fewer repetitions, a smaller amplitude or a slower pace. |

Exercise families are not reference data: they are created by the library import.

---

## 2. Test data (`db/seed/test_data.sql`)

Development, demo and test data only; never production. It is built **on top of the imported library**: exercises are referenced by name (`pg_temp.ex('…')`), never by id, so the file works with any import of the current workbook. If a name is missing, the seed stops with a clear message.

**Run order:** migrations (0001–0004) → library import → seed:

```bash
docker compose up -d
docker compose --profile import run --rm import-library
docker compose --profile test run --rm seed-test
```

Guards: the seed refuses to run if the database already has users, or if the library is empty. Ids of plans, plan items (plan id × 100 + n), sessions and recommendations are explicit, so this page can refer to them; the sequences are moved past them at the end. All timestamps are relative to the load time: done sessions are in the past, the open one in the future.

### 2.1 Accounts

All test accounts share the password `Test-Only-2026!` (argon2id hashes).

| id | E-mail | Role | Active |
|---|---|---|---|
| 1 | `admin@kinetune.test` | admin | yes |
| 2 | `laura@kinetune.test` | coach (the demo coach) | yes |
| 3 | `former.coach@kinetune.test` | coach | **no** — deactivated after its plan and session were created (history stays) |

### 2.2 Plans (blueprints)

| id | Title | Status | Target (min) | Calculated (min) | Locked | What it shows |
|---|---|---|---|---|---|---|
| 1 | Hips and hamstrings | reviewed | 40 | 39.8 | yes (S1, S2) | Main demo plan. Compensation **present** (Child's Pose after the quadriceps stretches, Kneeling Hip Shifts after Pigeon and Frog). Asymmetric exercise on **both sides in one item** (Ankle Circles – Standing, item 103) and as **two items** left/right (Half Split Hamstring Stretch – Static, 107/108). Uses Frog Stretch – Dynamic, which is deactivated later (**inactive exercise**). |
| 2 | Back care | reviewed | 22 | 21.9 | yes — **by the closed session 3** (also S6) | Compensation **missing**: Supine Spinal Twist – Static (item 214) is followed by none of its compensating exercises (Knees to Chest, Happy Baby Pose): BR6 warning. |
| 3 | Full body flow | reviewed | 20 | 20.3 | yes (S4, S5) | Its only difficulty-3 exercise (Quadriceps Stretch – Half-Kneeling – Dynamic, item 309) has **no regression** in the library. |
| 4 | Shoulders (work in progress) | draft | — | 2.1 | no | A draft without a target duration |
| 5 | Splits preparation | completed | 45 | 5.3 | no | Completed, not reviewed; the target does not match the calculated duration (BR8 case for the plan check) |
| 6 | Ankles and calves | reviewed | 8 | 8.0 | no | Reviewed but not used by any session; contains a stato-dynamic exercise |
| 7 | Hips and hamstrings (copy) | draft | 40 | 39.8 | no | **Duplicate** of plan 1 made with `duplicate_plan(1)` (items 701–718) |
| 8 | Evening relaxation | reviewed | 9 | 9.3 | yes (S7) | Plan of the deactivated coach |

### 2.3 Sessions

| id | Plan | Status | Present | Check-ins | What it shows |
|---|---|---|---|---|---|
| 1 | 1 | done (14 days ago) | 8 | 6 | Knee discomfort 4 of 8 = **exactly 50 %**, ≥ 2 people → **BR10** replacement. Pelvis/hips 1 of 8 → BR9 alternatives. Accepted and declined decisions; 3 feedback answers (K4 = 37.5 %). The concrete plan (`v_session_plan`) shows item 111 replaced. |
| 2 | 1 | reviewed (class in 30 min) | 2 | 2 | Knee 1 of 2 = **50 % with one person** → BR9 alternative, **not** BR10 (BR10 needs ≥ 2 people) |
| 3 | 2 | closed (class in 45 min) | 5 | 7 | **More check-ins than present** → the base is the number of check-ins (7); lower back 3 of 7 = 43 % → BR9. One recommendation is **undecided**, so the session cannot become `reviewed` yet (DQ32). |
| 4 | 3 | open | — | 2 | The check-in link is active; no recommendations yet |
| 5 | 3 | done (7 days ago) | 6 | 6 | Poor sleep 2 of 6 = 33 % on the difficulty-3 exercise without a regression → **no substitute**: BR11 warning (accepted = the coach applies the general advice). Ankle discomfort is reported, but plan 3 has no high ankle load, so it triggers nothing. |
| 6 | 2 | done (3 days ago) | 4 | **0** | **No check-ins**: no recommendations; reviewed at once |
| 7 | 8 | done (30 days ago) | 5 | 3 | Session of the deactivated coach; nothing reported |

Check-ins use the energy scale low / normal / high, and discomfort only in body areas shown in the check-in (`is_in_checkin`): knee, lower back, pelvis and hips, wrists and hands, ankle and foot.

### 2.4 Recommendations

Every candidate comes from the graphs: it shares a family and a main (target) muscle with the original exercise and is **not a progression** (harder version) of it. "Step" refers to the BR11 cascade (business rules v2).

| id | Session | Item → candidate | Rule / form | Factor, share | Cascade step | Decision |
|---|---|---|---|---|---|---|
| 1 | 1 | Quadriceps Stretch – Half-Kneeling – Static → Quadriceps Stretch – Standing – Static | BR10 replacement | knee 4/8 = 50 % | 2: lower knee load, same-level variation | accepted (LLM explanation) |
| 2 | 1 | Quadriceps Stretch – Half-Kneeling – Dynamic → Quadriceps Stretch – Standing – Dynamic | BR10 replacement | knee 4/8 = 50 % | 2: lower knee load, same-level variation | declined |
| 3 | 1 | Pigeon Stretch – Static → Supine Figure-Four Stretch – Static | BR9 alternative | pelvis/hips 1/8 | 2: lower hip load; no same-level variation, so a regression | accepted |
| 4 | 1 | Pigeon Stretch – Dynamic → Supine Figure-Four Stretch – Dynamic | BR9 alternative | pelvis/hips 1/8 | 2: regression | declined |
| 5 | 2 | Quadriceps Stretch – Half-Kneeling – Static → Quadriceps Stretch – Standing – Static | BR9 alternative | knee 1/2 = 50 %, one person | 2: same-level variation | accepted |
| 6 | 2 | Quadriceps Stretch – Half-Kneeling – Dynamic → Quadriceps Stretch – Standing – Dynamic | BR9 alternative | knee 1/2, one person | 2: same-level variation | declined |
| 7 | 3 | Bow Pose – Prone – Static → Thoracic Extension – Prone on Forearms – Static | BR9 alternative | lower back 3/7 (base = check-ins) | 1: no load on the lumbar spine, same-level variation | accepted |
| 8 | 3 | Bow Pose – Prone – Dynamic → Thoracic Extension – Prone on Forearms – Dynamic | BR9 alternative | lower back 3/7 | 1: same-level variation | **undecided** |
| 9 | 5 | Quadriceps Stretch – Half-Kneeling – Dynamic → (none) | BR11 warning | poor sleep 2/6 | high-difficulty exercise: 1) regression — none → warning | accepted |

### 2.5 Edge cases covered

| Edge case | Where |
|---|---|
| Exactly 50 % (and ≥ 2 people) → replacement | S1, recommendations 1–2 |
| 50 % with one person → alternative only | S2, recommendations 5–6 |
| No substitute → warning with general advice | S5, recommendation 9 |
| More check-ins than participants present | S3 (7 check-ins, 5 present) |
| 0 check-ins | S6 |
| Undecided recommendation (session stays closed) | S3, recommendation 8 |
| Inactive exercise in old plans | Frog Stretch – Dynamic in plans 1 and 7 |
| Plan item needing compensation — present / missing | plan 1 (present), plan 2 item 214 (missing) |
| Asymmetric exercise on both sides | item 103 (`side = both` in one item), items 107/108 (left + right) |
| Plans in every status, a locked plan, a duplicate | plans 1–8 (draft 4, 7; completed 5; reviewed 1, 2, 3, 6, 8; plan 2 locked by the closed S3; plan 7 = copy of plan 1) |
| Sessions in every status | open S4, closed S3, reviewed S2, done S1, S5, S6, S7 |
| Deactivated coach with history | user 3, plan 8, S7 |

### 2.6 Data quality checks on the test data

`db/checks/data_quality_checks.sql` on the imported library + this seed returns **no error rows** and exactly these **intended warnings**:

| Check | Warning | Why it is intended |
|---|---|---|
| DQ11 | Kneeling Hip Shifts – Side-to-Side – Dynamic: used in plans, no variation and no regression | Its family "hip mobility" has one exercise (allowed in the MVP) |
| DQ11 | Wrist Circles – Seated – Dynamic: used in plans, no variation and no regression | Its family "wrist mobility" has one exercise (allowed in the MVP) |
| DQ15 | Session 3: 7 check-ins but 5 participants present | Edge case "more check-ins than present" |
| DQ16 | Plan 1 uses the inactive exercise Frog Stretch – Dynamic | Edge case "inactive exercise" |
| DQ16 | Plan 7 uses the inactive exercise Frog Stretch – Dynamic | The duplicate of plan 1 |
| DQ35 | Family "hip mobility" has 1 exercise | Author's decision (MVP) |
| DQ35 | Family "wrist mobility" has 1 exercise | Author's decision (MVP) |

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

To be rewritten on top of the imported library: users, plans and sessions in every status, check-ins, recommendations and decisions, and the edge cases of the recommendation rules.

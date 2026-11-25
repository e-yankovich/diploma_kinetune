# Reference: exercise library

Read-only endpoints over the coach's exercise library (US1.2). The library is loaded from the author's spreadsheet by the import script; the API never changes it.

Base path: `/api/v1` · Authentication: none (prototype) · All responses are JSON.

- [GET /api/v1/exercises](#get-apiv1exercises) — list exercises with filters and sorting
- [GET /api/v1/exercises/{exercise_id}](#get-apiv1exercisesexercise_id) — one exercise with joints, muscles and graphs
- [GET /api/v1/families](#get-apiv1families) — exercise families

---

## GET /api/v1/exercises

Lists exercises. Without parameters: all **active** exercises sorted by name.

### Query parameters

| Name | Type | Required | Rules | Description |
|---|---|---|---|---|
| `q` | string | no | 2–100 characters | Part of the name, case-insensitive |
| `mode` | enum | no | `dynamic`, `static`, `stato_dynamic` | Execution mode |
| `starting_pose` | enum | no | see [data models](data-models.md#startingpose) | Starting position |
| `difficulty` | integer | no | 1–3 | Exact difficulty |
| `family_id` | integer | no | > 0 | Only members of this family |
| `include_inactive` | boolean | no | default `false` | Also return deactivated exercises |
| `sort` | enum | no | `name` (default), `difficulty` | `difficulty` sorts by difficulty, then name |

Filters combine with AND. An unknown family id returns an empty list (not an error).

### Example request

```bash
curl -s "http://localhost:8000/api/v1/exercises?family_id=1&difficulty=1&sort=name"
```

### Example response — 200 OK

```json
[
  {
    "id": 2,
    "name": "Ankle Circles – Seated",
    "mode": "dynamic",
    "starting_pose": "seated",
    "difficulty": 1,
    "is_symmetric": true,
    "rep_duration_sec": 2,
    "is_active": true,
    "families": ["ankle mobility"]
  },
  {
    "id": 1,
    "name": "Ankle Circles – Standing",
    "mode": "dynamic",
    "starting_pose": "balance",
    "difficulty": 1,
    "is_symmetric": false,
    "rep_duration_sec": 2,
    "is_active": true,
    "families": ["ankle mobility"]
  }
]
```

Items: [ExerciseSummary](data-models.md#exercisesummary).

### Edge cases

| Request | Result |
|---|---|
| `?q=zzzz` (no match) | `200` with `[]` |
| `?q=a` (too short) | `422 validation_error`, `location: query.q` |
| `?difficulty=7` | `422 validation_error`, `location: query.difficulty` |
| `?mode=yoga` | `422 validation_error`, `location: query.mode` |

### Status codes

| Code | When |
|---|---|
| 200 | List returned (may be empty) |
| 422 | A query parameter is invalid ([errors](errors.md)) |
| 503 | The database is not available |

---

## GET /api/v1/exercises/{exercise_id}

One exercise with everything the coach needs to judge it: joints with load level, muscles, compensating exercises and the two graphs.

### Path parameters

| Name | Type | Rules |
|---|---|---|
| `exercise_id` | integer | > 0 |

### Example request

```bash
curl -s http://localhost:8000/api/v1/exercises/1
```

### Example response — 200 OK (lists shortened)

```json
{
  "id": 1,
  "name": "Ankle Circles – Standing",
  "mode": "dynamic",
  "starting_pose": "balance",
  "difficulty": 1,
  "is_symmetric": false,
  "rep_duration_sec": 2,
  "is_active": true,
  "families": ["ankle mobility"],
  "description": "Rotation of foot in circular motions from the ankle joint standing on one leg.",
  "joints": [
    {"joint": "ankle", "is_primary": true, "load_level": "medium"}
  ],
  "muscles": [
    {"muscle": "calves", "is_primary": true},
    {"muscle": "peroneals", "is_primary": true}
  ],
  "compensations": [],
  "variations": [
    {"id": 2, "name": "Ankle Circles – Seated", "difficulty": 1, "level": "easier"},
    {"id": 4, "name": "Ankle Flexion and Extension – Standing", "difficulty": 1, "level": "same_level"},
    {"id": 9, "name": "Calf Stretch – Quadruped – Dynamic", "difficulty": 2, "level": "same_level"}
  ],
  "regressions": [
    {"id": 2, "name": "Ankle Circles – Seated", "difficulty": 1},
    {"id": 3, "name": "Ankle Flexion and Extension – Seated", "difficulty": 1}
  ],
  "progressions": []
}
```

Object: [ExerciseDetail](data-models.md#exercisedetail).

How the lists are built:

| Field | Source | Order |
|---|---|---|
| `joints`, `muscles` | Library links; `is_primary` = main joint / main (stretched) muscle | Main first, then by name |
| `compensations` | BR6: any one of them should follow the exercise in a plan | By name |
| `variations` | Members of the exercise's families (one hop through the family) | By name |
| `variations[].level` | `easier` if also a regression, `harder` if also a progression, otherwise `same_level` | — |
| `regressions` / `progressions` | Progression edges, one step backwards / forwards | By name |

### Example response — 404 Not Found

```bash
curl -s http://localhost:8000/api/v1/exercises/9999
```

```json
{
  "error": {
    "code": "not_found",
    "message": "Exercise 9999 does not exist",
    "request_id": "38741f2e947b462ab0fb71445179200a"
  }
}
```

### Status codes

| Code | When |
|---|---|
| 200 | Exercise returned (inactive exercises too) |
| 404 | No exercise with this id |
| 422 | `exercise_id` is not a positive integer (e.g. `/exercises/0`, `/exercises/abc`) |
| 503 | The database is not available |

---

## GET /api/v1/families

Lists exercise families with the number of member exercises. Use the `id` as the `family_id` filter.

### Example request

```bash
curl -s http://localhost:8000/api/v1/families
```

### Example response — 200 OK (shortened)

```json
[
  {"id": 1, "name": "ankle mobility", "exercise_count": 13},
  {"id": 3, "name": "calf flexibility", "exercise_count": 17},
  {"id": 6, "name": "forward fold", "exercise_count": 14}
]
```

Items: [FamilyOut](data-models.md#familyout). A family with one exercise is allowed (its member has no variations through it).

### Status codes

| Code | When |
|---|---|
| 200 | List returned, sorted by name |
| 503 | The database is not available |

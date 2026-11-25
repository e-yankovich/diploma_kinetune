# Reference: data models

The JSON schemas are defined in the specification ([openapi.json](../schemas/openapi.json), `components.schemas`). This page explains them.

## ExerciseSummary

| Field | Type | Description |
|---|---|---|
| `id` | integer | Exercise id |
| `name` | string | Unique name (up to 120 characters) |
| `mode` | [ExerciseMode](#exercisemode) | Execution mode |
| `starting_pose` | [StartingPose](#startingpose) | Starting position |
| `difficulty` | integer 1–3 | 1 easy, 2 medium, 3 hard |
| `is_symmetric` | boolean | `false` = performed on one side and then the other |
| `rep_duration_sec` | integer | Seconds for one repetition (static: one hold) |
| `is_active` | boolean | Deactivated exercises stay in old plans but are not offered |
| `families` | string[] | Family names, sorted |

## ExerciseDetail

All fields of ExerciseSummary, plus:

| Field | Type | Description |
|---|---|---|
| `description` | string \| null | Execution notes |
| `joints` | [JointLoad](#jointload)[] | Joints involved, main first |
| `muscles` | [MuscleRef](#muscleref)[] | Muscles, main (stretched) first |
| `compensations` | [ExerciseRef](#exerciseref)[] | Acceptable compensating exercises (BR6) |
| `variations` | [Variation](#variation)[] | Exercises sharing a family |
| `regressions` | [ExerciseRef](#exerciseref)[] | One step easier |
| `progressions` | [ExerciseRef](#exerciseref)[] | One step harder |

## ExerciseRef

`{ "id": integer, "name": string, "difficulty": integer }`

## Variation

ExerciseRef plus `level`: [VariationLevel](#variationlevel).

## JointLoad

| Field | Type | Description |
|---|---|---|
| `joint` | string | Joint name, e.g. `knee` |
| `is_primary` | boolean | Main joint of the exercise |
| `load_level` | [LoadLevel](#loadlevel) | Load on this joint |

## MuscleRef

`{ "muscle": string, "is_primary": boolean }` — main muscle = the muscle that is stretched.

## FamilyOut

`{ "id": integer, "name": string, "exercise_count": integer }`

## ErrorResponse

See [errors](errors.md).

## Enumerations

### ExerciseMode
`dynamic`, `static`, `stato_dynamic`

### StartingPose
`seated`, `standing`, `balance`, `quadruped`, `downward_dog`, `supine`, `prone`, `kneeling`, `front_split`

### LoadLevel
`low`, `medium`, `high`

### VariationLevel
`same_level`, `easier`, `harder`

### ExerciseSort
`name`, `difficulty`

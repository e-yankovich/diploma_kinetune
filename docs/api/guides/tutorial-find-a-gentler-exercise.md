# Tutorial: find a gentler version of an exercise

**Goal:** a participant reports knee discomfort; the coach looks for a gentler exercise for the same stretch. This tutorial shows how a client (for example the coach's frontend) walks the exercise graphs with the API.

Background (business rules v2): a **variation** is another execution of the same movement — the two exercises share a family. A **regression** is an easier version (a progression followed backwards). One pair can be both: then it is "a gentler version of the same stretch".

Prerequisite: the stack runs and the library is imported ([getting started](getting-started.md)).

## Step 1 — list the families

```bash
curl -s http://localhost:8000/api/v1/families
```

```json
[
  {"id": 1, "name": "ankle mobility", "exercise_count": 13},
  {"id": 3, "name": "calf flexibility", "exercise_count": 17}
]
```

Pick a family id for the filter in the next step (here `1`, "ankle mobility").

## Step 2 — list the exercises of the family

```bash
curl -s "http://localhost:8000/api/v1/exercises?family_id=1&sort=difficulty"
```

The list is sorted by difficulty, then by name. Each item has the `id` you need for step 3.

## Step 3 — open the exercise from the plan

Suppose the plan contains "Ankle Circles – Standing" (`id` 1):

```bash
curl -s http://localhost:8000/api/v1/exercises/1
```

Shortened response:

```json
{
  "id": 1,
  "name": "Ankle Circles – Standing",
  "starting_pose": "balance",
  "joints": [{"joint": "ankle", "is_primary": true, "load_level": "medium"}],
  "variations": [
    {"id": 2, "name": "Ankle Circles – Seated", "difficulty": 1, "level": "easier"},
    {"id": 4, "name": "Ankle Flexion and Extension – Standing", "difficulty": 1, "level": "same_level"}
  ],
  "regressions": [{"id": 2, "name": "Ankle Circles – Seated", "difficulty": 1}],
  "progressions": []
}
```

## Step 4 — choose a candidate

Use the `level` of each variation:

| `level` | Meaning | Use it as |
|---|---|---|
| `same_level` | Same family, neither easier nor harder | "Same level, another execution" |
| `easier` | Same family **and** a regression | "A gentler version of the same stretch" |
| `harder` | Same family **and** a progression | Never offered to a participant with discomfort |

Here "Ankle Circles – Seated" (`easier`) removes the balance and lowers the ankle load.

## Step 5 — check the candidate

```bash
curl -s http://localhost:8000/api/v1/exercises/2
```

Compare the joints and their `load_level` with the original. A candidate for a participant with discomfort should not load the reported joint more.

## Error cases to handle

| Situation | Status | `error.code` | What to do |
|---|---|---|---|
| The id does not exist (e.g. a stale link) | 404 | `not_found` | Reload the list |
| Wrong filter value (e.g. `difficulty=7`) | 422 | `validation_error` | Show `error.details[].message` next to the field |
| Database restarting | 503 | `service_unavailable` | Retry after a few seconds |

In the full product this search runs on the server (the recommendation engine, BR9–BR11), and the coach only accepts or declines the result.

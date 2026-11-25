# API changelog

All notable changes to the Kinetune API. Versions follow semantic versioning.

## 0.1.0 — 2026-11-25

Added (prototype slice):
- `GET /api/v1/exercises` with filters (`q`, `mode`, `starting_pose`, `difficulty`, `family_id`, `include_inactive`) and sorting.
- `GET /api/v1/exercises/{exercise_id}` with joints, muscles, compensations, variations (with level), regressions and progressions.
- `GET /api/v1/families`.
- `GET /health`.
- One error format for all errors; `X-Request-ID` header on every response.

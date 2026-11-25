# Architecture overview

## System context

```mermaid
flowchart LR
    coach([Coach<br/>browser]) -->|HTTPS| fe[Frontend SPA<br/>React, served by nginx]
    participant([Participant<br/>phone, anonymous]) -.->|planned: check-in| fe
    fe -->|/api/v1 JSON| api[Backend API<br/>FastAPI]
    api -->|SQL as kinetune_api| db[(PostgreSQL 18<br/>schema kinetune)]
    xlsx[[Library spreadsheet]] -->|import script<br/>as kinetune_admin| db
    api -.->|planned: explanations| llm[(External LLM)]
```

The library is written only by the import script; the API reads it. Dashed arrows are planned parts.

## Request flow

```mermaid
sequenceDiagram
    participant C as Client
    participant M as RequestLogMiddleware
    participant R as Router (api/v1/exercises.py)
    participant S as ExerciseService
    participant P as SqlAlchemyExerciseRepository
    participant D as PostgreSQL
    C->>M: GET /api/v1/exercises/1
    M->>R: request (request id assigned)
    R->>R: validate path/query (Pydantic)
    R->>S: get_exercise(1)
    S->>P: get_exercise, list_variations, list_regressions, list_progressions
    P->>D: SELECT ... (bound parameters)
    D-->>P: rows
    P-->>S: ORM objects
    S->>S: classify variations (same_level / easier / harder)
    S-->>R: ExerciseDetail
    R-->>M: 200 JSON
    M-->>C: response + X-Request-ID, one JSON log line
    Note over S,M: NotFoundError -> 404, validation -> 422,<br/>database down -> 503, other -> 500 (global handlers)
```

## Modules (backend)

| Module | Responsibility |
|---|---|
| `app/api/` | HTTP layer: routers, parameter validation, dependency wiring (`deps.py`) |
| `app/services/` | Business logic (e.g. variation levels from the two graphs) |
| `app/repositories/` | Data access; the service depends on a protocol, so tests use an in-memory fake |
| `app/models/` | SQLAlchemy ORM models over the existing schema (created by Alembic migrations in `db/`) |
| `app/schemas/` | Pydantic request/response models and enumerations; the OpenAPI schemas come from here |
| `app/core/` | Settings from environment variables, JSON logging, error classes and global handlers |

## Resources

| Resource | Endpoints | Notes |
|---|---|---|
| Exercise | `/api/v1/exercises`, `/api/v1/exercises/{id}` | Read-only |
| Family | `/api/v1/families` | Read-only; families are the hubs of the variation graph |
| Health | `/health` | Outside the versioned API |

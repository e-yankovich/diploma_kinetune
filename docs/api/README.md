# Kinetune API documentation

Kinetune is a hybrid recommendation system that helps a coach of group stretching classes adapt a training plan to the group's condition. This folder documents its HTTP API.

> **Status: prototype slice (v0.1.0).** Only the **exercise library** is available, read-only and without authentication. Coach and participant endpoints (plans, sessions, check-in, recommendations) will be added later; see the [changelog](CHANGELOG.md).

## Contents

| Section | What you find there |
|---|---|
| [Getting started](guides/getting-started.md) | Start the stack, call the API for the first time |
| [Tutorial: find a gentler exercise](guides/tutorial-find-a-gentler-exercise.md) | Step-by-step integration: families → filtered list → exercise → easier variation |
| [Reference: exercise library](reference/exercises.md) | Every endpoint with parameters, examples and status codes |
| [Reference: health](reference/health.md) | Service and database status |
| [Reference: data models](reference/data-models.md) | JSON objects and enumerations |
| [Reference: errors](reference/errors.md) | Error structure, codes, recovery steps |
| [Architecture overview](architecture.md) | System context, request flow, modules |
| [Documentation strategy](strategy.md) | Tools, standards, naming, versioning, known gaps |
| [Changelog](CHANGELOG.md) | API versions and changes |
| [Specification](schemas/openapi.json) | OpenAPI 3.1, generated from the code, linted with Redocly CLI |
| [Examples](examples/requests.http) | Runnable requests (VS Code REST Client / JetBrains HTTP client) |

## Interactive documentation

When the backend runs, FastAPI serves the same specification as:

- Swagger UI: <http://localhost:8000/docs>
- ReDoc: <http://localhost:8000/redoc>
- raw JSON: <http://localhost:8000/openapi.json>

## Basics

| | |
|---|---|
| Base URL | `http://localhost:8000/api/v1` (directly) or `http://localhost:8080/api/v1` (through the frontend) |
| Format | JSON (UTF-8) for every request and response, errors included |
| Authentication | None in the prototype slice — see [security note](guides/getting-started.md#security-note) |
| Versioning | Major version in the path (`/api/v1`); see [strategy](strategy.md#versioning) |
| Request id | Every response has an `X-Request-ID` header; send your own to correlate requests |

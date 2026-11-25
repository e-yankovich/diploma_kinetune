# Testing strategy

Automated tests of the prototype slice (exercise library): backend, frontend and database. All tests are fast, independent and repeatable (FIRST): no test depends on another, the unit and API tests need no database or network, and the data comes from fixtures taken from the real library.

## Test types

| Layer | Type | What is checked | Tool | Location |
|---|---|---|---|---|
| Backend | Unit | Service logic (variation levels from the two graphs, not-found, sorting of joints/muscles, filters passed on), settings from the environment, JSON log format, error classes | pytest | `backend/tests/unit/` |
| Backend | Integration (API) | HTTP layer with the service and the global error handlers: status codes (200, 404, 405, 422, 500, 503), error body, query validation, request id, OpenAPI error model. The repository is replaced by an in-memory fake through FastAPI dependency overrides. | pytest + FastAPI TestClient | `backend/tests/integration/test_api.py` |
| Backend | Integration (database) | SQLAlchemy repository on PostgreSQL with the imported library: filters, sorting, family counts, variations and regressions of a real exercise | pytest | `backend/tests/integration/test_repository_db.py` (runs only with `TEST_DATABASE=1`) |
| Frontend | Unit | API client (query building, error mapping, network errors, status messages), global state reducer, form validation rules | Vitest | `frontend/src/**/*.test.ts` |
| Frontend | Component | Filter form (validation, controlled fields, apply/reset), sortable table, error boundary | Vitest + Testing Library | `frontend/src/components/*.test.tsx` |
| Frontend | Integration | Pages with hooks, API client and global state, `fetch` stubbed: loading skeleton → data, sorting request, empty state, 503 → error state + toast, 404 → "not found", routing and navigation | Vitest + Testing Library | `frontend/src/pages/*.test.tsx`, `frontend/src/App.test.tsx` |
| Database | Smoke + privileges + data quality | Constraints and triggers, role privileges, data-quality rules | SQL scripts | `db/tests/`, `db/checks/` (see README) |

Naming: backend `test_*.py` in `tests/unit` and `tests/integration`, test functions named after the behaviour (`test_unknown_id_gives_404_error_body`); frontend `*.test.ts(x)` next to the tested file, `describe` = unit under test, `it` = behaviour.

## Coverage (25 Nov 2026)

| Suite | Tests | Coverage (lines) |
|---|---|---|
| Backend without database | 38 passed, 3 skipped | **91 %** |
| Backend with database (`TEST_DATABASE=1`) | 41 passed | **98 %** |
| Frontend | 33 passed | **97.5 %** statements, 91 % branches |

The frontend coverage run fails below 70 % (thresholds in `frontend/vite.config.ts`). The backend report is printed by `pytest-cov` (`--cov=app --cov-report=term-missing`).

## Running the tests locally

Backend (Python 3.12):

```bash
cd backend
pip install -r requirements-dev.txt
pytest                                   # unit + API tests with coverage
```

With the database tests (stack running, library imported):

```bash
TEST_DATABASE=1 DB_HOST=localhost DB_PORT=5432 DB_NAME=kinetune \
DB_USER=kinetune_api DB_PASSWORD=... pytest
```

Frontend (Node 22):

```bash
cd frontend
npm ci
npm test                 # all tests
npm run test:coverage    # with coverage report (text + coverage/index.html)
```

## Known gaps

- **CI is not set up yet** (planned with the CI/CD pipeline): tests run locally only.
- **No browser end-to-end tests** (Playwright/Cypress) yet; the page integration tests run in jsdom with a stubbed `fetch`. One e2e test of the main flow is planned once the stack runs in CI.
- The repository tests need a database and are skipped without it; the uncovered lines are listed by `pytest-cov`.
- No performance tests yet (NFR: plan check ≤ 1 s, recommendations ≤ 3 s) — they belong to the recommendation engine, which is not built yet.

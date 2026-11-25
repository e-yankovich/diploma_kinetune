# Kinetune

Hybrid recommendation system for adapting group training plans (diploma project).
This repository contains the database layer and a prototype slice of the application: a FastAPI backend and a React frontend for the exercise library, all in one Docker Compose stack ([containers](docs/containers/README.md)).

## Quick start

Requirements: Docker with Docker Compose v2. All commands run from the repository root
(`docker-compose.yml` and `.env` live there).

**Run order:** database + migrations → library import → (optional) test data → checks.

```bash
# 1. secrets
cp .env.example .env          # then set real passwords (see "Secrets" below)

# 2. database, migrations 0001–0004, backend and frontend
docker compose up -d --build  # db -> migrate -> backend -> frontend
docker compose logs migrate   # "Running upgrade ... -> 0004, Password policy ..."

# 3. exercise library from the author's spreadsheet (db/library/kinetune_library.xlsx)
docker compose --profile import run --rm import-library /data/kinetune_library.xlsx --dry-run
docker compose --profile import run --rm import-library

# 4. optional: test/demo data on top of the imported library
docker compose --profile test run --rm seed-test
```

- The **library import** runs in one transaction and reports all problems together with
  sheet, row, column and value; it connects as `kinetune_admin`. A changed sheet is applied
  to an existing library with `--update`. Details:
  [`docs/database/library_import.md`](docs/database/library_import.md).
- The **test data** (accounts, plans and sessions in every status, check-ins,
  recommendations and decisions, the rule edge cases) references the imported exercises by
  name. It refuses to run if the database already has users or if the library is empty.
  Contents: [`docs/database/test_data.md`](docs/database/test_data.md) §2.
- Then run the checks and tests ("Running the tests" below).
- Open the app at <http://localhost:8080> and the API docs at <http://localhost:8000/docs>
  ([API documentation](docs/api/README.md), [frontend](docs/frontend/architecture.md)).

Connect with any client on `localhost:${DB_PORT}` (default 5432; reachable only from
this machine), database `kinetune`, schema `kinetune`. The superuser is for
maintenance; day-to-day access uses the login roles (see "Roles and access"):

```bash
docker compose exec db psql -U postgres -d kinetune -c '\dt kinetune.*'
```

## How a startup works

The database structure is **never created by hand**. 

On the **first** `docker compose up` (empty data volume):

1. The `db` container initialises PostgreSQL and, from `db/init/`, runs
   `10_login_roles.sh` **once** to create the non-superuser login roles
   (`kinetune_migrator`, `kinetune_api`, `kinetune_reader`, `kinetune_admin`) with passwords from `.env`,
   and transfers ownership of the database to `kinetune_migrator`.
2. `db` reports healthy (`pg_isready` over TCP).
3. `migrate` (one-shot container) connects **as `kinetune_migrator`** and runs
   `alembic upgrade head`, so every object is owned by that role.
4. `migrate` exits 0. The backend will start only after that
   (`service_completed_successfully`).

On **later** starts the login roles already exist (init scripts don't re-run) and
`migrate` applies only the new migrations (history in `public.alembic_version`).
Each migration runs in one transaction: if it fails, nothing is changed.

Migrations applied:

| Rev | Contents                                                                                                                                                                                           |
|---|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 0001 | schema: types, tables, constraints, indexes (`01`); triggers, plan lock, `duplicate_plan()`, views `v_plan_item` / `v_session_plan` / `v_exercise_variation` (`02`)                                 |
| 0002 | reference data: roles, permissions, body areas, muscles, joints, rules BR1–BR11 (`03`)                                                                                                             |
| 0003 | group roles `app_read`/`app_write`/`app_admin`, privileges, SECURITY DEFINER triggers (`04`)                                                                                                       |
| 0004 | password policy: `app_user.password_hash` must be an argon2id PHC string (`05`)                                                                                                                   |

Useful commands (run from the repository root):

| Task | Command |
|---|---|
| Show the current schema version | `docker compose run --rm migrate alembic current` |
| Show migration history | `docker compose run --rm migrate alembic history` |
| Print the SQL without running it | `docker compose run --rm migrate alembic upgrade head --sql` |
| Roll back the last migration | `docker compose run --rm migrate alembic downgrade -1` |
| Delete everything (data too) | `docker compose down -v` |

## Roles and access

The cluster **superuser** (`POSTGRES_USER`, e.g. `postgres`) is used only to bootstrap
and for maintenance — never by the application or by migrations. Four **login roles**
carry no privileges directly; they inherit from NOLOGIN **group roles**:

| Login role | Group | Used by | Access |
|---|---|---|---|
| `kinetune_migrator` | owns all objects | migrations | DDL + full DML on its objects (not a superuser) |
| `kinetune_api` | `app_write` | FastAPI backend | writes operational data; reference data & library are read-only |
| `kinetune_reader` | `app_read` | reports / analysis | read-only; cannot read `app_user.email` or `password_hash` |
| `kinetune_admin` | `app_admin` | library import, reference data | library and reference data writable; no DDL |

`app_admin ⊃ app_write ⊃ app_read`. `app_admin` additionally maintains reference data and
the exercise library (no DDL). New tables are readable by `app_read` automatically via
default privileges; **write access is never automatic** and must be granted explicitly in
the migration that creates the table (`db/tests/privileges_test.sql` enforces this).
The full privilege matrix and the checklist for new objects are in
[`docs/database/security_and_access.md`](docs/database/security_and_access.md).

## Repository layout

```text
docker-compose.yml           db, migrate, backend, frontend; import-library (profile "import"); seed-test (profile "test")
backend/                     FastAPI app, tests, Dockerfile
frontend/                    React SPA, tests, Dockerfile (nginx)
.env.example                 template for secrets (.env is git-ignored)
db/
  01_schema.sql              DDL: types, tables, constraints, indexes, comments
  02_triggers.sql            DDL: triggers (cross-table rules), plan lock, duplicate_plan, views
  03_reference_data.sql      reference data (roles, permissions, areas, rules ...)
  04_roles_privileges.sql    group roles, grants, SECURITY DEFINER triggers
  05_password_policy.sql     argon2id password-hash constraint
  alembic.ini                migration tool configuration
  migrations/
    env.py                   connection from environment variables
    versions/0001..0004      one migration per SQL file above (0001 uses 01 + 02)
  init/                      run once on an empty volume (first start only)
    10_login_roles.sh        creates login roles with passwords from .env
    login_roles.psql         the role DDL it executes (passwords, never in Git)
  seed/
    test_data.sql            test/demo dataset on top of the imported library (seed-test service)
  library/
    import_library.py        library import: validates the sheet, derives the graphs
    kinetune_library.xlsx    the author's library workbook (input of the import)
  checks/
    data_quality_checks.sql  queries that return rows violating DQ rules
  tests/
    ddl_smoke_test.sql       valid flow + every constraint/trigger rejects bad data
    privileges_test.sql      each role can do exactly what it should, nothing more
    run_ddl_test.sh          runs the smoke test on a scratch database
  Dockerfile, requirements.txt          image of the "migrate" service
docs/
  api/                       API documentation and OpenAPI specification
  frontend/                  frontend architecture
  containers/                images, variables, container diagram, resources
  testing.md                 testing strategy and coverage
  database/
    kinetune_schema.dbml     logical schema (render at dbdiagram.io)
    kinetune-er-diagram.png  ER diagram rendered from the DBML
    data_dictionary.md       tables, columns, types, keys, data quality rules
    data_integrity_and_transactions.md  how integrity and transactions are handled
    security_and_access.md   database roles, privilege matrix, checklist for new objects
    library_import.md        library sheet format, validation, graph derivation
    test_data.md             reference data and the test dataset (edge cases, expected warnings)
  requirements/              thesis and course requirements (local only, git-ignored)
  business-rules.md          training rules notes (local only, git-ignored)
```

## Running the tests

With the stack running, from the repository root (the smoke test creates and drops its own
scratch database, so it connects as the **superuser**):

```bash
# DDL: constraints and triggers  (expected: 88 lines PASS, no FAIL)
PGHOST=localhost PGPORT=${DB_PORT} PGUSER=postgres PGPASSWORD=... db/tests/run_ddl_test.sh

# Roles and privileges  (run after the migrations; own fixture rows; expected: 81 PASS, no FAIL)
psql "host=localhost port=${DB_PORT} user=postgres dbname=kinetune" \
     -v ON_ERROR_STOP=1 -f db/tests/privileges_test.sql

# Data quality: each row is a rule violation; no 'error' rows = data is valid
# (after import + test data: 0 errors, 7 intended warnings)
psql "host=localhost port=${DB_PORT} user=kinetune_reader dbname=kinetune" \
     -f db/checks/data_quality_checks.sql
```

The privileges test uses `SET ROLE` to switch into each login role and rolls everything
back; it needs a superuser connection. The data-quality checks run with any `app_read`
role: an empty result means every rule holds; `warning` rows are reported but accepted
(the test dataset intentionally produces seven, listed in `test_data.md` §2.6), while any
`error` row must be fixed.

### Backend and frontend tests

```bash
cd backend && pip install -r requirements-dev.txt && pytest      # unit + API tests, coverage
cd frontend && npm ci && npm run test:coverage                    # unit, component, integration
```

Strategy, coverage numbers and the database tests of the backend: [`docs/testing.md`](docs/testing.md).

## Changing the schema

1. Add a new migration in `db/migrations/versions/` (e.g. `0005_add_x.py`, with
   `revision = "0005"`, `down_revision = "0004"`), with both `upgrade()` and `downgrade()`.
   Locally: `pip install -r db/requirements.txt && cd db && alembic revision -m "add x"`.
2. If the migration reads a new `*.sql` file, **add that file to the `COPY` in `db/Dockerfile`**
   so the image ships it.
3. If it creates a table the backend writes to, **grant the needed write access explicitly**
   in the same migration (SELECT for `app_read` is automatic). `privileges_test.sql` checks this.
4. Rebuild the image: `docker compose build migrate`.
5. Update `docs/database/` (DBML, data dictionary) in the same commit.
6. `docker compose up migrate` applies it.

### Versioning

Every schema change is a migration in Git; the database records its version in
`public.alembic_version`. **Existing migrations are never edited after they have been
applied anywhere.** Before the first deployment, the structure was consolidated into the
baseline migrations 0001–0004 (November 2026; no database had been deployed from the
earlier migrations); from the first real deployment on, every change is a new migration,
starting with 0005.

## Secrets

- `.env` is git-ignored; only `.env.example` with placeholders is committed. It holds:
  - `POSTGRES_USER` / `POSTGRES_PASSWORD` — the cluster superuser (bootstrap/maintenance).
  - `MIGRATOR_PASSWORD`, `API_PASSWORD`, `READER_PASSWORD`, `ADMIN_PASSWORD` — the four login roles.
- No application role is a superuser or can bypass RLS; the `migrate` container runs as a
  non-root OS user and connects as the non-superuser owner `kinetune_migrator`.
- Role passwords are stored as SCRAM-SHA-256 verifiers; user passwords as argon2id (enforced
  by a CHECK constraint).
- The database port is bound to `127.0.0.1`, not to all interfaces.
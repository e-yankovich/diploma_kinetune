# Kinetune

Hybrid recommendation system for adapting group training plans (diploma project).
This repository currently contains the **database layer**; the backend (FastAPI) and frontend (React) will be added to the same Docker Compose stack.

## Quick start

Requirements: Docker with Docker Compose v2.

```bash
cd deployment                 # the Docker Compose stack lives here
cp .env.example .env          # then set real passwords (see "Secrets" below)
docker compose up -d          # 1) starts PostgreSQL 18  2) applies migrations
docker compose logs migrate   # "Running upgrade ... -> 0004, Password policy ..."
```

Optionally load the demo/test dataset (coaches, a demo exercise library, sessions,
check-ins and recommendations). It refuses to run if the database already has users:

```bash
docker compose --profile test run --rm seed-test
```

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
   (`kinetune_migrator`, `kinetune_api`, `kinetune_reader`) with passwords from `.env`,
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

| Rev | Contents |
|---|---|
| 0001 | schema: types, tables, constraints, indexes (`01`), triggers (`02`) |
| 0002 | reference data: roles, permissions, body areas, muscles, joints, rules BR1–BR11 (`03`) |
| 0003 | group roles `app_read`/`app_write`/`app_admin`, privileges, SECURITY DEFINER triggers (`04`) |
| 0004 | password policy: `app_user.password_hash` must be an argon2id PHC string (`05`) |

Useful commands (run from `deployment/`):

| Task | Command |
|---|---|
| Show the current schema version | `docker compose run --rm migrate alembic current` |
| Show migration history | `docker compose run --rm migrate alembic history` |
| Print the SQL without running it | `docker compose run --rm migrate alembic upgrade head --sql` |
| Roll back the last migration | `docker compose run --rm migrate alembic downgrade -1` |
| Delete everything (data too) | `docker compose down -v` |

## Roles and access

The cluster **superuser** (`POSTGRES_USER`, e.g. `postgres`) is used only to bootstrap
and for maintenance — never by the application or by migrations. Three **login roles**
carry no privileges directly; they inherit from NOLOGIN **group roles**:

| Login role | Group | Used by | Access |
|---|---|---|---|
| `kinetune_migrator` | owns all objects | migrations | DDL + full DML on its objects (not a superuser) |
| `kinetune_api` | `app_write` | FastAPI backend | writes operational data; reference data & library are read-only |
| `kinetune_reader` | `app_read` | reports / analysis | read-only; cannot read `app_user.email` or `password_hash` |

`app_admin ⊃ app_write ⊃ app_read`. `app_admin` additionally maintains reference data and
the exercise library (no DDL). New tables are readable by `app_read` automatically via
default privileges; **write access is never automatic** and must be granted explicitly in
the migration that creates the table (`tests/privileges_test.sql` enforces this).

## Repository layout

```text
deployment/
  docker-compose.yml         db + migrate + seed-test (profile "test")
  .env.example               template for secrets (.env is git-ignored)
  db/
    01_schema.sql            DDL: types, tables, constraints, indexes, comments
    02_triggers.sql          DDL: functions and triggers (cross-table rules)
    03_reference_data.sql    reference data (roles, permissions, areas, rules ...)
    04_roles_privileges.sql  group roles, grants, SECURITY DEFINER triggers
    05_password_policy.sql   argon2id password-hash constraint
    alembic.ini              migration tool configuration
    migrations/
      env.py                 connection from environment variables
      versions/0001..0004    one migration per SQL file above
    init/                    run once on an empty volume (first start only)
      10_login_roles.sh      creates login roles with passwords from .env
      login_roles.psql       the role DDL it executes (passwords, never in Git)
    seed/
      test_data.sql          demo/test dataset (loaded via the seed-test service)
    checks/
      data_quality_checks.sql  queries that return rows violating DQ rules
    tests/
      ddl_smoke_test.sql     valid flow + every constraint/trigger rejects bad data
      privileges_test.sql    each role can do exactly what it should, nothing more
      run_ddl_test.sh        runs the smoke test on a scratch database
    Dockerfile, requirements.txt        image of the "migrate" service
documentation/database/
  kinetune_schema.dbml       logical schema (render at dbdiagram.io)
  data_dictionary.md         tables, columns, types, keys, data quality rules
  data_integrity_and_transactions.md   how integrity and transactions are handled
```

## Running the tests

With the stack running, from `deployment/` (the smoke test creates and drops its own
scratch database, so it connects as the **superuser**):

```bash
# DDL: constraints and triggers  (expected: 31 lines PASS, no FAIL)
PGHOST=localhost PGPORT=${DB_PORT} PGUSER=postgres PGPASSWORD=... db/tests/run_ddl_test.sh

# Roles and privileges  (run after migrations + test data; expected: no FAIL)
psql "host=localhost port=${DB_PORT} user=postgres dbname=kinetune" \
     -v ON_ERROR_STOP=1 -f db/tests/privileges_test.sql

# Data quality: each row is a rule violation; no 'error' rows = data is valid
psql "host=localhost port=${DB_PORT} user=kinetune_reader dbname=kinetune" \
     -f db/checks/data_quality_checks.sql
```

The privileges test uses `SET ROLE` to switch into each login role and rolls everything
back; it needs a superuser connection. The data-quality checks run with any `app_read`
role: an empty result means every rule holds; `warning` rows are reported but accepted
(the demo dataset intentionally contains a few), while any `error` row must be fixed.

## Changing the schema

1. Add a new migration in `db/migrations/versions/` (e.g. `0005_add_x.py`, with
   `revision = "0005"`, `down_revision = "0004"`), with both `upgrade()` and `downgrade()`.
   Locally: `pip install -r db/requirements.txt && cd db && alembic revision -m "add x"`.
2. If the migration reads a new `*.sql` file, **add that file to the `COPY` in `db/Dockerfile`**
   so the image ships it.
3. If it creates a table the backend writes to, **grant the needed write access explicitly**
   in the same migration (SELECT for `app_read` is automatic). `privileges_test.sql` checks this.
4. Rebuild the image: `docker compose build migrate`.
5. Update `documentation/database/` (DBML, data dictionary) in the same commit.
6. `docker compose up migrate` applies it.

Existing migrations are never edited after they have been applied anywhere.

## Secrets

- `.env` is git-ignored; only `.env.example` with placeholders is committed. It holds:
  - `POSTGRES_USER` / `POSTGRES_PASSWORD` — the cluster superuser (bootstrap/maintenance).
  - `MIGRATOR_PASSWORD`, `API_PASSWORD`, `READER_PASSWORD` — the three login roles.
- No application role is a superuser or can bypass RLS; the `migrate` container runs as a
  non-root OS user and connects as the non-superuser owner `kinetune_migrator`.
- Role passwords are stored as SCRAM-SHA-256 verifiers; user passwords as argon2id (enforced
  by a CHECK constraint).
- The database port is bound to `127.0.0.1`, not to all interfaces.
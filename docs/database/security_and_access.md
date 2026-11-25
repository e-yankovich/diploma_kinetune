# Kinetune — Database Security and Access

DBMS: PostgreSQL 18 · Roles and privileges: `db/04_roles_privileges.sql` (migration 0003) · Login roles: `db/init/` · Test: `db/tests/privileges_test.sql`

These are **PostgreSQL roles**: they decide what a database connection may do. The **application roles** (`coach`, `admin`: who may do what in the platform) are data in the tables `role` / `permission` and are described in the data dictionary, §4.3.

---

## 1. Principles

1. **Least privilege.** Each connection gets only what its use cases need. The backend cannot change the schema, the reference data or the exercise library.
2. **No superuser in daily work.** The cluster superuser is used only to create the cluster and for maintenance. Migrations run as the object owner `kinetune_migrator`, which is not a superuser.
3. **Privileges belong to group roles.** Login roles carry no privileges of their own; they inherit them from NOLOGIN group roles. Changing what the backend may do is one `GRANT` to a group.
4. **Write access is never automatic.** New tables are readable by `app_read` through default privileges, but every write privilege is granted explicitly in the migration that creates the table.
5. **Business rules hold for everyone.** Trigger functions run with the owner's rights (`SECURITY DEFINER`) and a fixed `search_path`, so a rule cannot be bypassed by a role that cannot see the tables the rule reads.
6. **Secrets stay out of Git.** Passwords of the login roles come from `.env` and are used once, when the cluster is created.

---

## 2. Roles

### 2.1 Login roles (created by `db/init/`, passwords from `.env`)

| Login role | Group | Used by | Attributes |
|---|---|---|---|
| `kinetune_migrator` | — (owns all objects) | Migrations (`migrate` service), library import, test seed | `CREATEROLE` only to manage the `app_*` groups; owner of the database |
| `kinetune_api` | `app_write` | FastAPI backend | Connection limit 20; `statement_timeout` 5 s, `lock_timeout` 2 s, `idle_in_transaction_session_timeout` 10 s |
| `kinetune_reader` | `app_read` | Reports, analysis | Connection limit 5; read-only transactions; `statement_timeout` 30 s |

No application role is a superuser or has `BYPASSRLS` / `REPLICATION` (checked by the test). Passwords are stored as SCRAM-SHA-256 verifiers.

### 2.2 Group roles (created by migration 0003)

```text
app_admin  ⊃  app_write  ⊃  app_read        (each includes the one below)
```

| Group | Purpose |
|---|---|
| `app_read` | Read everything except personal data of accounts (`app_user.email`, `password_hash`) |
| `app_write` | The backend: writes operational data (plans, sessions, check-ins, recommendations, decisions) |
| `app_admin` | Maintenance: additionally edits reference data and the exercise library. No DDL. Granted to a named person's login only when needed. |

### 2.3 Creating the group roles safely

Group roles are cluster-wide. Since PostgreSQL 16, a `CREATEROLE` role can manage only the roles it holds with `ADMIN OPTION`. Migration 0003 therefore:

- creates each missing `app_*` role (the migrator then holds `ADMIN OPTION` automatically);
- when it runs as a superuser (e.g. `tests/run_ddl_test.sh` before the migrations), gives `kinetune_migrator` `ADMIN OPTION` on the groups **without membership** (`INHERIT FALSE, SET FALSE`), so later migrations by the migrator still work and the migrator does not get the groups' privileges;
- if a group exists and the migrator cannot manage it, stops with a clear message and the exact `GRANT` a superuser has to run.

---

## 3. Privilege matrix

### 3.1 Tables

R = SELECT · I = INSERT · U = UPDATE (columns listed) · D = DELETE. A group also has everything of the groups below it.

| Table | app_read | app_write (backend) | app_admin |
|---|---|---|---|
| `app_user` | R on `id`, `display_name`, `is_active`, `created_at`, `last_login_at` only | R (all columns, for login), I, U (`email`, `password_hash`, `display_name`, `is_active`, `last_login_at`) | — |
| `role`, `permission`, `role_permission` | R | — | I, U, D |
| `user_role` | R | I, D (granted / revoked, never edited) | U |
| `body_area`, `muscle`, `joint`, `rule` | R | — | I, U, D |
| `exercise`, `exercise_muscle`, `exercise_joint`, `exercise_relation` | R | — | I, U, D |
| `exercise_family`, `exercise_family_member`, `exercise_compensation` | R | — | I, U, D |
| `plan` | R | I, D, U (`title`, `notes`, `target_duration_min`, `status`) | — |
| `plan_item` | R | I, D, U (`exercise_id`, `phase`, `position`, `side`, `reps_count`) | — |
| `session` | R | I, D (cascades to the session's data), U (`group_name`, `starts_at`, `status`, `participants_present`) | — |
| `checkin`, `checkin_discomfort`, `feedback` | R | I only (participant answers are never edited) | — |
| `recommendation` | R | I, U (`explanation`, `explanation_source`: LLM enrichment, T3) | — |
| `recommendation_decision` | R | I only (a decision is final) | — |
| Sequences | — | USAGE | — |

Nobody except the owner `kinetune_migrator` can run DDL, `TRUNCATE` or disable triggers.

### 3.2 Views and functions

| Object | app_read | app_write | Rights when it runs |
|---|---|---|---|
| `v_plan_item`, `v_session_plan` (views) | SELECT | (inherited) | Owner's rights for tables; read-only |
| `item_duration_sec()` | EXECUTE | (inherited) | Caller; reads no table. Needed by readers of the views (a view's functions are checked against the reader) |
| `plan_is_locked()` | EXECUTE | (inherited) | Caller; fixed `search_path` |
| `duplicate_plan()` | — | EXECUTE | **Caller** (`kinetune_api`): it inserts with the backend's own grants; the API checks that the caller owns the plan |
| `has_role()` | EXECUTE | (inherited) | Caller; fixed `search_path` |
| Trigger functions (`fn_*`, 16) | — | — | **Owner** (`SECURITY DEFINER`, `search_path = kinetune, pg_temp`); fired by the triggers, never called directly |

`EXECUTE` is revoked from `PUBLIC` on every function, and default privileges keep it revoked for new functions.

### 3.3 Checklist for a new object

Every migration that adds an object goes through this list; `tests/privileges_test.sql` checks the items marked **T**.

| New object | What to do |
|---|---|
| Table | SELECT for `app_read` comes from default privileges (**T**). Grant **write** access explicitly in the same migration if the backend writes it: `app_write` for operational data, `app_admin` for reference/library data (**T** for the library and reference tables). Use column lists for `UPDATE`. |
| View | Grant SELECT to `app_read` explicitly (**T**: every view is readable). Grant EXECUTE on every function the view calls to the roles that read it. |
| Function | EXECUTE is never `PUBLIC` (**T**). Grant EXECUTE to the narrowest group that needs it. Set `search_path = kinetune, pg_temp`. |
| Trigger function | `ALTER FUNCTION … SECURITY DEFINER SET search_path = kinetune, pg_temp` in `04_roles_privileges.sql` (**T**: every trigger function), and add its name to `TRIGGER_FUNCTIONS` in migration 0003 (downgrade). |
| Enum type | No grant needed (types are usable by everyone who can use the schema). |
| Group role | Only in `04_roles_privileges.sql`, created if missing, `NOLOGIN`. |

---

## 4. Tests

`db/tests/privileges_test.sql` runs as a superuser after the migrations, creates its own fixture rows (ids 9001+) and rolls everything back, so it works on an empty database and on one with test data. It checks:

- catalog rules: no application role is a superuser; every table and view is readable by `app_read`; no function is executable by `PUBLIC`; every trigger function is `SECURITY DEFINER` with a fixed `search_path`; the backend cannot write reference, library or access-control tables; `app_admin` can maintain them;
- `kinetune_api`: the use cases it needs work (login read, check-in, plan edit, decisions, duplicate a plan, read the views), everything else is rejected (editing check-ins, decisions, the library, rule texts, permissions, DDL), and the business rules still apply to it (DQ03, DQ05, DQ22, DQ30–DQ32);
- `kinetune_reader`: reads data and views, cannot read e-mail or password hashes, cannot write or duplicate a plan;
- `app_admin`: maintains the library (families, compensation, edges) and rule texts, but cannot run DDL;
- password policy: only argon2id hashes are accepted;
- default privileges: a new table is readable by `app_read` and not writable until granted.

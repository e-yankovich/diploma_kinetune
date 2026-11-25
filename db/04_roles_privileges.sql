-- =====================================================================
-- Kinetune — database roles and access rights
-- Applied by Alembic migration 0003 (run as kinetune_migrator, which owns
-- all objects; it is NOT a superuser). Manual run:
--   psql -v ON_ERROR_STOP=1 --single-transaction -f 04_roles_privileges.sql
--
-- Group roles (NOLOGIN) carry the privileges; login roles only inherit them:
--
--   app_read   <- kinetune_reader   reports / analysis, read-only
--   app_write  <- kinetune_api      the FastAPI backend
--   app_admin                       maintenance of reference data; granted to
--                                   a named person's login only when needed
--
--   app_admin  ⊃ app_write ⊃ app_read      (each includes the one below)
--
-- Login roles and their passwords are created outside Git by
-- db/init/10_login_roles.sh (first start of the database container).
-- The full access matrix is in the project README ("Roles and access").
-- =====================================================================

SET search_path TO kinetune;

-- ---------------------------------------------------------------------
-- 1. Group roles (cluster-wide objects; created only if missing)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_read') THEN
        CREATE ROLE app_read NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_write') THEN
        CREATE ROLE app_write NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_admin') THEN
        CREATE ROLE app_admin NOLOGIN;
    END IF;
END
$$;

COMMENT ON ROLE app_read  IS 'Kinetune: read all data except e-mail and password hashes';
COMMENT ON ROLE app_write IS 'Kinetune: application backend; writes operational data only';
COMMENT ON ROLE app_admin IS 'Kinetune: maintenance of reference data and exercise library';

GRANT app_read  TO app_write;
GRANT app_write TO app_admin;

-- ---------------------------------------------------------------------
-- 2. Schema and functions
-- ---------------------------------------------------------------------
REVOKE ALL    ON SCHEMA kinetune FROM PUBLIC;
GRANT  USAGE  ON SCHEMA kinetune TO app_read;
REVOKE CREATE ON SCHEMA public   FROM PUBLIC;     -- default since PG 15; stated explicitly

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA kinetune FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION has_role(integer, text) TO app_read;

-- ---------------------------------------------------------------------
-- 3. app_read: SELECT on everything, except personal data of accounts
-- ---------------------------------------------------------------------
GRANT  SELECT ON ALL TABLES IN SCHEMA kinetune TO app_read;
REVOKE SELECT ON app_user FROM app_read;
GRANT  SELECT (id, display_name, is_active, created_at, last_login_at) ON app_user TO app_read;
-- not granted: app_user.email, app_user.password_hash

-- ---------------------------------------------------------------------
-- 4. app_write: what the backend needs, nothing more
--    Reference data, library and access-control definitions are read-only
--    for the backend (they change only through migrations or app_admin).
--    Column lists limit UPDATE to the columns the use cases change.
-- ---------------------------------------------------------------------
GRANT SELECT ON app_user TO app_write;            -- login needs e-mail and hash
GRANT INSERT ON app_user TO app_write;
GRANT UPDATE (email, password_hash, display_name, is_active, last_login_at) ON app_user TO app_write;

GRANT INSERT, DELETE ON user_role TO app_write;   -- roles are granted / revoked, never edited

GRANT INSERT, DELETE ON plan TO app_write;
GRANT UPDATE (title, notes) ON plan TO app_write;

GRANT INSERT, DELETE ON plan_item TO app_write;
GRANT UPDATE (exercise_id, phase, position, side, reps_count) ON plan_item TO app_write;

GRANT INSERT, DELETE ON session TO app_write;     -- DELETE cascades to the session's data
GRANT UPDATE (group_name, starts_at, status, participants_present) ON session TO app_write;

GRANT INSERT ON checkin, checkin_discomfort, feedback TO app_write;    -- participant answers are never edited

GRANT INSERT ON recommendation TO app_write;
GRANT UPDATE (explanation, explanation_source) ON recommendation TO app_write;  -- LLM enrichment (T3)

GRANT INSERT ON recommendation_decision TO app_write;  -- a decision is final: no UPDATE, no DELETE

GRANT USAGE ON ALL SEQUENCES IN SCHEMA kinetune TO app_write;

-- ---------------------------------------------------------------------
-- 5. app_admin: additionally maintains reference data and the library
--    (no DDL: only kinetune_migrator owns objects)
-- ---------------------------------------------------------------------
GRANT INSERT, UPDATE, DELETE ON
      body_area, muscle, joint, rule,
      exercise, exercise_muscle, exercise_joint, exercise_relation,
      role, permission, role_permission
   TO app_admin;
GRANT UPDATE ON user_role TO app_admin;

-- ---------------------------------------------------------------------
-- 6. Default privileges for objects created LATER by kinetune_migrator
--    New tables are readable by app_read automatically; write access is
--    never automatic and must be granted explicitly in the migration that
--    creates the table (checked by tests/privileges_test.sql).
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA kinetune GRANT SELECT ON TABLES    TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA kinetune GRANT USAGE  ON SEQUENCES TO app_write;
ALTER DEFAULT PRIVILEGES IN SCHEMA kinetune REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- ---------------------------------------------------------------------
-- 7. Trigger functions run with the owner's rights (SECURITY DEFINER)
--    The business rules (DQ01–DQ25) must hold whoever writes the data, and
--    the rule checks read tables the caller may not see (e.g. the
--    last-admin check locks all admin rows). A fixed search_path prevents
--    a caller from substituting objects with the same names.
-- ---------------------------------------------------------------------
ALTER FUNCTION has_role(integer, text)            SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_checkin_session_open()          SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_feedback_session_closed()       SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_session_status()                SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_session_owner()                 SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_plan_owner()                    SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_plan_set_updated_at()           SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_plan_touch_from_item()          SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_plan_item_side()                SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_recommendation_consistency()    SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_decision_time()                 SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_last_admin()                    SECURITY DEFINER SET search_path = kinetune, pg_temp;
ALTER FUNCTION fn_granted_by_admin()              SECURITY DEFINER SET search_path = kinetune, pg_temp;

-- ---------------------------------------------------------------------
-- 8. Give the login roles their group (if the bootstrap created them)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'kinetune_api') THEN
        GRANT app_write TO kinetune_api;
    END IF;
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'kinetune_reader') THEN
        GRANT app_read TO kinetune_reader;
    END IF;
END
$$;

-- =====================================================================
-- Kinetune — roles, privileges and password policy test
-- Run as a SUPERUSER after migrations + test data (it switches to each
-- role with SET ROLE). Everything is rolled back at the end.
--   psql -U postgres -d kinetune -v ON_ERROR_STOP=1 -f db/tests/privileges_test.sql
-- =====================================================================
BEGIN;
SET search_path TO kinetune;

CREATE FUNCTION pg_temp.expect_fail(p_label text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS  [%] %  -> rejected: %', current_user, p_label, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL  [%] %  -> was allowed', current_user, p_label;
END $$;

CREATE FUNCTION pg_temp.expect_ok(p_label text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE NOTICE 'PASS  [%] %  -> allowed', current_user, p_label;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL  [%] %  -> rejected: %', current_user, p_label, SQLERRM;
END $$;

-- ---------- no application role is a superuser ----------
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles
                WHERE rolname IN ('kinetune_migrator','kinetune_api','kinetune_reader','app_read','app_write','app_admin')
                  AND (rolsuper OR rolbypassrls OR rolreplication)) THEN
        RAISE EXCEPTION 'FAIL  an application role is a superuser / bypasses RLS / replicates';
    END IF;
    RAISE NOTICE 'PASS  no application role is superuser, BYPASSRLS or REPLICATION';
END $$;

-- ---------- every table is readable by app_read (default privileges work) ----------
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(c.relname, ', ') INTO v
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'kinetune' AND c.relkind = 'r'
       AND c.relname <> 'app_user'               -- column-level grant, checked below
       AND NOT has_table_privilege('app_read', c.oid, 'SELECT');
    IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL  app_read cannot read: %', v; END IF;
    RAISE NOTICE 'PASS  app_read can read every table';
END $$;

-- =========================== kinetune_api ===========================
SET ROLE kinetune_api;
SELECT pg_temp.expect_ok  ('read password hash for login',          $q$SELECT password_hash FROM app_user WHERE email = 'laura@kinetune.test'$q$);
SELECT pg_temp.expect_ok  ('submit a check-in (open session 6)',    $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (6, 3, false, 'en')$q$);
SELECT pg_temp.expect_ok  ('LLM enrichment of an explanation',      $q$UPDATE recommendation SET explanation = 'LLM text', explanation_source = 'llm' WHERE id = 4$q$);
SELECT pg_temp.expect_ok  ('record a decision',                     $q$INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (12, 'accepted')$q$);
SELECT pg_temp.expect_ok  ('create a plan',                         $q$INSERT INTO plan (coach_id, title) VALUES (2, 'New plan')$q$);
SELECT pg_temp.expect_ok  ('delete a session (cascades to its data)', $q$DELETE FROM session WHERE id = 2$q$);
SELECT pg_temp.expect_fail('edit a participant''s check-in',        $q$UPDATE checkin SET energy = 5 WHERE id = 101$q$);
SELECT pg_temp.expect_fail('delete feedback',                       $q$DELETE FROM feedback$q$);
SELECT pg_temp.expect_fail('change a decision',                     $q$UPDATE recommendation_decision SET decision = 'declined' WHERE recommendation_id = 1$q$);
SELECT pg_temp.expect_fail('change affected_count (column not granted)', $q$UPDATE recommendation SET affected_count = 99 WHERE id = 1$q$);
SELECT pg_temp.expect_fail('edit the exercise library',             $q$INSERT INTO exercise (name, mode, starting_pose, difficulty, default_duration_sec) VALUES ('X','dynamic','lying',1,60)$q$);
SELECT pg_temp.expect_fail('edit rule texts',                       $q$UPDATE rule SET explanation = 'x' WHERE id = 9$q$);
SELECT pg_temp.expect_fail('edit permissions',                      $q$INSERT INTO role_permission VALUES (1, 10)$q$);
SELECT pg_temp.expect_fail('create a table (DDL)',                  $q$CREATE TABLE kinetune.hack (id int)$q$);
SELECT pg_temp.expect_fail('create a table in public',              $q$CREATE TABLE public.hack (id int)$q$);
SELECT pg_temp.expect_fail('drop a table',                          $q$DROP TABLE kinetune.feedback$q$);
SELECT pg_temp.expect_fail('truncate',                              $q$TRUNCATE kinetune.checkin CASCADE$q$);
SELECT pg_temp.expect_fail('disable a trigger',                     $q$ALTER TABLE kinetune.checkin DISABLE TRIGGER ALL$q$);
-- business rules still apply to the backend (SECURITY DEFINER triggers)
SELECT pg_temp.expect_fail('DQ03 check-in into a closed session',   $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1, 3, false, 'en')$q$);
SELECT pg_temp.expect_fail('DQ22 remove the last admin',            $q$DELETE FROM user_role WHERE user_id = 1 AND role_id = 2$q$);
-- password policy
SELECT pg_temp.expect_fail('store a plain-text password',           $q$INSERT INTO app_user (email, password_hash, display_name) VALUES ('p@x.test', 'Secret123!', 'P')$q$);
SELECT pg_temp.expect_fail('store an MD5 hash',                     $q$INSERT INTO app_user (email, password_hash, display_name) VALUES ('m@x.test', md5('Secret123!'), 'M')$q$);
SELECT pg_temp.expect_fail('store a SHA-1 hash',                    $q$INSERT INTO app_user (email, password_hash, display_name) VALUES ('s@x.test', '5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8', 'S')$q$);
SELECT pg_temp.expect_fail('store a SHA-256 hash',                  $q$INSERT INTO app_user (email, password_hash, display_name) VALUES ('t@x.test', encode(sha256('x'::bytea), 'hex'), 'T')$q$);
SELECT pg_temp.expect_fail('store a bcrypt hash',                   $q$INSERT INTO app_user (email, password_hash, display_name) VALUES ('b@x.test', '$2b$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW', 'B')$q$);
SELECT pg_temp.expect_ok  ('store an argon2id hash',                $q$INSERT INTO app_user (email, password_hash, display_name) VALUES ('a@x.test', '$argon2id$v=19$m=65536,t=3,p=4$ijGjM2XusNzizEHNbAb0uw$VSXuYAG0q8co/44+hZwTIu1eTRasx2DvCMM+I6ins2k', 'A')$q$);
RESET ROLE;

-- =========================== kinetune_reader ===========================
SET ROLE kinetune_reader;
SELECT pg_temp.expect_ok  ('read plans and sessions',               $q$SELECT count(*) FROM plan JOIN session ON session.plan_id = plan.id$q$);
SELECT pg_temp.expect_ok  ('read display names',                    $q$SELECT display_name, is_active FROM app_user$q$);
SELECT pg_temp.expect_fail('read e-mail addresses',                 $q$SELECT email FROM app_user$q$);
SELECT pg_temp.expect_fail('read password hashes',                  $q$SELECT password_hash FROM app_user$q$);
SELECT pg_temp.expect_fail('SELECT * from app_user',                $q$SELECT * FROM app_user$q$);
SELECT pg_temp.expect_fail('insert a check-in',                     $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (6, 3, false, 'en')$q$);
SELECT pg_temp.expect_fail('update a plan',                         $q$UPDATE plan SET title = 'x'$q$);
RESET ROLE;

-- =========================== app_admin (maintenance) ===========================
SET ROLE app_admin;
SELECT pg_temp.expect_ok  ('edit the exercise library',             $q$UPDATE exercise SET description = 'updated' WHERE id = 1$q$);
SELECT pg_temp.expect_ok  ('edit rule texts',                       $q$UPDATE rule SET explanation = explanation || ' ' WHERE id = 9$q$);
SELECT pg_temp.expect_fail('DDL is still not allowed',              $q$ALTER TABLE kinetune.exercise ADD COLUMN x int$q$);
RESET ROLE;

-- ===== new objects: default privileges give SELECT to app_read only =====
SET ROLE kinetune_migrator;
CREATE TABLE kinetune.zz_new_table (id int);
RESET ROLE;
DO $$ BEGIN
    IF NOT has_table_privilege('app_read', 'kinetune.zz_new_table', 'SELECT') THEN
        RAISE EXCEPTION 'FAIL  new table is not readable by app_read'; END IF;
    IF has_table_privilege('app_write', 'kinetune.zz_new_table', 'INSERT') THEN
        RAISE EXCEPTION 'FAIL  new table is writable without an explicit grant'; END IF;
    RAISE NOTICE 'PASS  new table: SELECT for app_read automatic, no write access until granted';
END $$;

ROLLBACK;

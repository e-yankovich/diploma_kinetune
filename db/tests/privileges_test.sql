-- =====================================================================
-- Kinetune — roles, privileges and password policy test
-- Run as a SUPERUSER after the migrations (it switches to each role with
-- SET ROLE). It creates its own fixture rows (ids 9001+), so it runs on an
-- empty database and on one with test data. Everything is rolled back.
--   psql -U postgres -d kinetune -v ON_ERROR_STOP=1 -f db/tests/privileges_test.sql
-- Matrix and checklist: docs/database/security_and_access.md
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

-- ===================== catalog checks =====================

-- no application role is a superuser
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles
                WHERE rolname IN ('kinetune_migrator','kinetune_api','kinetune_reader','kinetune_admin','app_read','app_write','app_admin')
                  AND (rolsuper OR rolbypassrls OR rolreplication)) THEN
        RAISE EXCEPTION 'FAIL  an application role is a superuser / bypasses RLS / replicates';
    END IF;
    RAISE NOTICE 'PASS  no application role is superuser, BYPASSRLS or REPLICATION';
END $$;

-- every table is readable by app_read (default privileges work)
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

-- every view is readable by app_read
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(c.relname, ', ') INTO v
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'kinetune' AND c.relkind = 'v'
       AND NOT has_table_privilege('app_read', c.oid, 'SELECT');
    IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL  app_read cannot read view(s): %', v; END IF;
    RAISE NOTICE 'PASS  app_read can read every view';
END $$;

-- no function is executable by PUBLIC
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(p.proname, ', ') INTO v
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'kinetune'
       AND has_function_privilege('public', p.oid, 'EXECUTE');
    IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL  PUBLIC can execute: %', v; END IF;
    RAISE NOTICE 'PASS  no kinetune function is executable by PUBLIC';
END $$;

-- every trigger function runs with the owner's rights and a fixed search_path
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(p.proname, ', ') INTO v
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'kinetune'
       AND p.prorettype = 'trigger'::regtype
       AND NOT (p.prosecdef AND 'search_path=kinetune, pg_temp' = ANY (coalesce(p.proconfig, '{}')));
    IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL  trigger function(s) not SECURITY DEFINER with a fixed search_path: %', v; END IF;
    RAISE NOTICE 'PASS  every trigger function is SECURITY DEFINER with search_path = kinetune, pg_temp';
END $$;

-- the backend cannot write reference data, the library or access-control definitions
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(t || ':' || priv, ', ') INTO v
      FROM unnest(ARRAY['body_area','muscle','joint','rule',
                        'exercise','exercise_muscle','exercise_joint','exercise_relation',
                        'exercise_family','exercise_family_member','exercise_compensation',
                        'role','permission','role_permission']) t,
           unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE']) priv
     WHERE has_table_privilege('app_write', 'kinetune.' || t, priv);
    IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL  app_write can write: %', v; END IF;
    RAISE NOTICE 'PASS  app_write cannot write reference, library or access-control tables';
END $$;

-- app_admin maintains every library and reference table
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(t || ':' || priv, ', ') INTO v
      FROM unnest(ARRAY['body_area','muscle','joint','rule',
                        'exercise','exercise_muscle','exercise_joint','exercise_relation',
                        'exercise_family','exercise_family_member','exercise_compensation']) t,
           unnest(ARRAY['INSERT','UPDATE','DELETE']) priv
     WHERE NOT has_table_privilege('app_admin', 'kinetune.' || t, priv);
    IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL  app_admin cannot write: %', v; END IF;
    RAISE NOTICE 'PASS  app_admin can maintain every library and reference table';
END $$;

-- ===================== fixture (as superuser) =====================
-- argon2id hash of an unused test password (the password policy needs a PHC string)
INSERT INTO app_user (id, email, password_hash, display_name) OVERRIDING SYSTEM VALUE VALUES
  (9001, 'coach.priv@kinetune.test', '$argon2id$v=19$m=65536,t=3,p=4$ijGjM2XusNzizEHNbAb0uw$VSXuYAG0q8co/44+hZwTIu1eTRasx2DvCMM+I6ins2k', 'Priv Coach'),
  (9002, 'admin.priv@kinetune.test', '$argon2id$v=19$m=65536,t=3,p=4$ijGjM2XusNzizEHNbAb0uw$VSXuYAG0q8co/44+hZwTIu1eTRasx2DvCMM+I6ins2k', 'Priv Admin');
INSERT INTO user_role (user_id, role_id)
  SELECT 9001, id FROM role WHERE code = 'coach'
  UNION ALL
  SELECT 9002, id FROM role WHERE code = 'admin';

INSERT INTO exercise (id, name, mode, starting_pose, difficulty, rep_duration_sec) OVERRIDING SYSTEM VALUE VALUES
  (9001, 'Priv test dynamic', 'dynamic', 'seated', 1, 4),
  (9002, 'Priv test static',  'static',  'seated', 1, 15);
INSERT INTO exercise_joint (exercise_id, joint_id, is_primary, load_level)
  SELECT 9001, id, true, 'low' FROM joint WHERE name = 'knee';

-- plan 9001: reviewed and used by sessions (locked); plan 9002: draft, unlocked
INSERT INTO plan (id, coach_id, title) OVERRIDING SYSTEM VALUE VALUES
  (9001, 9001, 'Priv locked plan'), (9002, 9001, 'Priv draft plan');
INSERT INTO plan_item (id, plan_id, exercise_id, phase, position, reps_count) OVERRIDING SYSTEM VALUE VALUES
  (9001, 9001, 9001, 'warm_up', 1, 10),
  (9002, 9001, 9002, 'main',    1, 4),
  (9003, 9002, 9001, 'warm_up', 1, 10);
UPDATE plan SET target_duration_min = 45 WHERE id = 9001;
UPDATE plan SET status = 'completed' WHERE id = 9001;
UPDATE plan SET status = 'reviewed'  WHERE id = 9001;

-- S9001: closed, with a check-in, feedback and two recommendations;
-- S9002: open (accepts check-ins); S9003: closed, for the delete test
INSERT INTO session (id, coach_id, plan_id, group_name, starts_at, checkin_token) OVERRIDING SYSTEM VALUE VALUES
  (9001, 9001, 9001, 'Priv closed', now(), rpad('priv_s1_', 43, 'x')),
  (9002, 9001, 9001, 'Priv open',   now(), rpad('priv_s2_', 43, 'x')),
  (9003, 9001, 9001, 'Priv delete', now(), rpad('priv_s3_', 43, 'x'));
INSERT INTO checkin (id, session_id, energy, poor_sleep, language) OVERRIDING SYSTEM VALUE VALUES
  (9001, 9001, 'low', true, 'en'), (9003, 9003, 'normal', false, 'ru');
UPDATE session SET status = 'closed', participants_present = 5 WHERE id IN (9001, 9003);
INSERT INTO feedback (session_id, rating) VALUES (9001, 5);
INSERT INTO recommendation (id, session_id, plan_item_id, rule_id, form, candidate_exercise_id,
                            affected_count, explanation, explanation_source) OVERRIDING SYSTEM VALUE VALUES
  (9001, 9001, 9001, 10, 'replacement', 9002, 3, 'Template text', 'template');
INSERT INTO recommendation (id, session_id, plan_item_id, rule_id, form, is_warning,
                            affected_count, explanation, explanation_source) OVERRIDING SYSTEM VALUE VALUES
  (9002, 9001, 9002, 11, 'alternative', true, 1, 'Fewer repetitions', 'template');

-- =========================== kinetune_api ===========================
SET ROLE kinetune_api;
SELECT pg_temp.expect_ok  ('read password hash for login',          $q$SELECT password_hash FROM app_user WHERE email = 'coach.priv@kinetune.test'$q$);
SELECT pg_temp.expect_ok  ('submit a check-in (open session)',      $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (9002, 'normal', false, 'en')$q$);
SELECT pg_temp.expect_ok  ('LLM enrichment of an explanation',      $q$UPDATE recommendation SET explanation = 'LLM text', explanation_source = 'llm' WHERE id = 9002$q$);
SELECT pg_temp.expect_ok  ('record a decision',                     $q$INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (9001, 'accepted')$q$);
SELECT pg_temp.expect_ok  ('create a plan',                         $q$INSERT INTO plan (coach_id, title) VALUES (9001, 'New plan')$q$);
SELECT pg_temp.expect_ok  ('set the target duration',               $q$UPDATE plan SET target_duration_min = 40 WHERE id = 9002$q$);
SELECT pg_temp.expect_ok  ('set the plan status',                   $q$UPDATE plan SET status = 'completed' WHERE id = 9002$q$);
SELECT pg_temp.expect_ok  ('edit an item of an unlocked plan',      $q$UPDATE plan_item SET reps_count = 12 WHERE id = 9003$q$);
SELECT pg_temp.expect_ok  ('read the concrete plan of a session',   $q$SELECT * FROM v_session_plan WHERE session_id = 9001$q$);
SELECT pg_temp.expect_ok  ('read plan items with durations',        $q$SELECT * FROM v_plan_item WHERE plan_id = 9001$q$);
SELECT pg_temp.expect_ok  ('check the plan lock',                   $q$SELECT plan_is_locked(9001)$q$);
SELECT pg_temp.expect_ok  ('duplicate a locked plan',               $q$SELECT duplicate_plan(9001)$q$);
SELECT pg_temp.expect_ok  ('read the library (families, compensation)', $q$SELECT count(*) FROM exercise_family_member JOIN exercise_compensation USING (exercise_id)$q$);
-- business rules still apply to the backend (SECURITY DEFINER triggers)
SELECT pg_temp.expect_fail('DQ32 reviewed with an undecided recommendation', $q$UPDATE session SET status = 'reviewed' WHERE id = 9001$q$);
SELECT pg_temp.expect_fail('DQ03 check-in into a closed session',   $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (9001, 'normal', false, 'en')$q$);
SELECT pg_temp.expect_fail('DQ22 remove the last admin',            $q$DELETE FROM user_role WHERE role_id = (SELECT id FROM role WHERE code = 'admin')$q$);
SELECT pg_temp.expect_fail('DQ31 edit an item of a locked plan',    $q$UPDATE plan_item SET reps_count = 1 WHERE id = 9001$q$);
SELECT pg_temp.expect_fail('DQ31 rename a locked plan',             $q$UPDATE plan SET title = 'x' WHERE id = 9001$q$);
SELECT pg_temp.expect_fail('DQ30 session from a non-reviewed plan', $q$INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token) VALUES (9001, 9002, 'G', now(), repeat('q', 43))$q$);
SELECT pg_temp.expect_fail('DQ05 close without participants present', $q$UPDATE session SET status = 'closed' WHERE id = 9002$q$);
-- normal flow continues
SELECT pg_temp.expect_ok  ('decide the last recommendation',        $q$INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (9002, 'declined')$q$);
SELECT pg_temp.expect_ok  ('mark a session reviewed (all decided)', $q$UPDATE session SET status = 'reviewed' WHERE id = 9001$q$);
SELECT pg_temp.expect_ok  ('delete a session (cascades to its data)', $q$DELETE FROM session WHERE id = 9003$q$);
-- not allowed
SELECT pg_temp.expect_fail('edit a participant''s check-in',        $q$UPDATE checkin SET energy = 'high' WHERE id = 9001$q$);
SELECT pg_temp.expect_fail('delete feedback',                       $q$DELETE FROM feedback$q$);
SELECT pg_temp.expect_fail('change a decision',                     $q$UPDATE recommendation_decision SET decision = 'declined' WHERE recommendation_id = 9001$q$);
SELECT pg_temp.expect_fail('change affected_count (column not granted)', $q$UPDATE recommendation SET affected_count = 99 WHERE id = 9001$q$);
SELECT pg_temp.expect_fail('edit the exercise library',             $q$INSERT INTO exercise (name, mode, starting_pose, difficulty, rep_duration_sec) VALUES ('X','dynamic','supine',1,4)$q$);
SELECT pg_temp.expect_fail('change a joint load level',             $q$UPDATE exercise_joint SET load_level = 'high' WHERE exercise_id = 9001$q$);
SELECT pg_temp.expect_fail('create an exercise family',             $q$INSERT INTO exercise_family (name) VALUES ('priv family')$q$);
SELECT pg_temp.expect_fail('add a compensation',                    $q$INSERT INTO exercise_compensation VALUES (9002, 9001)$q$);
SELECT pg_temp.expect_fail('add a graph edge',                      $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, type, is_directed) VALUES (9001, 9002, 'variation', false)$q$);
SELECT pg_temp.expect_fail('views are read-only',                   $q$DELETE FROM v_plan_item$q$);
SELECT pg_temp.expect_fail('edit rule texts',                       $q$UPDATE rule SET explanation = 'x' WHERE id = 9$q$);
SELECT pg_temp.expect_fail('edit permissions',                      $q$INSERT INTO role_permission VALUES (1, 10)$q$);
SELECT pg_temp.expect_fail('create a table (DDL)',                  $q$CREATE TABLE kinetune.hack (id int)$q$);
SELECT pg_temp.expect_fail('create a table in public',              $q$CREATE TABLE public.hack (id int)$q$);
SELECT pg_temp.expect_fail('drop a table',                          $q$DROP TABLE kinetune.feedback$q$);
SELECT pg_temp.expect_fail('truncate',                              $q$TRUNCATE kinetune.checkin CASCADE$q$);
SELECT pg_temp.expect_fail('disable a trigger',                     $q$ALTER TABLE kinetune.checkin DISABLE TRIGGER ALL$q$);
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
SELECT pg_temp.expect_ok  ('read the library (families, compensation)', $q$SELECT count(*) FROM exercise_family, exercise_compensation$q$);
SELECT pg_temp.expect_fail('read e-mail addresses',                 $q$SELECT email FROM app_user$q$);
SELECT pg_temp.expect_fail('read password hashes',                  $q$SELECT password_hash FROM app_user$q$);
SELECT pg_temp.expect_fail('SELECT * from app_user',                $q$SELECT * FROM app_user$q$);
SELECT pg_temp.expect_fail('insert a check-in',                     $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (9002, 'normal', false, 'en')$q$);
SELECT pg_temp.expect_fail('update a plan',                         $q$UPDATE plan SET title = 'x'$q$);
SELECT pg_temp.expect_ok  ('read the concrete plan of a session',   $q$SELECT * FROM v_session_plan$q$);
SELECT pg_temp.expect_ok  ('calculate an item duration',            $q$SELECT item_duration_sec(4, 15, false, 'both')$q$);
SELECT pg_temp.expect_ok  ('check the plan lock',                   $q$SELECT plan_is_locked(9001)$q$);
SELECT pg_temp.expect_fail('duplicate a plan',                      $q$SELECT duplicate_plan(9001)$q$);
RESET ROLE;

-- =========================== kinetune_admin (library import) ===========================
DO $$ BEGIN
    IF NOT pg_has_role('kinetune_admin', 'app_admin', 'MEMBER') THEN
        RAISE EXCEPTION 'FAIL  kinetune_admin is not a member of app_admin'; END IF;
    RAISE NOTICE 'PASS  kinetune_admin holds app_admin';
END $$;
SET ROLE kinetune_admin;
SELECT pg_temp.expect_ok  ('lock the library for an import',        $q$LOCK TABLE exercise IN SHARE ROW EXCLUSIVE MODE$q$);
SELECT pg_temp.expect_ok  ('insert an exercise',                    $q$INSERT INTO exercise (name, mode, starting_pose, difficulty, rep_duration_sec) VALUES ('Priv import','dynamic','supine',1,4)$q$);
SELECT pg_temp.expect_ok  ('rebuild graph edges',                   $q$DELETE FROM exercise_relation WHERE from_exercise_id = 9001$q$);
SELECT pg_temp.expect_ok  ('check plan usage before --replace',     $q$SELECT count(*) FROM plan_item$q$);
SELECT pg_temp.expect_fail('DDL is not allowed',                    $q$CREATE TABLE kinetune.hack (id int)$q$);
SELECT pg_temp.expect_fail('truncate is not allowed',               $q$TRUNCATE kinetune.exercise_relation$q$);
RESET ROLE;

-- =========================== app_admin (maintenance) ===========================
SET ROLE app_admin;
SELECT pg_temp.expect_ok  ('edit the exercise library',             $q$UPDATE exercise SET description = 'updated' WHERE id = 9001$q$);
SELECT pg_temp.expect_ok  ('create a family and add members',       $q$WITH f AS (INSERT INTO exercise_family (name) VALUES ('priv family') RETURNING id) INSERT INTO exercise_family_member SELECT e, f.id FROM f, unnest(ARRAY[9001, 9002]) e$q$);
SELECT pg_temp.expect_ok  ('add a compensation',                    $q$INSERT INTO exercise_compensation VALUES (9002, 9001)$q$);
SELECT pg_temp.expect_ok  ('add a graph edge',                      $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, type, is_directed) VALUES (9001, 9002, 'variation', false)$q$);
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

-- Kinetune — DDL smoke test
-- Runs a valid end-to-end flow, then checks that each constraint/trigger
-- rejects bad data. Everything is rolled back at the end.
-- psql -v ON_ERROR_STOP=1 -f tests/ddl_smoke_test.sql

BEGIN;
SET search_path TO kinetune;

-- helper: run a statement and require it to FAIL
CREATE FUNCTION pg_temp.expect_fail(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS  %  -> rejected: %', p_label, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL  %  -> statement was accepted', p_label;
END $$;

-- ---------- valid flow ----------
INSERT INTO role (code, name) VALUES ('coach', 'Coach'), ('admin', 'Administrator');
INSERT INTO permission (code, description) VALUES ('plan.write', 'Edit own plans');
INSERT INTO role_permission SELECT r.id, p.id FROM role r, permission p WHERE r.code = 'coach';

INSERT INTO app_user (email, password_hash, display_name) VALUES
  ('coach@example.com', 'argon2id$x', 'Coach'),
  ('admin@example.com', 'argon2id$y', 'Admin');
INSERT INTO user_role (user_id, role_id)
  SELECT u.id, r.id FROM app_user u, role r
   WHERE (u.email, r.code) IN (('coach@example.com', 'coach'), ('admin@example.com', 'admin'));

INSERT INTO body_area (code, name_en, name_ru) VALUES ('knees', 'Knees', 'Колени'), ('lower_back', 'Lower back', 'Поясница');
INSERT INTO muscle (name, body_area_id) VALUES ('quadriceps', 1), ('erector spinae', 2);
INSERT INTO joint  (name, body_area_id) VALUES ('knee', 1);
INSERT INTO rule (id, description, explanation)
  SELECT g, 'BR' || g, 'Explanation BR' || g FROM generate_series(1, 11) g;

INSERT INTO exercise (name, mode, starting_pose, difficulty, default_duration_sec) VALUES
  ('Back extension',   'dynamic', 'lying',    1, 60),   -- id 1
  ('Deep lunge',       'static',  'standing', 2, 60),   -- id 2
  ('Half kneel lunge', 'static',  'seated',   1, 60),   -- id 3
  ('Standing balance', 'static',  'balance',  2, 30);   -- id 4
UPDATE exercise SET is_symmetric = false WHERE id = 2;
UPDATE exercise SET required_compensation_id = 1 WHERE id = 2;
INSERT INTO exercise_muscle VALUES (2, 1, true), (3, 1, true), (1, 2, true);
INSERT INTO exercise_joint  VALUES (2, 1, true), (3, 1, false);
INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, type, is_directed)
  VALUES (2, 3, 'variation', false), (3, 2, 'progression', true);

INSERT INTO plan (coach_id, title) VALUES (1, 'Tuesday stretch');
INSERT INTO plan_item (plan_id, exercise_id, phase, position, duration_sec, side, reps_count) VALUES
  (1, 1, 'warm_up', 1, 60, 'both', 10),
  (1, 2, 'main',    1, 60, 'left', NULL),
  (1, 2, 'main',    2, 60, 'right', NULL);

-- reorder: swap positions 1 and 2 in one transaction (deferred UNIQUE)
UPDATE plan_item SET position = 2 WHERE id = 2;
UPDATE plan_item SET position = 1 WHERE id = 3;
SET CONSTRAINTS uq_plan_item_position IMMEDIATE;   -- force the check now: must pass
SET CONSTRAINTS uq_plan_item_position DEFERRED;

INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token)
  VALUES (1, 1, 'Tuesday evening', now() + interval '1 hour', repeat('a', 43));
INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1, 2, true, 'ru');
INSERT INTO checkin_discomfort VALUES (1, 1);
SELECT pg_temp.expect_fail('energy 1..5',
  $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1,6,false,'en')$q$);
SELECT pg_temp.expect_fail('language en/ru',
  $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1,3,false,'de')$q$);
SELECT pg_temp.expect_fail('feedback before check-in is closed',
  $q$INSERT INTO feedback (session_id, rating) VALUES (1,4)$q$);

UPDATE session SET status = 'closed' WHERE id = 1;
DO $$ BEGIN
  IF (SELECT checkin_closed_at FROM kinetune.session WHERE id = 1) IS NULL THEN
    RAISE EXCEPTION 'FAIL checkin_closed_at not set by trigger'; END IF;
  RAISE NOTICE 'PASS  close sets checkin_closed_at';
END $$;

INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, candidate_exercise_id,
                            affected_count, explanation, explanation_source)
  VALUES (1, 2, 9, 'alternative', 3, 1, '1 of 6 present reported knee discomfort', 'template');
INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, is_warning,
                            affected_count, explanation, explanation_source)
  VALUES (1, 3, 11, 'replacement', true, 3, 'Fewer repetitions, smaller amplitude', 'template');
INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (1, 'accepted');
INSERT INTO feedback (session_id, rating, comment) VALUES (1, 5, 'Good');
UPDATE session SET status = 'done', participants_present = 6 WHERE id = 1;
DO $$ BEGIN RAISE NOTICE 'PASS  valid flow completed'; END $$;

-- ---------- rejections: constraints ----------
SELECT pg_temp.expect_fail('email must be lower-case',
  $q$INSERT INTO app_user (email, password_hash, display_name) VALUES ('X@Y.com','h','X')$q$);
SELECT pg_temp.expect_fail('difficulty 1..3',
  $q$INSERT INTO exercise (name, mode, starting_pose, difficulty, default_duration_sec) VALUES ('Bad','dynamic','lying',4,60)$q$);
SELECT pg_temp.expect_fail('compensation not self',
  $q$UPDATE exercise SET required_compensation_id = id WHERE id = 3$q$);
SELECT pg_temp.expect_fail('relation not self',
  $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, type) VALUES (1,1,'variation')$q$);
SELECT pg_temp.expect_fail('undirected edge stored with from < to',
  $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, type, is_directed) VALUES (4,1,'variation',false)$q$);
SELECT pg_temp.expect_fail('warning <=> no candidate',
  $q$INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, is_warning, candidate_exercise_id, affected_count, explanation, explanation_source) VALUES (1,2,9,'alternative',true,3,1,'x','template')$q$);
SELECT pg_temp.expect_fail('one decision per recommendation',
  $q$INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (1,'declined')$q$);
SELECT pg_temp.expect_fail('cannot delete exercise in use (RESTRICT)',
  $q$DELETE FROM exercise WHERE id = 2$q$);
SELECT pg_temp.expect_fail('rule id 1..11',
  $q$INSERT INTO rule VALUES (12,'x','y')$q$);
SELECT pg_temp.expect_fail('new session must start open',
  $q$INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token, status) VALUES (1,1,'G',now(),repeat('b',43),'closed')$q$);
SELECT pg_temp.expect_fail('check-in token format',
  $q$INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token) VALUES (1,1,'G',now(),'short')$q$);

-- ---------- rejections: triggers ----------
SELECT pg_temp.expect_fail('DQ03 check-in after close',
  $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1,3,false,'en')$q$);
SELECT pg_temp.expect_fail('DQ04 status backwards',
  $q$UPDATE session SET status = 'open' WHERE id = 1$q$);
SELECT pg_temp.expect_fail('DQ21 plan owner must be coach',
  $q$INSERT INTO plan (coach_id, title) VALUES (2,'Admin plan')$q$);
SELECT pg_temp.expect_fail('DQ25 symmetric exercise needs side both',
  $q$INSERT INTO plan_item (plan_id, exercise_id, phase, position, duration_sec, side) VALUES (1,1,'cool_down',1,60,'left')$q$);
SELECT pg_temp.expect_fail('DQ02 candidate differs from original',
  $q$INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, candidate_exercise_id, affected_count, explanation, explanation_source) VALUES (1,2,9,'alternative',2,1,'x','template')$q$);
SELECT pg_temp.expect_fail('DQ22 last admin cannot be removed',
  $q$DELETE FROM user_role WHERE user_id = 2$q$);
SELECT pg_temp.expect_fail('DQ22 last admin cannot be deactivated',
  $q$UPDATE app_user SET is_active = false WHERE id = 2$q$);
SELECT pg_temp.expect_fail('DQ23 only admin grants roles',
  $q$INSERT INTO user_role (user_id, role_id, granted_by) SELECT 2, id, 1 FROM role WHERE code = 'coach'$q$);

-- DQ01: second plan + session; recommendation pointing at another plan's item
INSERT INTO plan (coach_id, title) VALUES (1, 'Other plan');
INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token)
  SELECT 1, id, 'Thursday', now(), repeat('c', 43) FROM plan WHERE title = 'Other plan';
UPDATE session SET status = 'closed' WHERE group_name = 'Thursday';
SELECT pg_temp.expect_fail('DQ01 plan item from another plan',
  $q$INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, candidate_exercise_id, affected_count, explanation, explanation_source) SELECT id,2,9,'alternative',3,1,'x','template' FROM session WHERE group_name = 'Thursday'$q$);
SELECT pg_temp.expect_fail('DQ05 done requires participants_present',
  $q$UPDATE session SET status = 'done' WHERE group_name = 'Thursday'$q$);
-- make user 2 a coach too, so the next test fails on ownership, not on the role
INSERT INTO user_role (user_id, role_id) SELECT 2, id FROM role WHERE code = 'coach';
SELECT pg_temp.expect_fail('DQ08 session plan must belong to its coach',
  $q$INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token) SELECT 2, id, 'X', now(), repeat('d',43) FROM plan WHERE title = 'Other plan'$q$);

-- deferred UNIQUE: a real duplicate must fail at commit time
SELECT pg_temp.expect_fail('duplicate position fails at constraint check',
  $q$UPDATE plan_item SET position = 1 WHERE id = 2; SET CONSTRAINTS uq_plan_item_position IMMEDIATE$q$);

-- cascade: deleting a session removes its participant data
DELETE FROM session WHERE id = 1;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM kinetune.checkin) OR EXISTS (SELECT 1 FROM kinetune.recommendation)
     OR EXISTS (SELECT 1 FROM kinetune.feedback) THEN
    RAISE EXCEPTION 'FAIL cascade did not remove session data'; END IF;
  RAISE NOTICE 'PASS  deleting a session cascades to its data';
END $$;

ROLLBACK;

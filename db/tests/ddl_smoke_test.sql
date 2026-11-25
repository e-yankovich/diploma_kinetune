-- Kinetune — DDL smoke test
-- Runs a valid end-to-end flow, then checks that each constraint/trigger
-- rejects bad data. Everything is rolled back at the end.
-- Needs 01_schema.sql, 02_triggers.sql and 04_roles_privileges.sql applied
-- (tests/run_ddl_test.sh does this). The test inserts its own reference rows.
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

-- helper: require a condition to be true
CREATE FUNCTION pg_temp.expect_true(p_label text, p_ok boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL  %', p_label;
    END IF;
    RAISE NOTICE 'PASS  %', p_label;
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

INSERT INTO body_area (code, name_en, name_ru, is_in_checkin) VALUES
  ('knee', 'Knee', 'Колено', true), ('lower_back', 'Lower back', 'Поясница', true);
INSERT INTO body_area (code, name_en, name_ru) VALUES ('abdomen', 'Abdomen', 'Живот');
SELECT pg_temp.expect_true('body_area.is_in_checkin defaults to false',
  (SELECT NOT is_in_checkin FROM body_area WHERE code = 'abdomen'));
INSERT INTO muscle (name, body_area_id) VALUES ('quads', 1), ('back extensors', 2);
INSERT INTO joint  (name, body_area_id) VALUES ('knee', 1), ('lumbar spine', 2);
INSERT INTO rule (id, description, explanation)
  SELECT g, 'BR' || g, 'Explanation BR' || g FROM generate_series(1, 11) g;

INSERT INTO exercise (name, mode, starting_pose, difficulty, rep_duration_sec) VALUES
  ('Back extension',   'dynamic', 'prone',    1, 4),    -- id 1
  ('Deep lunge',       'static',  'kneeling', 2, 15),   -- id 2
  ('Half kneel lunge', 'static',  'kneeling', 1, 15),   -- id 3
  ('Standing balance', 'static',  'balance',  2, 15),   -- id 4
  ('Cat-cow',          'dynamic', 'quadruped', 1, 4);   -- id 5
UPDATE exercise SET is_symmetric = false WHERE id IN (2, 3);
INSERT INTO exercise_muscle VALUES (2, 1, true), (3, 1, true), (1, 2, true);
-- deep lunge: knee is not its primary joint, but carries a high load
INSERT INTO exercise_joint (exercise_id, joint_id, is_primary, load_level) VALUES
  (2, 1, false, 'high'), (3, 1, true, 'low'), (1, 2, true, 'medium');

-- families and compensation (M:N): the deep lunge has two acceptable compensations
INSERT INTO exercise_family (name) VALUES ('hip flexor stretch'), ('spine mobility');
INSERT INTO exercise_family_member VALUES (2, 1), (3, 1), (1, 2), (5, 2);
INSERT INTO exercise_compensation VALUES (2, 1), (2, 5);
SELECT pg_temp.expect_true('an exercise can have several compensating exercises (BR6)',
  (SELECT count(*) = 2 FROM exercise_compensation WHERE exercise_id = 2));

-- variation graph = star around each family: nothing stored per pair
SELECT pg_temp.expect_true('v_exercise_variation: family members are variations, both directions',
  (SELECT array_agg(exercise_id || '-' || variation_id ORDER BY exercise_id, variation_id)
          = ARRAY['1-5', '2-3', '3-2', '5-1']
     FROM v_exercise_variation));
SELECT pg_temp.expect_true('v_exercise_variation: no pair across families, no self-pair',
  NOT EXISTS (SELECT 1 FROM v_exercise_variation
               WHERE exercise_id = variation_id OR (exercise_id, variation_id) IN ((2, 1), (3, 5))));

-- progression graph: directed edges only (automatic and manual)
INSERT INTO exercise_relation (from_exercise_id, to_exercise_id) VALUES (3, 2);          -- automatic
INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, is_manual) VALUES (3, 4, true);
SELECT pg_temp.expect_true('exercise_relation: type defaults to progression, is_manual to false',
  (SELECT type = 'progression' AND NOT is_manual FROM exercise_relation WHERE (from_exercise_id, to_exercise_id) = (3, 2)));
SELECT pg_temp.expect_true('a pair can be in both graphs (shared family + progression 3 -> 2)',
  EXISTS (SELECT 1 FROM v_exercise_variation v JOIN exercise_relation r
                    ON (r.from_exercise_id, r.to_exercise_id) = (v.exercise_id, v.variation_id)));

INSERT INTO plan (coach_id, title) VALUES (1, 'Tuesday stretch');                -- plan 1
INSERT INTO plan_item (plan_id, exercise_id, phase, position, side, reps_count) VALUES
  (1, 1, 'warm_up', 1, 'both', 15),      -- item 1: 15 x 4 s           =  60 s
  (1, 2, 'main',    1, 'left', 12),      -- item 2: 12 x 15 s          = 180 s
  (1, 2, 'main',    2, 'right', 12);     -- item 3: 12 x 15 s          = 180 s

-- reorder: swap positions 1 and 2 in one transaction (deferred UNIQUE)
UPDATE plan_item SET position = 2 WHERE id = 2;
UPDATE plan_item SET position = 1 WHERE id = 3;
SET CONSTRAINTS uq_plan_item_position IMMEDIATE;   -- force the check now: must pass
SET CONSTRAINTS uq_plan_item_position DEFERRED;

-- ---------- item duration (one formula, item_duration_sec) ----------
SELECT pg_temp.expect_true('duration: symmetric, both = reps x rep',
  item_duration_sec(15, 4, true, 'both') = 60);
SELECT pg_temp.expect_true('duration: asymmetric, one side = reps x rep',
  item_duration_sec(12, 15, false, 'left') = 180);
SELECT pg_temp.expect_true('duration: asymmetric, both sides in one item = reps x rep x 2',
  item_duration_sec(12, 15, false, 'both') = 360);
SELECT pg_temp.expect_true('v_plan_item: plan 1 lasts 60 + 180 + 180 s, seq follows phase and position',
  (SELECT sum(duration_sec) = 420
          AND array_agg(plan_item_id ORDER BY seq) = ARRAY[1, 3, 2]
     FROM v_plan_item WHERE plan_id = 1));
SELECT pg_temp.expect_fail('reps_count > 0',
  $q$INSERT INTO plan_item (plan_id, exercise_id, phase, position, reps_count) VALUES (1,1,'cool_down',1,0)$q$);
SELECT pg_temp.expect_fail('reps_count is required (no default)',
  $q$INSERT INTO plan_item (plan_id, exercise_id, phase, position) VALUES (1,1,'cool_down',1)$q$);
SELECT pg_temp.expect_fail('rep_duration_sec > 0',
  $q$INSERT INTO exercise (name, mode, starting_pose, difficulty, rep_duration_sec) VALUES ('Zero','dynamic','supine',1,0)$q$);

-- ---------- plan status ----------
SELECT pg_temp.expect_true('new plan starts as draft', (SELECT status = 'draft' FROM plan WHERE id = 1));
SELECT pg_temp.expect_fail('DQ29 new plan must start as draft',
  $q$INSERT INTO plan (coach_id, title, status, target_duration_min) VALUES (1,'X','reviewed',45)$q$);
SELECT pg_temp.expect_fail('DQ29 completed without target duration',
  $q$UPDATE plan SET status = 'completed' WHERE id = 1$q$);
SELECT pg_temp.expect_fail('target duration > 0',
  $q$UPDATE plan SET target_duration_min = 0 WHERE id = 1$q$);
UPDATE plan SET target_duration_min = 45 WHERE id = 1;
SELECT pg_temp.expect_fail('DQ29 draft -> reviewed skips completed',
  $q$UPDATE plan SET status = 'reviewed' WHERE id = 1$q$);
SELECT pg_temp.expect_fail('DQ30 session from a draft plan',
  $q$INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token) VALUES (1,1,'G',now(),repeat('z',43))$q$);
UPDATE plan SET status = 'completed' WHERE id = 1;
SELECT pg_temp.expect_fail('DQ30 session from a completed plan',
  $q$INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token) VALUES (1,1,'G',now(),repeat('z',43))$q$);
UPDATE plan SET status = 'reviewed' WHERE id = 1;
SELECT pg_temp.expect_fail('DQ29 reviewed -> completed',
  $q$UPDATE plan SET status = 'completed' WHERE id = 1$q$);
-- any change of a reviewed plan (no session yet) moves it back to draft ...
UPDATE plan_item SET reps_count = 16 WHERE id = 1;
SELECT pg_temp.expect_true('DQ29 editing an item of a reviewed plan moves it back to draft',
  (SELECT status = 'draft' FROM plan WHERE id = 1));
UPDATE plan SET status = 'completed' WHERE id = 1;
UPDATE plan SET target_duration_min = 50 WHERE id = 1;
SELECT pg_temp.expect_true('DQ29 changing the target duration moves the plan back to draft',
  (SELECT status = 'draft' FROM plan WHERE id = 1));
UPDATE plan SET status = 'completed' WHERE id = 1;
UPDATE plan SET status = 'reviewed'  WHERE id = 1;
UPDATE plan SET title = 'Tuesday stretch (v2)' WHERE id = 1;
SELECT pg_temp.expect_true('DQ29 changing the title moves the plan back to draft',
  (SELECT status = 'draft' FROM plan WHERE id = 1));
UPDATE plan SET status = 'completed' WHERE id = 1;
UPDATE plan SET notes = 'x', status = 'reviewed' WHERE id = 1;
SELECT pg_temp.expect_true('DQ29 a field change wins over a status change in the same statement',
  (SELECT status = 'draft' FROM plan WHERE id = 1));
-- ... and the coach runs the check again
UPDATE plan SET status = 'completed' WHERE id = 1;
UPDATE plan SET status = 'reviewed'  WHERE id = 1;

-- ---------- session flow ----------
-- explicit id: the rejected inserts above have already used identity values
INSERT INTO session (id, coach_id, plan_id, group_name, starts_at, checkin_token) OVERRIDING SYSTEM VALUE
  VALUES (1, 1, 1, 'Tuesday evening', now() + interval '1 hour', repeat('a', 43));
INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1, 'low', true, 'ru');
INSERT INTO checkin_discomfort VALUES (1, 1);
SELECT pg_temp.expect_fail('energy is low / normal / high',
  $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1,'medium',false,'en')$q$);
SELECT pg_temp.expect_fail('energy is not a number any more',
  $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1,3,false,'en')$q$);
SELECT pg_temp.expect_fail('language en/ru',
  $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1,'normal',false,'de')$q$);
SELECT pg_temp.expect_fail('feedback before check-in is closed',
  $q$INSERT INTO feedback (session_id, rating) VALUES (1,4)$q$);

-- ---------- plan lock: any session locks its plan ----------
SELECT pg_temp.expect_true('plan with a session is locked', plan_is_locked(1));
SELECT pg_temp.expect_fail('DQ31 locked plan (open session): add an item',
  $q$INSERT INTO plan_item (plan_id, exercise_id, phase, position, reps_count) VALUES (1,1,'cool_down',1,5)$q$);
SELECT pg_temp.expect_fail('DQ31 locked plan (open session): rename',
  $q$UPDATE plan SET title = 'Renamed' WHERE id = 1$q$);

SELECT pg_temp.expect_fail('DQ05 close without participants_present',
  $q$UPDATE session SET status = 'closed' WHERE id = 1$q$);
UPDATE session SET status = 'closed', participants_present = 1 WHERE id = 1;
SELECT pg_temp.expect_true('close sets checkin_closed_at',
  (SELECT checkin_closed_at IS NOT NULL FROM session WHERE id = 1));

INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, candidate_exercise_id,
                            affected_count, explanation, explanation_source)
  VALUES (1, 2, 10, 'replacement', 3, 1, '1 of 1 reported knee discomfort', 'template');   -- rec 1
INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, is_warning,
                            affected_count, explanation, explanation_source)
  VALUES (1, 3, 11, 'replacement', true, 1, 'Fewer repetitions, smaller amplitude', 'template');  -- rec 2
INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, candidate_exercise_id,
                            affected_count, explanation, explanation_source)
  VALUES (1, 2, 10, 'replacement', 4, 1, 'Another candidate for the same item', 'template');  -- rec 3
INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (1, 'accepted');
SELECT pg_temp.expect_fail('DQ33 second accepted replacement for the same item',
  $q$INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (3, 'accepted')$q$);
INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (3, 'declined');

-- session 'reviewed' needs a decision on every recommendation (warning included)
SELECT pg_temp.expect_fail('DQ04 closed -> done skips reviewed',
  $q$UPDATE session SET status = 'done' WHERE id = 1$q$);
SELECT pg_temp.expect_fail('DQ32 reviewed while a warning is undecided',
  $q$UPDATE session SET status = 'reviewed' WHERE id = 1$q$);
INSERT INTO recommendation_decision (recommendation_id, decision) VALUES (2, 'accepted');
UPDATE session SET status = 'reviewed' WHERE id = 1;
SELECT pg_temp.expect_true('reviewed allowed when every recommendation is decided',
  (SELECT status = 'reviewed' FROM session WHERE id = 1));

-- concrete plan of the session: the accepted replacement swaps the exercise,
-- the blueprint stays as it is
SELECT pg_temp.expect_true('v_session_plan shows the accepted replacement (item 2: exercise 2 -> 3)',
  (SELECT original_exercise_id = 2 AND exercise_id = 3 AND is_replaced
          AND replacement_recommendation_id = 1 AND duration_sec = 12 * 15
     FROM v_session_plan WHERE session_id = 1 AND plan_item_id = 2));
SELECT pg_temp.expect_true('v_session_plan: warning and declined replacement change nothing (item 3)',
  (SELECT exercise_id = 2 AND original_exercise_id = 2 AND NOT is_replaced
          AND replacement_recommendation_id IS NULL
     FROM v_session_plan WHERE session_id = 1 AND plan_item_id = 3));
SELECT pg_temp.expect_true('plan_item is unchanged by the decision',
  (SELECT exercise_id = 2 FROM plan_item WHERE id = 2));

INSERT INTO feedback (session_id, rating, comment) VALUES (1, 5, 'Good');
UPDATE session SET status = 'done', participants_present = 6 WHERE id = 1;
DO $$ BEGIN RAISE NOTICE 'PASS  valid flow completed'; END $$;

-- ---------- plan lock after the class ----------
SELECT pg_temp.expect_fail('DQ31 locked plan: change an item',
  $q$UPDATE plan_item SET reps_count = 6 WHERE id = 2$q$);
SELECT pg_temp.expect_fail('DQ31 locked plan: delete an item',
  $q$DELETE FROM plan_item WHERE id = 1$q$);
SELECT pg_temp.expect_fail('DQ31 locked plan: change the target duration',
  $q$UPDATE plan SET target_duration_min = 60 WHERE id = 1$q$);
SELECT pg_temp.expect_fail('DQ31 locked plan: change the notes',
  $q$UPDATE plan SET notes = 'changed' WHERE id = 1$q$);
SELECT pg_temp.expect_fail('DQ31 locked plan: reopen as draft',
  $q$UPDATE plan SET status = 'draft' WHERE id = 1$q$);

-- duplicate_plan: an editable draft copy with the same items
DO $$
DECLARE v_copy integer;
BEGIN
    v_copy := kinetune.duplicate_plan(1);
    PERFORM pg_temp.expect_true('duplicate_plan: copy is a draft with the same target and items',
        (SELECT p.status = 'draft' AND p.target_duration_min = 50 AND p.title = 'Tuesday stretch (v2) (copy)'
                AND NOT kinetune.plan_is_locked(v_copy)
                AND (SELECT count(*) FROM kinetune.plan_item WHERE plan_id = v_copy) = 3
           FROM kinetune.plan p WHERE p.id = v_copy));
    UPDATE kinetune.plan_item SET reps_count = 8 WHERE plan_id = v_copy AND phase = 'warm_up';
    PERFORM pg_temp.expect_true('duplicate_plan: the copy can be edited, the original is unchanged',
        (SELECT reps_count = 16 FROM kinetune.plan_item WHERE id = 1));
END $$;
DO $$
DECLARE v_copy integer := kinetune.duplicate_plan(1, 'Thursday version');
BEGIN
    PERFORM pg_temp.expect_true('duplicate_plan with an explicit title',
        (SELECT title = 'Thursday version' FROM kinetune.plan WHERE id = v_copy));
END $$;
SELECT pg_temp.expect_fail('duplicate_plan of a missing plan',
  $q$SELECT duplicate_plan(9999)$q$);

-- ---------- rejections: constraints ----------
SELECT pg_temp.expect_fail('email must be lower-case',
  $q$INSERT INTO app_user (email, password_hash, display_name) VALUES ('X@Y.com','h','X')$q$);
SELECT pg_temp.expect_fail('difficulty 1..3',
  $q$INSERT INTO exercise (name, mode, starting_pose, difficulty, rep_duration_sec) VALUES ('Bad','dynamic','supine',4,4)$q$);
SELECT pg_temp.expect_fail('starting pose: lying is no longer a value',
  $q$INSERT INTO exercise (name, mode, starting_pose, difficulty, rep_duration_sec) VALUES ('Old pose','dynamic','lying',1,4)$q$);
SELECT pg_temp.expect_true('starting pose: all nine library values are accepted',
  (SELECT array_agg(v::text ORDER BY v::text) = ARRAY['balance','downward_dog','front_split','kneeling','prone',
                                                 'quadruped','seated','standing','supine']
     FROM unnest(enum_range(NULL::starting_pose)) v));
SELECT pg_temp.expect_fail('joint load level is required',
  $q$INSERT INTO exercise_joint (exercise_id, joint_id, is_primary) VALUES (4,1,true)$q$);
SELECT pg_temp.expect_fail('compensation not self',
  $q$INSERT INTO exercise_compensation VALUES (3,3)$q$);
SELECT pg_temp.expect_fail('compensation pair stored once',
  $q$INSERT INTO exercise_compensation VALUES (2,1)$q$);
SELECT pg_temp.expect_fail('compensating exercise in use cannot be deleted (RESTRICT)',
  $q$DELETE FROM exercise WHERE id = 5$q$);
SELECT pg_temp.expect_fail('family name unique',
  $q$INSERT INTO exercise_family (name) VALUES ('spine mobility')$q$);
SELECT pg_temp.expect_fail('family name not blank',
  $q$INSERT INTO exercise_family (name) VALUES ('  ')$q$);
SELECT pg_temp.expect_fail('family with members cannot be deleted (RESTRICT)',
  $q$DELETE FROM exercise_family WHERE name = 'spine mobility'$q$);
SELECT pg_temp.expect_fail('relation not self',
  $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id) VALUES (1,1)$q$);
SELECT pg_temp.expect_fail('variation edges cannot be stored (relation_type = progression only)',
  $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, type) VALUES (1,5,'variation')$q$);
SELECT pg_temp.expect_fail('DQ36 no progressions in both directions (2 -> 3 next to 3 -> 2)',
  $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id) VALUES (2,3)$q$);
SELECT pg_temp.expect_fail('DQ36 no reverse of a manual progression (4 -> 3 next to 3 -> 4)',
  $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id) VALUES (4,3)$q$);
SELECT pg_temp.expect_fail('DQ36 the same progression twice',
  $q$INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, is_manual) VALUES (3,2,true)$q$);
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
  $q$INSERT INTO checkin (session_id, energy, poor_sleep, language) VALUES (1,'normal',false,'en')$q$);
SELECT pg_temp.expect_fail('DQ04 status backwards',
  $q$UPDATE session SET status = 'open' WHERE id = 1$q$);
SELECT pg_temp.expect_fail('DQ21 plan owner must be coach',
  $q$INSERT INTO plan (coach_id, title) VALUES (2,'Admin plan')$q$);
-- a draft plan without sessions for the item-level tests
INSERT INTO plan (coach_id, title) VALUES (1, 'Scratch plan');
INSERT INTO plan_item (plan_id, exercise_id, phase, position, reps_count)
  SELECT id, 1, 'warm_up', 1, 10 FROM plan WHERE title = 'Scratch plan';
INSERT INTO plan_item (plan_id, exercise_id, phase, position, reps_count)
  SELECT id, 1, 'warm_up', 2, 10 FROM plan WHERE title = 'Scratch plan';
SELECT pg_temp.expect_fail('DQ25 symmetric exercise needs side both',
  $q$INSERT INTO plan_item (plan_id, exercise_id, phase, position, side, reps_count) SELECT id,1,'cool_down',1,'left',5 FROM plan WHERE title = 'Scratch plan'$q$);
SELECT pg_temp.expect_fail('DQ02 candidate differs from original',
  $q$INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, candidate_exercise_id, affected_count, explanation, explanation_source) VALUES (1,2,9,'alternative',2,1,'x','template')$q$);
SELECT pg_temp.expect_fail('DQ22 last admin cannot be removed',
  $q$DELETE FROM user_role WHERE user_id = 2$q$);
SELECT pg_temp.expect_fail('DQ22 last admin cannot be deactivated',
  $q$UPDATE app_user SET is_active = false WHERE id = 2$q$);
SELECT pg_temp.expect_fail('DQ23 only admin grants roles',
  $q$INSERT INTO user_role (user_id, role_id, granted_by) SELECT 2, id, 1 FROM role WHERE code = 'coach'$q$);

-- DQ01: second plan + session; recommendation pointing at another plan's item
INSERT INTO plan (coach_id, title, target_duration_min) VALUES (1, 'Other plan', 30);
UPDATE plan SET status = 'completed' WHERE title = 'Other plan';
UPDATE plan SET status = 'reviewed'  WHERE title = 'Other plan';
INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token)
  SELECT 1, id, 'Thursday', now(), repeat('c', 43) FROM plan WHERE title = 'Other plan';
UPDATE session SET status = 'closed', participants_present = 0 WHERE group_name = 'Thursday';
SELECT pg_temp.expect_fail('DQ01 plan item from another plan',
  $q$INSERT INTO recommendation (session_id, plan_item_id, rule_id, form, candidate_exercise_id, affected_count, explanation, explanation_source) SELECT id,2,9,'alternative',3,1,'x','template' FROM session WHERE group_name = 'Thursday'$q$);
SELECT pg_temp.expect_fail('DQ05 participants_present cannot be removed after close',
  $q$UPDATE session SET participants_present = NULL WHERE group_name = 'Thursday'$q$);
UPDATE session SET status = 'reviewed' WHERE group_name = 'Thursday';
SELECT pg_temp.expect_true('reviewed allowed at once for a session without recommendations',
  (SELECT status = 'reviewed' FROM session WHERE group_name = 'Thursday'));
-- make user 2 a coach too, so the next test fails on ownership, not on the role
INSERT INTO user_role (user_id, role_id) SELECT 2, id FROM role WHERE code = 'coach';
SELECT pg_temp.expect_fail('DQ08 session plan must belong to its coach',
  $q$INSERT INTO session (coach_id, plan_id, group_name, starts_at, checkin_token) SELECT 2, id, 'X', now(), repeat('d',43) FROM plan WHERE title = 'Other plan'$q$);

-- deferred UNIQUE: a real duplicate must fail at commit time
SELECT pg_temp.expect_fail('duplicate position fails at constraint check',
  $q$UPDATE plan_item SET position = 1 WHERE plan_id = (SELECT id FROM plan WHERE title = 'Scratch plan') AND position = 2; SET CONSTRAINTS uq_plan_item_position IMMEDIATE$q$);

-- cascade: deleting a session removes its participant data
DELETE FROM session WHERE id = 1;
SELECT pg_temp.expect_true('deleting a session cascades to its data',
  NOT EXISTS (SELECT 1 FROM checkin) AND NOT EXISTS (SELECT 1 FROM recommendation)
  AND NOT EXISTS (SELECT 1 FROM feedback));
-- cascade: deleting an exercise removes its family and compensation rows
DELETE FROM exercise_compensation WHERE compensation_exercise_id = 5;
DELETE FROM exercise WHERE id = 5;
SELECT pg_temp.expect_true('deleting an exercise cascades to its family membership',
  NOT EXISTS (SELECT 1 FROM exercise_family_member WHERE exercise_id = 5));

ROLLBACK;

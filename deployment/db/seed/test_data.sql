-- =====================================================================
-- Kinetune — TEST DATA (development, demo and tests only; never production)
--
--   docker compose --profile test run --rm seed-test
--   or: psql -v ON_ERROR_STOP=1 --single-transaction -f db/seed/test_data.sql
--
-- Requires migrations 0001–0004 (reference data comes from 0002).
-- Loads only into a database without users (guard below).
-- The exercise library here is a DEMO library made for testing; the real
-- library (30–50 exercises) is compiled by the author (thesis, C3).
-- All test accounts share the password  Test-Only-2026!  (argon2id-hashed).
--
-- Each numbered block below is labelled with what it demonstrates.
-- Ids are explicit (OVERRIDING SYSTEM VALUE) so tests can refer to them;
-- sequences are moved past them at the end.
-- Body areas: 1 neck, 2 shoulders, 3 wrists, 4 lower_back, 5 hips, 6 knees
-- Rules: 9 = BR9 alternative, 10 = BR10 replacement, 11 = BR11 warning
-- =====================================================================

SET search_path TO kinetune;

-- All timestamps are relative to the day the data is loaded, so that
-- 'done' sessions are in the past and 'open' ones in the future:
-- pg_temp.t(-14, '17:00') = 14 days ago at 17:00 UTC.
CREATE FUNCTION pg_temp.t(p_days integer, p_time text) RETURNS timestamptz
LANGUAGE sql STABLE AS $$
    SELECT (date_trunc('day', now() AT TIME ZONE 'UTC') + p_days * interval '1 day' + p_time::interval) AT TIME ZONE 'UTC'
$$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM app_user) THEN
        RAISE EXCEPTION 'Test data can be loaded only into a database without users';
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 1. Accounts: admin, two coaches, one coach deactivated later
-- ---------------------------------------------------------------------
INSERT INTO app_user (id, email, password_hash, display_name) OVERRIDING SYSTEM VALUE VALUES
  (1, 'admin@kinetune.test',        '$argon2id$v=19$m=65536,t=3,p=4$ijGjM2XusNzizEHNbAb0uw$VSXuYAG0q8co/44+hZwTIu1eTRasx2DvCMM+I6ins2k', 'Admin'),
  (2, 'laura@kinetune.test',        '$argon2id$v=19$m=65536,t=3,p=4$0oAP0hoO+vZ7qa1ZTY8NlA$Tye9OhNS9h6ymTee0Tc3UBu0G5YCYO6Qh8WH2hISbrg', 'Laura (demo coach)'),
  (3, 'coach2@kinetune.test',       '$argon2id$v=19$m=65536,t=3,p=4$bildVAAr1HJacKs2NDMDgg$HT+IWh6zY+6cL+Xj4u41jvmROT8dDjDidwKIweI8KeE', 'Second coach'),
  (4, 'former.coach@kinetune.test', '$argon2id$v=19$m=65536,t=3,p=4$rxr82lneHqYc7gQd+hAe6A$ub7z5psxc2uAWpziC4EuHN6IPrilgsFNMIcgKUUFb+A', 'Former coach');

INSERT INTO user_role (user_id, role_id, granted_by) VALUES (1, 2, NULL);   -- bootstrap admin
INSERT INTO user_role (user_id, role_id, granted_by) VALUES
  (2, 1, 1), (3, 1, 1), (4, 1, 1);                                        -- coaches, granted by the admin

-- ---------------------------------------------------------------------
-- 2. Demo exercise library (29 exercises, one inactive)
-- ---------------------------------------------------------------------
INSERT INTO exercise (id, name, description, mode, starting_pose, is_symmetric, difficulty, default_duration_sec, is_active)
OVERRIDING SYSTEM VALUE VALUES
  -- warm-up (dynamic)
  ( 1, 'Neck rolls',                     'Slow half circles of the head',             'dynamic',       'seated',   true,  1, 120, true),
  ( 2, 'Shoulder circles',               'Forward and backward circles',              'dynamic',       'standing', true,  1, 120, true),
  ( 3, 'Wrist circles',                  'Circles with interlaced fingers',           'dynamic',       'seated',   true,  1,  90, true),
  ( 4, 'Pelvic tilts',                   'Lying on the back, knees bent',             'dynamic',       'lying',    true,  1, 120, true),
  ( 5, 'Leg swings',                     'Front-to-back swings on one leg',           'dynamic',       'balance',  false, 1, 120, true),
  ( 6, 'Hip circles',                    'Hands on hips, wide circles',               'dynamic',       'standing', true,  1, 120, true),
  ( 7, 'Torso twists',                   'Standing rotations, arms loose',            'dynamic',       'standing', true,  1, 120, true),
  ( 8, 'Knee lifts',                     'Marching on the spot, knees high',          'dynamic',       'standing', true,  1, 120, true),
  -- main part
  ( 9, 'Standing forward fold',          'Fold with a gentle sway',                   'stato_dynamic', 'standing', true,  2, 240, true),
  (10, 'Seated forward fold',            'Legs straight, reach for the feet',         'static',        'seated',   true,  1, 240, true),
  (11, 'Deep lunge',                     'Hip flexor stretch with small pulses',      'stato_dynamic', 'standing', false, 2, 180, true),
  (12, 'Sphinx back extension',          'Lying on the stomach, lift the chest',      'stato_dynamic', 'lying',    true,  1, 180, true),
  (13, 'Lying hip flexor stretch',       'Lying at the edge of a mat, one leg down',  'static',        'lying',    false, 1, 180, true),
  (14, 'Standing quad stretch',          'Heel to glute, standing on one leg',        'static',        'balance',  false, 2, 150, true),
  (15, 'Side-lying quad stretch',        'Heel to glute, lying on the side',          'static',        'lying',    false, 1, 150, true),
  (16, 'Pigeon pose',                    'Front shin across the mat',                 'static',        'lying',    false, 3, 180, true),
  (17, 'Figure-four stretch',            'Lying, ankle over the opposite knee',       'static',        'lying',    false, 1, 180, true),
  (18, 'Doorway chest stretch',          'Forearm on a door frame, step through',     'static',        'standing', false, 1, 150, true),
  (19, 'Cross-body arm swings',          'Arms swing across the chest',               'dynamic',       'standing', false, 1, 120, true),
  (20, 'Kneeling wrist stretch',         'Palms on the floor, fingers to the knees',  'static',        'seated',   true,  2, 120, true),
  (21, 'Wall wrist stretch',             'Palm against a wall, fingers down',         'static',        'standing', false, 1, 120, true),
  (22, 'Tree pose',                      'Foot on the inner thigh, arms up',          'static',        'balance',  false, 2, 120, true),
  (23, 'Butterfly stretch',              'Soles together, gentle knee flutters',      'stato_dynamic', 'seated',   true,  1, 180, true),
  (24, 'Seated spinal twist',            'Cross-legged rotation with breathing',      'stato_dynamic', 'seated',   false, 1, 150, true),
  -- cool-down
  (25, 'Child''s pose',                  'Kneeling, forehead to the floor',           'static',        'seated',   true,  1, 240, true),
  (26, 'Knees to chest',                 'Lying on the back, hug the knees',          'static',        'lying',    true,  1, 240, true),
  (27, 'Legs up the wall',               'Lying, legs resting on a wall',             'static',        'lying',    true,  1, 300, true),
  -- inactive (kept because an old plan uses it)
  (28, 'Ballistic toe touches',          'Bouncing toe touches (no longer used)',     'dynamic',       'standing', true,  2, 120, false),
  -- high difficulty
  (29, 'Front split',                    'Full split, front leg straight',            'static',        'seated',   false, 3, 180, true);

-- compensation (BR6): forward folds must be followed by a back extension
UPDATE exercise SET required_compensation_id = 12 WHERE id IN (9, 10);

INSERT INTO exercise_muscle (exercise_id, muscle_id, is_primary) VALUES
  (1,1,true),(1,2,true),   (2,4,true),(2,7,false),   (3,8,true),(3,9,true),
  (4,10,true),(4,11,false),(5,14,true),(5,18,false), (6,13,true),(6,16,false),
  (7,11,true),(7,10,false),(8,14,true),(8,12,false), (9,18,true),(9,10,false),
  (10,18,true),(10,10,false),(11,14,true),(11,17,false),(12,10,true),(12,11,false),
  (13,14,true),(14,17,true),(15,17,true),(16,16,true),(16,12,true),(17,16,true),(17,12,false),
  (18,5,true),(18,4,false),(19,4,true),(19,7,false),(20,8,true),(21,8,true),
  (22,13,true),(22,15,false),(23,15,true),(24,11,true),(24,12,false),
  (25,10,true),(25,6,false),(26,10,true),(26,12,false),(27,18,true),(27,19,false),
  (28,18,true),(29,18,true),(29,14,true);

-- is_primary = the joint carries the main (medium/high) load
INSERT INTO exercise_joint (exercise_id, joint_id, is_primary) VALUES
  (1,1,true),(2,2,true),(3,3,true),(4,4,true),(5,5,true),(5,6,false),(6,5,true),(7,4,true),
  (8,5,true),(8,6,false),(9,4,true),(9,5,false),(10,5,true),(11,5,true),(11,6,true),
  (12,4,true),(13,5,true),(13,6,false),(14,6,true),(15,6,false),(16,5,true),(16,6,true),
  (17,5,true),(18,2,true),(19,2,true),(20,3,true),(20,6,false),(21,3,false),(22,5,true),(22,6,false),
  (23,5,true),(24,4,true),(25,6,true),(25,4,false),(26,4,true),(27,5,false),(28,4,true),
  (29,5,true),(29,6,false);

-- graph: undirected variations (stored once, smaller id first) and directed progressions
INSERT INTO exercise_relation (from_exercise_id, to_exercise_id, type, is_directed) VALUES
  ( 5,  8, 'variation',   false),   -- leg swings ~ knee lifts (knee lifts: no balance)
  (18, 19, 'variation',   false),
  (22, 23, 'variation',   false),   -- tree pose ~ butterfly (butterfly: no balance)
  (25, 26, 'variation',   false),   -- child's pose ~ knees to chest (less knee load)
  (13, 11, 'progression', true),    -- lying hip flexor -> deep lunge (harder)
  (11, 29, 'progression', true),    -- deep lunge -> front split
  (17, 16, 'progression', true),    -- figure-four -> pigeon
  (15, 14, 'progression', true),    -- side-lying quad -> standing quad
  (10,  9, 'progression', true),    -- seated fold -> standing fold
  (21, 20, 'progression', true);    -- wall wrist -> kneeling wrist

-- ---------------------------------------------------------------------
-- 3. Plans
-- ---------------------------------------------------------------------
INSERT INTO plan (id, coach_id, title, notes) OVERRIDING SYSTEM VALUE VALUES
  (1, 2, 'Tuesday evening: full body',   'Passes BR1–BR8 (45-min class)'),
  (2, 2, 'Hips and lower back',          'Deliberately breaks BR5 (static share) and BR6 (compensation too far)'),
  (3, 2, 'Upper body and wrists',        'Deliberately breaks BR5'),
  (4, 4, 'Old plan (archived)',          'Uses an inactive exercise; owner deactivated'),
  (5, 3, 'Morning stretch',              'Plan of the second coach');

INSERT INTO plan_item (id, plan_id, exercise_id, phase, position, duration_sec, side, reps_count)
OVERRIDING SYSTEM VALUE VALUES
  -- plan 1
  (101,1, 1,'warm_up',  1,120,'both', 10),
  (102,1, 2,'warm_up',  2,120,'both', 10),
  (103,1, 5,'warm_up',  3,120,'left', 10),   -- balance exercise in the first quarter (BR9)
  (104,1, 5,'warm_up',  4,120,'right',10),
  (105,1, 8,'warm_up',  5,120,'both', 20),
  (106,1, 9,'main',     1,240,'both', NULL), -- needs compensation 12 (position 6: 5 later, OK)
  (107,1,11,'main',     2,180,'left', NULL),
  (108,1,11,'main',     3,180,'right',NULL),
  (109,1,14,'main',     4,150,'left', NULL),
  (110,1,14,'main',     5,150,'right',NULL),
  (111,1,12,'main',     6,180,'both', 8),
  (112,1,19,'main',     7,120,'left', NULL),
  (113,1,19,'main',     8,120,'right',NULL),
  (114,1,25,'cool_down',1,240,'both', NULL),
  (115,1,27,'cool_down',2,300,'both', NULL),
  -- plan 2
  (201,2, 4,'warm_up',  1,120,'both', 12),
  (202,2, 6,'warm_up',  2,120,'both', 10),
  (203,2, 7,'warm_up',  3,120,'both', 10),
  (204,2,10,'main',     1,240,'both', NULL), -- compensation 12 is 6 exercises later (BR6 warning)
  (205,2,16,'main',     2,180,'left', NULL),
  (206,2,16,'main',     3,180,'right',NULL),
  (207,2,23,'main',     4,180,'both', NULL),
  (208,2,24,'main',     5,150,'left', NULL),
  (209,2,24,'main',     6,150,'right',NULL),
  (210,2,12,'main',     7,180,'both', 8),
  (211,2,26,'cool_down',1,240,'both', NULL),
  (212,2,27,'cool_down',2,300,'both', NULL),
  -- plan 3
  (301,3, 1,'warm_up',  1,120,'both', 10),
  (302,3, 2,'warm_up',  2,120,'both', 10),
  (303,3, 3,'warm_up',  3, 90,'both', 15),
  (304,3,18,'main',     1,150,'left', NULL),
  (305,3,18,'main',     2,150,'right',NULL),
  (306,3,20,'main',     3,120,'both', NULL),
  (307,3,19,'main',     4,120,'left', NULL),
  (308,3,19,'main',     5,120,'right',NULL),
  (309,3,22,'main',     6,120,'left', NULL), -- balance, but not in the first quarter
  (310,3,22,'main',     7,120,'right',NULL),
  (311,3,25,'cool_down',1,240,'both', NULL),
  -- plan 4 (archived)
  (401,4,28,'warm_up',  1,120,'both', 10),   -- inactive exercise
  (402,4, 9,'main',     1,240,'both', NULL),
  (403,4,27,'cool_down',1,300,'both', NULL),
  -- plan 5 (second coach)
  (501,5, 2,'warm_up',  1,120,'both', 10),
  (502,5, 6,'warm_up',  2,120,'both', 10),
  (503,5,13,'main',     1,180,'left', NULL),
  (504,5,13,'main',     2,180,'right',NULL),
  (505,5,24,'main',     3,150,'left', NULL),
  (506,5,24,'main',     4,150,'right',NULL),
  (507,5,19,'main',     5,120,'left', NULL),
  (508,5,19,'main',     6,120,'right',NULL),
  (509,5,12,'main',     7,180,'both', 8),
  (510,5,26,'cool_down',1,240,'both', NULL);

-- ---------------------------------------------------------------------
-- 4. Sessions. Each starts 'open' (trigger), receives check-ins, is closed,
--    gets recommendations and feedback, and is marked 'done' with attendance.
--    checkin_closed_at is then set to a realistic time for the history.
-- ---------------------------------------------------------------------
INSERT INTO session (id, coach_id, plan_id, group_name, starts_at, checkin_token) OVERRIDING SYSTEM VALUE VALUES
  (1, 2, 1, 'Tuesday evening',       pg_temp.t(-14, '17:00'), rpad('test_session_01_', 43, 'x')),
  (2, 2, 2, 'Thursday evening',      pg_temp.t(-12, '17:00'), rpad('test_session_02_', 43, 'x')),
  (3, 2, 2, 'Thursday evening',      pg_temp.t(-9, '17:00'), rpad('test_session_03_', 43, 'x')),
  (4, 2, 1, 'Tuesday evening',       pg_temp.t(-7, '17:00'), rpad('test_session_04_', 43, 'x')),
  (5, 2, 3, 'Wednesday small group', pg_temp.t(-2, '16:00'), rpad('test_session_05_', 43, 'x')),
  (6, 2, 1, 'Tuesday evening',       pg_temp.t(5, '17:00'), rpad('test_session_06_', 43, 'x')),
  (7, 3, 5, 'Morning group',         pg_temp.t(7, '07:00'), rpad('test_session_07_', 43, 'x')),
  (8, 4, 4, 'Old Monday group',      pg_temp.t(-42, '17:00'), rpad('test_session_08_', 43, 'x'));

-- check-ins (energy 1–5: 1–2 = low; anonymous; EN/RU)
INSERT INTO checkin (id, session_id, energy, poor_sleep, language, submitted_at) OVERRIDING SYSTEM VALUE VALUES
  -- S1: 6 check-ins, 7 present
  (101,1,2,true, 'en',pg_temp.t(-14, '16:05')),
  (102,1,3,false,'ru',pg_temp.t(-14, '16:12')),
  (103,1,4,false,'en',pg_temp.t(-14, '16:20')),
  (104,1,3,false,'ru',pg_temp.t(-14, '16:31')),
  (105,1,1,true, 'en',pg_temp.t(-14, '16:38')),
  (106,1,4,false,'en',pg_temp.t(-14, '16:44')),
  -- S2: none
  -- S3: 5 check-ins, only 4 present (someone checked in and did not come)
  (301,3,3,false,'en',pg_temp.t(-9, '16:10')),
  (302,3,2,true, 'ru',pg_temp.t(-9, '16:15')),
  (303,3,4,false,'en',pg_temp.t(-9, '16:22')),
  (304,3,3,false,'ru',pg_temp.t(-9, '16:30')),
  (305,3,5,false,'en',pg_temp.t(-9, '16:41')),
  -- S4: 4 check-ins, attendance not entered yet
  (401,4,3,false,'en',pg_temp.t(-7, '16:08')),
  (402,4,4,false,'ru',pg_temp.t(-7, '16:19')),
  (403,4,2,false,'en',pg_temp.t(-7, '16:27')),
  (404,4,5,false,'en',pg_temp.t(-7, '16:35')),
  -- S5: 2 check-ins
  (501,5,3,false,'en',pg_temp.t(-2, '15:20')),
  (502,5,1,true, 'ru',pg_temp.t(-2, '15:31')),
  -- S6: open, 2 check-ins so far
  (601,6,4,false,'en',pg_temp.t(5, '16:02')),
  (602,6,2,true, 'ru',pg_temp.t(5, '16:09')),
  -- S8: historical, no discomfort
  (801,8,4,false,'en',pg_temp.t(-42, '16:10')),
  (802,8,3,false,'en',pg_temp.t(-42, '16:20')),
  (803,8,5,false,'ru',pg_temp.t(-42, '16:30'));

INSERT INTO checkin_discomfort (checkin_id, body_area_id) VALUES
  (101,6),(102,6),(104,4),(106,6),(106,5),          -- S1: knees 3, lower back 1, hips 1
  (301,5),(302,5),(302,4),(303,5),(304,4),          -- S3: hips 3, lower back 2
  (401,6),(403,6),                                  -- S4: knees 2 of 4 = exactly 50 %
  (501,3),                                          -- S5: wrists 1 of 2 = 50 %, but one person
  (602,1);                                          -- S6: neck

-- close the check-in (trigger sets checkin_closed_at = now(); corrected below)
UPDATE session SET status = 'closed' WHERE id IN (1, 2, 3, 4, 5, 8);
UPDATE session SET checkin_closed_at = starts_at - interval '10 minutes' WHERE id IN (1, 2, 3, 4, 5, 8);

-- ---------------------------------------------------------------------
-- 5. Recommendations (representative examples of the engine's output)
-- ---------------------------------------------------------------------
INSERT INTO recommendation (id, session_id, plan_item_id, rule_id, form, is_warning, candidate_exercise_id,
                            affected_count, explanation, explanation_source, created_at)
OVERRIDING SYSTEM VALUE VALUES
  -- S1: 3 of 7 report knees (< 50 %) -> BR9 alternatives
  ( 1,1,107, 9,'alternative',false,13,3,'Three of seven participants mentioned knee discomfort. The lying hip flexor stretch targets the same hip flexors with the knee resting on the mat, so offer it next to the deep lunge.','llm',     pg_temp.t(-14, '16:50:05')),
  ( 2,1,108, 9,'alternative',false,13,3,'3 of 7 participants reported discomfort in the knees. "Lying hip flexor stretch" is offered next to "Deep lunge" for those who need it.','template',pg_temp.t(-14, '16:50:05')),
  ( 3,1,109, 9,'alternative',false,15,3,'3 of 7 participants reported discomfort in the knees. "Side-lying quad stretch" is offered next to "Standing quad stretch" for those who need it.','template',pg_temp.t(-14, '16:50:05')),
  ( 4,1,110, 9,'alternative',false,15,3,'3 of 7 participants reported discomfort in the knees. "Side-lying quad stretch" is offered next to "Standing quad stretch" for those who need it.','template',pg_temp.t(-14, '16:50:05')),
  -- S1: 2 of 7 low energy / poor sleep, balance exercise in the first quarter -> BR9
  ( 5,1,103, 9,'alternative',false, 8,2,'2 of 7 participants reported low energy or poor sleep. "Knee lifts" is offered next to "Leg swings" for those who need it.','template',pg_temp.t(-14, '16:50:05')),
  -- S1: 1 of 7 lower back -> BR9 (candidate via a regression edge)
  ( 6,1,106, 9,'alternative',false,10,1,'One participant mentioned lower-back discomfort. The seated forward fold stretches the same hamstrings with less load on the lower back.','llm',pg_temp.t(-14, '16:50:05')),
  ( 7,1,114, 9,'alternative',false,26,3,'3 of 7 participants reported discomfort in the knees. "Knees to chest" is offered next to "Child''s pose" for those who need it.','template',pg_temp.t(-14, '16:50:05')),
  -- S3: 3 of 4 present report hips (>= 50 % and >= 2) -> BR10 replacements
  ( 8,3,205,10,'replacement',false,17,3,'Three of the four participants reported hip discomfort. The figure-four stretch works the same piriformis and glutes lying on the back, with much less load on the hip and knee.','llm',pg_temp.t(-9, '16:50:04')),
  ( 9,3,206,10,'replacement',false,17,3,'3 of 4 participants reported discomfort in the hips. Replacing "Pigeon pose" with "Figure-four stretch" for the whole group is suggested.','template',pg_temp.t(-9, '16:50:04')),
  -- S3: 2 of 4 lower back (exactly 50 %, 2 people) -> BR10, but no substitute -> BR11 warning
  (10,3,208,11,'replacement',true, NULL,2,'No suitable substitute for "Seated spinal twist" was found. Consider fewer repetitions, a smaller amplitude or a slower pace.','template',pg_temp.t(-9, '16:50:04')),
  (11,3,209,11,'replacement',true, NULL,2,'No suitable substitute for "Seated spinal twist" was found. Consider fewer repetitions, a smaller amplitude or a slower pace.','template',pg_temp.t(-9, '16:50:04')),
  -- S4: 2 of 4 check-ins (attendance unknown -> base = check-ins) = 50 %, 2 people -> BR10, not decided yet
  (12,4,107,10,'replacement',false,13,2,'2 of 4 participants reported discomfort in the knees. Replacing "Deep lunge" with "Lying hip flexor stretch" for the whole group is suggested.','template',pg_temp.t(-7, '16:50:03')),
  (13,4,108,10,'replacement',false,13,2,'2 of 4 participants reported discomfort in the knees. Replacing "Deep lunge" with "Lying hip flexor stretch" for the whole group is suggested.','template',pg_temp.t(-7, '16:50:03')),
  -- S5: 1 of 2 = 50 % but only ONE person -> BR9 alternative, not BR10
  (14,5,306, 9,'alternative',false,21,1,'One participant mentioned wrist discomfort. The wall wrist stretch keeps the same stretch without body weight on the hands.','llm',pg_temp.t(-2, '15:50:02')),
  -- S5: wrist circles have no related exercise -> BR11 warning
  (15,5,303,11,'alternative',true, NULL,1,'No suitable substitute for "Wrist circles" was found. Consider fewer repetitions, a smaller amplitude or a slower pace.','template',pg_temp.t(-2, '15:50:02'));

-- decisions (missing row = not decided yet: recommendations 4, 12, 13, 15)
INSERT INTO recommendation_decision (recommendation_id, decision, decided_at) VALUES
  ( 1,'accepted',pg_temp.t(-14, '16:53')),
  ( 2,'accepted',pg_temp.t(-14, '16:53')),
  ( 3,'declined',pg_temp.t(-14, '16:54')),
  ( 5,'accepted',pg_temp.t(-14, '16:54')),
  ( 6,'accepted',pg_temp.t(-14, '16:55')),
  ( 7,'declined',pg_temp.t(-14, '16:55')),
  ( 8,'accepted',pg_temp.t(-9, '16:52')),
  ( 9,'accepted',pg_temp.t(-9, '16:52')),
  (10,'accepted',pg_temp.t(-9, '16:53')),
  (11,'declined',pg_temp.t(-9, '16:53')),
  (14,'accepted',pg_temp.t(-2, '15:51'));

-- ---------------------------------------------------------------------
-- 6. Feedback (after the check-in is closed; voluntary)
-- ---------------------------------------------------------------------
INSERT INTO feedback (session_id, rating, comment, submitted_at) VALUES
  (1,5,'The lunge alternative really helped my knee', pg_temp.t(-14, '18:20')),
  (1,4,NULL,                                           pg_temp.t(-14, '18:31')),
  (1,5,'Спасибо, было очень комфортно',                pg_temp.t(-14, '18:47')),
  (1,3,'A bit too fast at the end',                    pg_temp.t(-14, '19:02')),
  (3,4,NULL,                                           pg_temp.t(-9, '18:25')),
  (4,5,NULL,                                           pg_temp.t(-7, '18:15')),
  (4,4,'Nice pace',                                    pg_temp.t(-7, '18:40'));

-- ---------------------------------------------------------------------
-- 7. Attendance -> 'done'; S4 and S5 stay 'closed', S6 and S7 stay 'open'
-- ---------------------------------------------------------------------
UPDATE session SET status = 'done', participants_present = 7 WHERE id = 1;
UPDATE session SET status = 'done', participants_present = 5 WHERE id = 2;  -- 0 check-ins
UPDATE session SET status = 'done', participants_present = 4 WHERE id = 3;  -- fewer present than check-ins
UPDATE session SET status = 'done', participants_present = 6 WHERE id = 8;

-- the former coach leaves: account deactivated, history kept
UPDATE app_user SET is_active = false WHERE id = 4;
UPDATE app_user SET last_login_at = pg_temp.t(-2, '15:45') WHERE id = 2;
UPDATE app_user SET last_login_at = pg_temp.t(-1, '08:00') WHERE id = 1;

-- ---------------------------------------------------------------------
-- 8. Move identity sequences past the explicit ids
-- ---------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('kinetune.app_user',       'id'), (SELECT max(id) FROM app_user));
SELECT setval(pg_get_serial_sequence('kinetune.exercise',       'id'), (SELECT max(id) FROM exercise));
SELECT setval(pg_get_serial_sequence('kinetune.plan',           'id'), (SELECT max(id) FROM plan));
SELECT setval(pg_get_serial_sequence('kinetune.plan_item',      'id'), (SELECT max(id) FROM plan_item));
SELECT setval(pg_get_serial_sequence('kinetune.session',        'id'), (SELECT max(id) FROM session));
SELECT setval(pg_get_serial_sequence('kinetune.checkin',        'id'), (SELECT max(id) FROM checkin));
SELECT setval(pg_get_serial_sequence('kinetune.recommendation', 'id'), (SELECT max(id) FROM recommendation));

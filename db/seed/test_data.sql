-- =====================================================================
-- Kinetune — TEST DATA (development, demo and tests only; never production)
--
--   docker compose --profile test run --rm seed-test
--   or: psql -v ON_ERROR_STOP=1 --single-transaction -f db/seed/test_data.sql
--
-- Run order: migrations (0001–0004) -> library import -> this file.
-- Built ON TOP OF THE IMPORTED LIBRARY: exercises are referenced by name
-- (pg_temp.ex), never by id, so the file works with any import.
-- Loads only into a database without users (guard below).
-- All test accounts share the password  Test-Only-2026!  (argon2id-hashed).
--
-- Contents and the edge cases each block demonstrates:
-- docs/database/test_data.md §2. Ids of plans, items, sessions and
-- recommendations are explicit (OVERRIDING SYSTEM VALUE) so the docs can
-- refer to them; sequences are moved past them at the end.
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

-- Exercise id by name; stops the seed if the library does not have it.
CREATE FUNCTION pg_temp.ex(p_name text) RETURNS integer
LANGUAGE plpgsql STABLE AS $$
DECLARE v_id integer;
BEGIN
    SELECT id INTO v_id FROM kinetune.exercise WHERE name = p_name;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'Exercise "%" is not in the library; the test data expects the library of db/library/', p_name;
    END IF;
    RETURN v_id;
END $$;

-- Body area id by code.
CREATE FUNCTION pg_temp.area(p_code text) RETURNS smallint
LANGUAGE sql STABLE AS $$ SELECT id FROM kinetune.body_area WHERE code = p_code $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM app_user) THEN
        RAISE EXCEPTION 'Test data can be loaded only into a database without users';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM exercise) THEN
        RAISE EXCEPTION 'The exercise library is empty: run the library import first (docker compose --profile import run --rm import-library)';
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 1. Accounts: one admin, two coaches (the second one is deactivated at
--    the end, after its history was created)
-- ---------------------------------------------------------------------
INSERT INTO app_user (id, email, password_hash, display_name) OVERRIDING SYSTEM VALUE VALUES
  (1, 'admin@kinetune.test',        '$argon2id$v=19$m=65536,t=3,p=4$ijGjM2XusNzizEHNbAb0uw$VSXuYAG0q8co/44+hZwTIu1eTRasx2DvCMM+I6ins2k', 'Admin'),
  (2, 'laura@kinetune.test',        '$argon2id$v=19$m=65536,t=3,p=4$0oAP0hoO+vZ7qa1ZTY8NlA$Tye9OhNS9h6ymTee0Tc3UBu0G5YCYO6Qh8WH2hISbrg', 'Laura (demo coach)'),
  (3, 'former.coach@kinetune.test', '$argon2id$v=19$m=65536,t=3,p=4$rxr82lneHqYc7gQd+hAe6A$ub7z5psxc2uAWpziC4EuHN6IPrilgsFNMIcgKUUFb+A', 'Former coach');

INSERT INTO user_role (user_id, role_id, granted_by)
  SELECT 1, id, NULL FROM role WHERE code = 'admin';            -- bootstrap admin
INSERT INTO user_role (user_id, role_id, granted_by)
  SELECT u, id, 1 FROM role, unnest(ARRAY[2, 3]) u WHERE code = 'coach';   -- coaches, granted by the admin

-- ---------------------------------------------------------------------
-- 2. Plans and their items (blueprints)
--    Item ids = plan id x 100 + n. side 'both' on an asymmetric exercise
--    doubles the duration (BR8); reps are per side for asymmetric
--    exercises and total for symmetric ones.
-- ---------------------------------------------------------------------
INSERT INTO plan (id, coach_id, title, notes) OVERRIDING SYSTEM VALUE VALUES
  (1, 2, 'Hips and hamstrings',          'Main demo plan; used by sessions 1 and 2 (locked)'),
  (2, 2, 'Back care',                    'Used by sessions 3 and 6; locked by the closed session 3'),
  (3, 2, 'Full body flow',               'Used by sessions 4 and 5'),
  (4, 2, 'Shoulders (work in progress)', 'Draft: no target duration yet'),
  (5, 2, 'Splits preparation',           'Completed, not reviewed; target 45 min does not match the calculated duration (BR8 case)'),
  (6, 2, 'Ankles and calves',            'Reviewed, not used by any session (not locked)'),
  (8, 3, 'Evening relaxation',           'Plan of the former coach; used by session 7');
-- plan 7 is created below with duplicate_plan(1)

INSERT INTO plan_item (id, plan_id, exercise_id, phase, position, side, reps_count) OVERRIDING SYSTEM VALUE VALUES
  -- plan 1: compensation PRESENT (Child's Pose, Kneeling Hip Shifts);
  -- asymmetric exercise on both sides in one item (Ankle Circles – Standing)
  -- and as two items left/right (Half Split Hamstring Stretch – Static)
  (101, 1, pg_temp.ex('Neck Circles – Dynamic'),                               'warm_up',   1, 'both',  20),
  (102, 1, pg_temp.ex('Spinal Flexion and Extension – Standing – Dynamic'),    'warm_up',   2, 'both',  20),
  (103, 1, pg_temp.ex('Ankle Circles – Standing'),                             'warm_up',   3, 'both',  30),
  (104, 1, pg_temp.ex('Hamstring Stretch – Standing – Dynamic (Single-Leg)'),  'warm_up',   4, 'both',  20),
  (105, 1, pg_temp.ex('Hip Flexor Stretch – Half-Kneeling – Dynamic'),         'warm_up',   5, 'both',  20),
  (106, 1, pg_temp.ex('Half Split Hamstring Stretch – Dynamic'),               'main',      1, 'both',  20),
  (107, 1, pg_temp.ex('Half Split Hamstring Stretch – Static'),                'main',      2, 'left',   6),
  (108, 1, pg_temp.ex('Half Split Hamstring Stretch – Static'),                'main',      3, 'right',  6),
  (109, 1, pg_temp.ex('Supine Hamstring Stretch – Dynamic (Single-Leg)'),      'main',      4, 'both',  20),
  (110, 1, pg_temp.ex('Quadriceps Stretch – Half-Kneeling – Dynamic'),         'main',      5, 'both',  20),
  (111, 1, pg_temp.ex('Quadriceps Stretch – Half-Kneeling – Static'),          'main',      6, 'both',   6),
  (112, 1, pg_temp.ex('Pigeon Stretch – Dynamic'),                             'main',      7, 'both',  30),
  (113, 1, pg_temp.ex('Pigeon Stretch – Static'),                              'main',      8, 'both',   6),
  (114, 1, pg_temp.ex('Frog Stretch – Dynamic'),                               'main',      9, 'both',  30),
  (115, 1, pg_temp.ex('Kneeling Hip Shifts – Side-to-Side – Dynamic'),         'main',     10, 'both',  40),
  (116, 1, pg_temp.ex('Happy Baby Pose – Static'),                             'cool_down', 1, 'both',   6),
  (117, 1, pg_temp.ex('Child''s Pose – Static'),                               'cool_down', 2, 'both',   8),
  (118, 1, pg_temp.ex('Supine Relaxation – Static'),                           'cool_down', 3, 'both',  20),
  -- plan 2: compensation MISSING for Supine Spinal Twist – Static (its
  -- compensations Knees to Chest / Happy Baby are not in the plan: BR6)
  (201, 2, pg_temp.ex('Cat-Cow – Quadruped – Dynamic'),                        'warm_up',   1, 'both',  20),
  (202, 2, pg_temp.ex('Thoracic Rotation – Standing – Dynamic'),               'warm_up',   2, 'both',  12),
  (203, 2, pg_temp.ex('Spinal Lateral Flexion – Standing – Dynamic'),          'warm_up',   3, 'both',  12),
  (204, 2, pg_temp.ex('Spinal Flexion and Extension – Standing – Dynamic'),    'warm_up',   4, 'both',  15),
  (205, 2, pg_temp.ex('Cobra Stretch – Dynamic'),                              'main',      1, 'both',  15),
  (206, 2, pg_temp.ex('Cobra Stretch – Static'),                               'main',      2, 'both',   6),
  (207, 2, pg_temp.ex('Thread the Needle – Quadruped – Dynamic'),              'main',      3, 'both',  10),
  (208, 2, pg_temp.ex('Thread the Needle – Quadruped – Static'),               'main',      4, 'both',   4),
  (209, 2, pg_temp.ex('Bow Pose – Prone – Dynamic'),                           'main',      5, 'both',  10),
  (210, 2, pg_temp.ex('Bow Pose – Prone – Static'),                            'main',      6, 'both',   4),
  (211, 2, pg_temp.ex('Seated Spinal Flexion and Extension – Dynamic (Cross-Legged)'), 'main', 7, 'both', 15),
  (212, 2, pg_temp.ex('Supine Spinal Twist – Dynamic'),                        'main',      8, 'both',  10),
  (213, 2, pg_temp.ex('Child''s Pose – Static'),                               'cool_down', 1, 'both',   6),
  (214, 2, pg_temp.ex('Supine Spinal Twist – Static'),                         'cool_down', 2, 'both',   4),
  (215, 2, pg_temp.ex('Constructive Rest – Static'),                           'cool_down', 3, 'both',  12),
  -- plan 3: the only difficulty-3 exercise has no regression (BR11 warning case)
  (301, 3, pg_temp.ex('Neck Lateral Flexion – Dynamic'),                       'warm_up',   1, 'both',  10),
  (302, 3, pg_temp.ex('Wrist Circles – Seated – Dynamic'),                     'warm_up',   2, 'both',  12),
  (303, 3, pg_temp.ex('Shoulder Flexion – Quadruped – Alternating – Dynamic'), 'warm_up',   3, 'both',  12),
  (304, 3, pg_temp.ex('Ankle Flexion and Extension – Standing'),               'warm_up',   4, 'both',  15),
  (305, 3, pg_temp.ex('Calf Stretch – Standing – Dynamic'),                    'main',      1, 'both',  20),
  (306, 3, pg_temp.ex('Calf Stretch – Standing – Static'),                     'main',      2, 'both',   4),
  (307, 3, pg_temp.ex('Forward Fold – Standing – Dynamic (Feet Together)'),    'main',      3, 'both',  15),
  (308, 3, pg_temp.ex('Forward Fold – Standing – Static (Feet Together)'),     'main',      4, 'both',   4),
  (309, 3, pg_temp.ex('Quadriceps Stretch – Half-Kneeling – Dynamic'),         'main',      5, 'both',  10),
  (310, 3, pg_temp.ex('Kneeling Middle Split Prep – Dynamic'),                 'main',      6, 'both',  10),
  (311, 3, pg_temp.ex('Kneeling Middle Split Prep – Static'),                  'main',      7, 'left',   4),
  (312, 3, pg_temp.ex('Kneeling Middle Split Prep – Static'),                  'main',      8, 'right',  4),
  (313, 3, pg_temp.ex('Spinal Lateral Flexion – Standing – Dynamic'),          'main',      9, 'both',  10),
  (314, 3, pg_temp.ex('Kneeling Hip Shifts – Side-to-Side – Dynamic'),         'main',     10, 'both',  30),
  (315, 3, pg_temp.ex('Child''s Pose – Static'),                               'cool_down', 1, 'both',   6),
  (316, 3, pg_temp.ex('Diaphragmatic Breathing – Supine – Static'),            'cool_down', 2, 'both',  10),
  -- plan 4: draft
  (401, 4, pg_temp.ex('Thread the Needle – Quadruped – Dynamic'),              'warm_up',   1, 'both',  10),
  (402, 4, pg_temp.ex('Shoulder Flexion – Quadruped – Bilateral – Dynamic'),   'main',      1, 'both',  12),
  -- plan 5: completed
  (501, 5, pg_temp.ex('Kneeling Hip Shifts – Side-to-Side – Dynamic'),         'warm_up',   1, 'both',  30),
  (502, 5, pg_temp.ex('Front Split Stretch – Dynamic'),                        'main',      1, 'both',  10),
  (503, 5, pg_temp.ex('Front Split Stretch – Static'),                         'main',      2, 'left',   3),
  (504, 5, pg_temp.ex('Front Split Stretch – Static'),                         'main',      3, 'right',  3),
  (505, 5, pg_temp.ex('Child''s Pose – Static'),                               'cool_down', 1, 'both',   6),
  -- plan 6: reviewed, unused
  (601, 6, pg_temp.ex('Ankle Circles – Seated'),                               'warm_up',   1, 'both',  30),
  (602, 6, pg_temp.ex('Toe Flexion and Extension – Seated'),                   'warm_up',   2, 'both',  15),
  (603, 6, pg_temp.ex('Calf Stretch – Seated – Dynamic'),                      'main',      1, 'both',  20),
  (604, 6, pg_temp.ex('Calf Stretch – Seated – Static-Dynamic'),               'main',      2, 'both',  20),
  (605, 6, pg_temp.ex('Calf Stretch – Seated – Static'),                       'main',      3, 'both',   4),
  (606, 6, pg_temp.ex('Constructive Rest – Static'),                           'cool_down', 1, 'both',  12),
  -- plan 8: former coach
  (801, 8, pg_temp.ex('Knees to Chest – Dynamic'),                             'warm_up',   1, 'both',  15),
  (802, 8, pg_temp.ex('Happy Baby Pose – Dynamic'),                            'main',      1, 'both',  15),
  (803, 8, pg_temp.ex('Happy Baby Pose – Static'),                             'main',      2, 'both',   4),
  (804, 8, pg_temp.ex('Supine Spinal Twist – Dynamic'),                        'main',      3, 'both',  10),
  (805, 8, pg_temp.ex('Supine Relaxation – Static'),                           'cool_down', 1, 'both',  20);

-- Target durations: reviewed plans get the calculated duration (BR8 holds);
-- plan 5 keeps 45 min, which differs from its calculated duration.
UPDATE plan p
   SET target_duration_min = (SELECT round(sum(v.duration_sec) / 60.0) FROM v_plan_item v WHERE v.plan_id = p.id)
 WHERE p.id IN (1, 2, 3, 6, 8);
UPDATE plan SET target_duration_min = 45 WHERE id = 5;

-- Statuses: draft -> completed -> reviewed (the trigger checks the order)
UPDATE plan SET status = 'completed' WHERE id IN (1, 2, 3, 5, 6, 8);
UPDATE plan SET status = 'reviewed'  WHERE id IN (1, 2, 3, 6, 8);

-- plan 7: a duplicate of plan 1 (draft copy, editable). The sequences are
-- moved first, so the copy gets id 7 and its items ids 701..
SELECT setval(pg_get_serial_sequence('kinetune.plan',      'id'), 6);
SELECT setval(pg_get_serial_sequence('kinetune.plan_item', 'id'), 700);
DO $$ BEGIN
    IF kinetune.duplicate_plan(1) <> 7 THEN
        RAISE EXCEPTION 'duplicate_plan(1) was expected to create plan 7';
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 3. Sessions in every status
--    S1 done      plan 1  exactly 50 % (4 of 8) with knee discomfort -> BR10
--    S2 reviewed  plan 1  50 % but only one person (1 of 2)          -> BR9   (class in 30 min)
--    S3 closed    plan 2  more check-ins (7) than present (5); one undecided recommendation (class in 45 min)
--    S4 open      plan 3  check-in link active, two answers so far
--    S5 done      plan 3  poor sleep on a difficulty-3 exercise without regression -> BR11 warning
--    S6 done      plan 2  0 check-ins: no recommendations
--    S7 done      plan 8  former coach (deactivated afterwards)
-- ---------------------------------------------------------------------
INSERT INTO session (id, coach_id, plan_id, group_name, starts_at, checkin_token) OVERRIDING SYSTEM VALUE VALUES
  (1, 2, 1, 'Tuesday evening',   pg_temp.t(-14, '17:00'), rpad('test_session_01_', 43, 'x')),
  (2, 2, 1, 'Lunch break group', now() + interval '30 minutes', rpad('test_session_02_', 43, 'x')),
  (3, 2, 2, 'Back care group',   now() + interval '45 minutes', rpad('test_session_03_', 43, 'x')),
  (4, 2, 3, 'Saturday open',     pg_temp.t(  2, '10:00'), rpad('test_session_04_', 43, 'x')),
  (5, 2, 3, 'Tuesday evening',   pg_temp.t( -7, '17:00'), rpad('test_session_05_', 43, 'x')),
  (6, 2, 2, 'Back care group',   pg_temp.t( -3, '20:00'), rpad('test_session_06_', 43, 'x')),
  (7, 3, 8, 'Former group',      pg_temp.t(-30, '19:00'), rpad('test_session_07_', 43, 'x'));

-- check-ins (anonymous; energy low/normal/high; discomfort only in check-in body areas)
CREATE TEMP TABLE seed_checkin (session_id int, energy energy_level, poor_sleep boolean, language char(2), minutes_before int, areas text[]);
INSERT INTO seed_checkin VALUES
  -- S1: 6 check-ins, 8 present -> knee 4 of 8 = 50 %, pelvis/hips 1 of 8
  (1, 'normal', false, 'en', 40, '{knee}'),
  (1, 'normal', false, 'ru', 35, '{knee}'),
  (1, 'high',   false, 'en', 30, '{knee,lower_back}'),
  (1, 'normal', false, 'ru', 25, '{knee}'),
  (1, 'high',   false, 'en', 20, '{}'),
  (1, 'normal', false, 'ru', 15, '{pelvis_hips}'),
  -- S2: 2 check-ins, 2 present -> knee 1 of 2 = 50 % but one person
  (2, 'normal', false, 'en', 0, '{knee}'),
  (2, 'high',   false, 'ru', 0, '{}'),
  -- S3: 7 check-ins, 5 present -> base 7; lower back 3 of 7 = 43 %
  (3, 'normal', false, 'en', 0, '{lower_back}'),
  (3, 'normal', false, 'en', 0, '{lower_back}'),
  (3, 'normal', false, 'ru', 0, '{lower_back}'),
  (3, 'high',   false, 'ru', 0, '{}'),
  (3, 'normal', false, 'en', 0, '{}'),
  (3, 'normal', false, 'ru', 0, '{}'),
  (3, 'high',   false, 'en', 0, '{}'),
  -- S4: open, two answers so far
  (4, 'low',    true,  'ru', 0, '{}'),
  (4, 'normal', false, 'en', 0, '{wrists_hands}'),
  -- S5: 6 check-ins, 6 present -> poor sleep 2 of 6 = 33 %; ankle discomfort
  --     (no high ankle load in plan 3: nothing to recommend for it)
  (5, 'normal', true,  'en', 40, '{}'),
  (5, 'low',    true,  'ru', 35, '{}'),
  (5, 'normal', false, 'en', 30, '{ankle_foot}'),
  (5, 'high',   false, 'en', 25, '{}'),
  (5, 'normal', false, 'ru', 20, '{}'),
  (5, 'normal', false, 'en', 15, '{}'),
  -- S6: none
  -- S7: 3 check-ins, nothing reported
  (7, 'normal', false, 'en', 30, '{}'),
  (7, 'high',   false, 'en', 25, '{}'),
  (7, 'normal', false, 'ru', 20, '{}');

DO $$
DECLARE
    r    record;
    v_id integer;
BEGIN
    FOR r IN SELECT sc.*, s.starts_at FROM seed_checkin sc JOIN kinetune.session s ON s.id = sc.session_id LOOP
        INSERT INTO kinetune.checkin (session_id, energy, poor_sleep, language, submitted_at)
        VALUES (r.session_id, r.energy, r.poor_sleep, r.language,
                CASE WHEN r.minutes_before = 0 THEN now() ELSE r.starts_at - r.minutes_before * interval '1 minute' END)
        RETURNING id INTO v_id;
        INSERT INTO kinetune.checkin_discomfort (checkin_id, body_area_id)
        SELECT v_id, pg_temp.area(a) FROM unnest(r.areas) a;
    END LOOP;
END $$;

-- close the check-in with the number of participants present (required);
-- the trigger sets checkin_closed_at = now(), corrected to a realistic time
UPDATE session SET status = 'closed', participants_present = 8 WHERE id = 1;
UPDATE session SET status = 'closed', participants_present = 2 WHERE id = 2;
UPDATE session SET status = 'closed', participants_present = 5 WHERE id = 3;
UPDATE session SET status = 'closed', participants_present = 6 WHERE id = 5;
UPDATE session SET status = 'closed', participants_present = 4 WHERE id = 6;
UPDATE session SET status = 'closed', participants_present = 5 WHERE id = 7;
-- (sessions 2 and 3 take place today: closed now)
UPDATE session SET checkin_closed_at = starts_at - interval '10 minutes' WHERE id IN (1, 5, 6, 7);

-- ---------------------------------------------------------------------
-- 4. Recommendations (generated at close) and the coach's decisions
--    Every candidate comes from the graphs: it shares a family and a main
--    muscle with the original and is not a progression (harder version) of it.
-- ---------------------------------------------------------------------
INSERT INTO recommendation (id, session_id, plan_item_id, rule_id, form, is_warning, candidate_exercise_id,
                            affected_count, explanation, explanation_source, created_at) OVERRIDING SYSTEM VALUE VALUES
  -- S1: knee 4 of 8 = 50 % and >= 2 -> BR10 replacement; cascade step 2 (lower knee load), same-level variation
  (1, 1, 111, 10, 'replacement', false, pg_temp.ex('Quadriceps Stretch – Standing – Static'), 4,
      'Four of eight participants (50%) reported discomfort in the knee. Replacing the half-kneeling quadriceps stretch with the standing version for the whole group keeps the same quads stretch with a lower load on the knee. (AI-generated)',
      'llm', pg_temp.t(-14, '16:50')),
  (2, 1, 110, 10, 'replacement', false, pg_temp.ex('Quadriceps Stretch – Standing – Dynamic'), 4,
      '4 of 8 participants (50%) reported discomfort in the knee. Replacing "Quadriceps Stretch – Half-Kneeling – Dynamic" with "Quadriceps Stretch – Standing – Dynamic" for the whole group is suggested: same level, another execution, a lower load on the knee.',
      'template', pg_temp.t(-14, '16:50')),
  -- S1: pelvis/hips 1 of 8 -> BR9 alternative; step 2 has no same-level variation, so a regression
  (3, 1, 113,  9, 'alternative', false, pg_temp.ex('Supine Figure-Four Stretch – Static'), 1,
      '1 of 8 participants (13%) reported discomfort in the pelvis and hips. "Supine Figure-Four Stretch – Static" is offered next to "Pigeon Stretch – Static" for those who need it: a gentler version of the same stretch.',
      'template', pg_temp.t(-14, '16:50')),
  (4, 1, 112,  9, 'alternative', false, pg_temp.ex('Supine Figure-Four Stretch – Dynamic'), 1,
      '1 of 8 participants (13%) reported discomfort in the pelvis and hips. "Supine Figure-Four Stretch – Dynamic" is offered next to "Pigeon Stretch – Dynamic" for those who need it: a gentler version of the same stretch.',
      'template', pg_temp.t(-14, '16:50')),
  -- S2: knee 1 of 2 = 50 % but only one person -> BR9 alternative, not BR10
  (5, 2, 111,  9, 'alternative', false, pg_temp.ex('Quadriceps Stretch – Standing – Static'), 1,
      '1 of 2 participants (50%) reported discomfort in the knee. "Quadriceps Stretch – Standing – Static" is offered next to "Quadriceps Stretch – Half-Kneeling – Static" for those who need it: same level, another execution, a lower load on the knee.',
      'template', now()),
  (6, 2, 110,  9, 'alternative', false, pg_temp.ex('Quadriceps Stretch – Standing – Dynamic'), 1,
      '1 of 2 participants (50%) reported discomfort in the knee. "Quadriceps Stretch – Standing – Dynamic" is offered next to "Quadriceps Stretch – Half-Kneeling – Dynamic" for those who need it: same level, another execution, a lower load on the knee.',
      'template', now()),
  -- S3: lower back 3 of 7 (base = check-ins, more than present) -> BR9; step 1 (no load on the lumbar spine)
  (7, 3, 210,  9, 'alternative', false, pg_temp.ex('Thoracic Extension – Prone on Forearms – Static'), 3,
      '3 of 7 participants (43%) reported discomfort in the lower back. "Thoracic Extension – Prone on Forearms – Static" is offered next to "Bow Pose – Prone – Static" for those who need it: no load on the lower back.',
      'template', now()),
  (8, 3, 209,  9, 'alternative', false, pg_temp.ex('Thoracic Extension – Prone on Forearms – Dynamic'), 3,
      '3 of 7 participants (43%) reported discomfort in the lower back. "Thoracic Extension – Prone on Forearms – Dynamic" is offered next to "Bow Pose – Prone – Dynamic" for those who need it: no load on the lower back.',
      'template', now()),
  -- S5: poor sleep 2 of 6 on a difficulty-3 exercise; it has no regression -> BR11 warning
  (9, 5, 309, 11, 'alternative', true, NULL, 2,
      'No suitable substitute for "Quadriceps Stretch – Half-Kneeling – Dynamic" was found in the library (poor sleep). Consider fewer repetitions, a smaller amplitude or a slower pace.',
      'template', pg_temp.t(-7, '16:50'));

INSERT INTO recommendation_decision (recommendation_id, decision, decided_at) VALUES
  (1, 'accepted', pg_temp.t(-14, '16:53')),
  (2, 'declined', pg_temp.t(-14, '16:54')),
  (3, 'accepted', pg_temp.t(-14, '16:55')),
  (4, 'declined', pg_temp.t(-14, '16:55')),
  (5, 'accepted', now()),
  (6, 'declined', now()),
  (7, 'accepted', now()),
  -- recommendation 8 is left UNDECIDED: session 3 stays 'closed'
  (9, 'accepted', pg_temp.t(-7, '16:52'));

-- ---------------------------------------------------------------------
-- 5. Session review, feedback, class done
-- ---------------------------------------------------------------------
UPDATE session SET status = 'reviewed' WHERE id IN (1, 2, 5, 6, 7);   -- every recommendation decided
UPDATE session SET status = 'done'     WHERE id IN (1, 5, 6, 7);      -- S2 stays reviewed (class tomorrow)

INSERT INTO feedback (session_id, rating, comment, submitted_at) VALUES
  (1, 5, 'The standing version was much easier on my knee.', pg_temp.t(-14, '18:10')),
  (1, 4, NULL,                                                pg_temp.t(-14, '18:20')),
  (1, 3, 'Too many hamstring holds for me.',                  pg_temp.t(-13, '09:00')),
  (5, 4, NULL,                                                pg_temp.t(-7, '18:15')),
  (7, 5, 'Very relaxing.',                                    pg_temp.t(-30, '20:05')),
  (7, 4, NULL,                                                pg_temp.t(-30, '20:30'));

-- ---------------------------------------------------------------------
-- 6. Later changes
-- ---------------------------------------------------------------------
-- an exercise used in old plans is deactivated (DQ16 warning: plans 1 and 7 use it)
UPDATE exercise SET is_active = false WHERE id = pg_temp.ex('Frog Stretch – Dynamic');
-- the second coach leaves: the account is deactivated, the history stays
UPDATE app_user SET is_active = false WHERE id = 3;

-- ---------------------------------------------------------------------
-- 7. Move identity sequences past the explicitly set ids
-- ---------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('kinetune.app_user',       'id'), (SELECT max(id) FROM app_user));
SELECT setval(pg_get_serial_sequence('kinetune.plan',           'id'), (SELECT max(id) FROM plan));
SELECT setval(pg_get_serial_sequence('kinetune.plan_item',      'id'), (SELECT max(id) FROM plan_item));
SELECT setval(pg_get_serial_sequence('kinetune.session',        'id'), (SELECT max(id) FROM session));
SELECT setval(pg_get_serial_sequence('kinetune.recommendation', 'id'), (SELECT max(id) FROM recommendation));

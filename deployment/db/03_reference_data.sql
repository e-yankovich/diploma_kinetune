-- =====================================================================
-- Kinetune — reference (fixed) data
-- Applied by Alembic migration 0002. Manual run:
--   psql -v ON_ERROR_STOP=1 --single-transaction -f 03_reference_data.sql
--
-- Contents: application roles and permissions, body areas (the check-in
-- list from thesis 2.5), muscles, joints, business rules BR1–BR11.
-- Ids are set explicitly so that seed files and tests can refer to them;
-- identity sequences are moved past the last id at the end.
-- =====================================================================

SET search_path TO kinetune;

-- ---------------------------------------------------------------------
-- Application roles and permissions (data_dictionary.md §4.3)
-- ---------------------------------------------------------------------
INSERT INTO role (id, code, name, description) OVERRIDING SYSTEM VALUE VALUES
  (1, 'coach', 'Coach',         'Plans classes, runs sessions, decides on recommendations'),
  (2, 'admin', 'Administrator', 'Manages users, roles and reference data');
-- the client role (future) is added by a later migration

INSERT INTO permission (id, code, description) OVERRIDING SYSTEM VALUE VALUES
  ( 1, 'library.read',          'View exercises, muscles, joints and relations'),
  ( 2, 'library.write',         'Add, edit or deactivate exercises and relations'),
  ( 3, 'plan.read',             'View own plans'),
  ( 4, 'plan.write',            'Create, edit and delete own plans'),
  ( 5, 'session.manage',        'Create sessions, share and close the check-in, enter attendance'),
  ( 6, 'checkin.read_summary',  'View aggregated check-in results of own sessions'),
  ( 7, 'recommendation.decide', 'Accept or decline recommendations'),
  ( 8, 'feedback.read',         'View feedback of own sessions'),
  ( 9, 'report.read',           'View KPI reports of own sessions'),
  (10, 'user.manage',           'Create and deactivate users, reset passwords'),
  (11, 'role.manage',           'Grant and revoke roles'),
  (12, 'reference.write',       'Edit body areas, muscles, joints and rule texts');

INSERT INTO role_permission (role_id, permission_id) VALUES
  -- coach
  (1, 1), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9),
  -- admin (no access to participants' answers: data minimisation)
  (2, 1), (2, 2), (2, 10), (2, 11), (2, 12);

-- ---------------------------------------------------------------------
-- Body areas: the discomfort list of the check-in form (thesis 2.5)
-- ---------------------------------------------------------------------
INSERT INTO body_area (id, code, name_en, name_ru) OVERRIDING SYSTEM VALUE VALUES
  (1, 'neck',       'Neck',       'Шея'),
  (2, 'shoulders',  'Shoulders',  'Плечи'),
  (3, 'wrists',     'Wrists',     'Запястья'),
  (4, 'lower_back', 'Lower back', 'Поясница'),
  (5, 'hips',       'Hips',       'Тазобедренные суставы'),
  (6, 'knees',      'Knees',      'Колени');

-- ---------------------------------------------------------------------
-- Joints (one per body area)
-- ---------------------------------------------------------------------
INSERT INTO joint (id, name, body_area_id) OVERRIDING SYSTEM VALUE VALUES
  (1, 'cervical spine', 1),
  (2, 'shoulder',       2),
  (3, 'wrist',          3),
  (4, 'lumbar spine',   4),
  (5, 'hip',            5),
  (6, 'knee',           6);

-- ---------------------------------------------------------------------
-- Muscles (each belongs to exactly one body area)
-- ---------------------------------------------------------------------
INSERT INTO muscle (id, name, body_area_id) OVERRIDING SYSTEM VALUE VALUES
  ( 1, 'upper trapezius',    1),
  ( 2, 'levator scapulae',   1),
  ( 3, 'sternocleidomastoid',1),
  ( 4, 'deltoids',           2),
  ( 5, 'pectoralis major',   2),
  ( 6, 'latissimus dorsi',   2),
  ( 7, 'rotator cuff',       2),
  ( 8, 'wrist flexors',      3),
  ( 9, 'wrist extensors',    3),
  (10, 'erector spinae',     4),
  (11, 'quadratus lumborum', 4),
  (12, 'gluteus maximus',    5),
  (13, 'gluteus medius',     5),
  (14, 'hip flexors',        5),
  (15, 'adductors',          5),
  (16, 'piriformis',         5),
  (17, 'quadriceps',         6),
  (18, 'hamstrings',         6),
  (19, 'calves',             6);

-- ---------------------------------------------------------------------
-- Business rules BR1–BR11 (thesis Table 2.7)
-- explanation = template shown to the coach; placeholders in {braces}
-- are filled by the backend. Also the fallback when the LLM fails (NFR9).
-- ---------------------------------------------------------------------
INSERT INTO rule (id, description, explanation) VALUES
  (1, 'The plan consists of three phases: a warm-up, a main part and a cool-down.',
      'The plan is missing the {phase} phase.'),
  (2, 'The warm-up contains only dynamic exercises.',
      '"{exercise}" is not dynamic and is placed in the warm-up.'),
  (3, 'High-difficulty exercises are not placed in the warm-up or the cool-down.',
      '"{exercise}" is a high-difficulty exercise placed in the {phase}.'),
  (4, 'Every static exercise is preceded, in any earlier phase, by at least one dynamic exercise for the same joint or body area.',
      'No dynamic exercise for the {area} comes before the static exercise "{exercise}".'),
  (5, 'Static exercises make up no more than 35% of the exercises in the main part.',
      'Static exercises make up {share}% of the main part (limit 35%).'),
  (6, 'An exercise that requires compensation (in particular for the back) is followed by a compensating exercise before the end of the class; if the compensation comes more than five exercises later, the platform suggests moving it closer.',
      '"{exercise}" needs the compensating exercise "{compensation}" {problem}.'),
  (7, 'An asymmetric exercise is performed on both sides within the same phase.',
      '"{exercise}" is planned only for the {side} side in the {phase}.'),
  (8, 'The total duration of the plan differs from the class duration by no more than 5 minutes.',
      'The plan lasts {plan_minutes} min; the class lasts {class_minutes} min.'),
  (9, 'If from one participant up to less than 50% of the participants present report discomfort in a joint that an exercise loads at a medium or high level, or report low energy or poor sleep while a balance exercise is placed in the first quarter of the class, an alternative is proposed next to the original exercise.',
      '{affected} of {present} participants reported {factor}. "{candidate}" is offered next to "{exercise}" for those who need it.'),
  (10, 'If at least 50% of the participants present, and at least two participants, report such a condition, the replacement of the exercise for the whole group is proposed.',
      '{affected} of {present} participants reported {factor}. Replacing "{exercise}" with "{candidate}" for the whole group is suggested.'),
  (11, 'A proposed exercise targets the same muscle, belongs to the same phase, removes the reported factor (a lower load on the reported joint or no balance) and keeps the plan compliant with BR1–BR8; if no exercise qualifies, a warning with general advice (fewer repetitions, smaller amplitude, slower pace) is shown.',
      'No suitable substitute for "{exercise}" was found. Consider fewer repetitions, a smaller amplitude or a slower pace.');

-- ---------------------------------------------------------------------
-- Move identity sequences past the explicitly set ids
-- ---------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('kinetune.role',       'id'), (SELECT max(id) FROM role));
SELECT setval(pg_get_serial_sequence('kinetune.permission', 'id'), (SELECT max(id) FROM permission));
SELECT setval(pg_get_serial_sequence('kinetune.body_area',  'id'), (SELECT max(id) FROM body_area));
SELECT setval(pg_get_serial_sequence('kinetune.joint',      'id'), (SELECT max(id) FROM joint));
SELECT setval(pg_get_serial_sequence('kinetune.muscle',     'id'), (SELECT max(id) FROM muscle));

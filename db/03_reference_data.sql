-- =====================================================================
-- Kinetune — reference (fixed) data
-- Applied by Alembic migration 0002. Manual run:
--   psql -v ON_ERROR_STOP=1 --single-transaction -f 03_reference_data.sql
--
-- Contents: application roles and permissions, body areas (10, of which
-- 7 are in the check-in), joints (11), muscles (28), business rules
-- BR1–BR11. Exercise families are not seeded here: they come from the
-- library import (db/library/).
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
-- Body areas (body parts). is_in_checkin = shown in the check-in form;
-- only these can trigger BR9/BR10. Source: library sheet "Body parts".
-- ---------------------------------------------------------------------
INSERT INTO body_area (id, code, name_en, name_ru, is_in_checkin) OVERRIDING SYSTEM VALUE VALUES
  ( 1, 'head_neck',       'Head and neck',    'Голова и шея',        true),
  ( 2, 'shoulder_girdle', 'Shoulder girdle',  'Плечевой пояс',       true),
  ( 3, 'arm',             'Arm',              'Рука',                false),
  ( 4, 'wrists_hands',    'Wrists and hands', 'Запястья и кисти',    true),
  ( 5, 'upper_back',      'Upper back',       'Верхняя часть спины', false),
  ( 6, 'lower_back',      'Lower back',       'Поясница',            true),
  ( 7, 'abdomen',         'Abdomen',          'Живот',               false),
  ( 8, 'pelvis_hips',     'Pelvis and hips',  'Таз и бёдра',         true),
  ( 9, 'knee',            'Knee',             'Колено',              true),
  (10, 'ankle_foot',      'Ankle and foot',   'Голеностоп и стопа',  true);

-- ---------------------------------------------------------------------
-- Joints (each belongs to exactly one body area). Names are lower-case
-- English: the library import matches them by name.
-- ---------------------------------------------------------------------
INSERT INTO joint (id, name, body_area_id) OVERRIDING SYSTEM VALUE VALUES
  ( 1, 'cervical spine',  1),
  ( 2, 'shoulder',        2),
  ( 3, 'elbow',           3),
  ( 4, 'wrist',           4),
  ( 5, 'fingers',         4),
  ( 6, 'thoracic spine',  5),
  ( 7, 'lumbar spine',    6),
  ( 8, 'hip',             8),
  ( 9, 'knee',            9),
  (10, 'ankle',          10),
  (11, 'foot',           10);
-- abdomen has no joint (muscles only); knee has no muscle (joint only)

-- ---------------------------------------------------------------------
-- Muscles (each belongs to exactly one body area). Names are lower-case
-- English: the library import matches them by name.
-- ---------------------------------------------------------------------
INSERT INTO muscle (id, name, body_area_id) OVERRIDING SYSTEM VALUE VALUES
  ( 1, 'upper traps',         1),
  ( 2, 'side of neck',        1),
  ( 3, 'front of neck',       1),
  ( 4, 'delts',               2),
  ( 5, 'chest',               2),
  ( 6, 'rotator cuff',        2),
  ( 7, 'biceps',              3),
  ( 8, 'triceps',             3),
  ( 9, 'forearm flexors',     3),
  (10, 'forearm extensors',   3),
  (11, 'finger flexors',      4),
  (12, 'lats',                5),
  (13, 'mid back',            5),
  (14, 'back extensors',      6),
  (15, 'side of lower back',  6),
  (16, 'abs',                 7),
  (17, 'obliques',            7),
  (18, 'glutes',              8),
  (19, 'outer hip',           8),
  (20, 'deep hip rotators',   8),
  (21, 'hip flexors',         8),
  (22, 'quads',               8),
  (23, 'hamstrings',          8),
  (24, 'inner thigh',         8),
  (25, 'calves',             10),
  (26, 'shin',               10),
  (27, 'peroneals',          10),
  (28, 'sole of foot',       10);

-- ---------------------------------------------------------------------
-- Business rules BR1–BR11 (business rules v2, docs/business-rules.md)
-- description = the rule's logic; explanation = short template shown to
-- the coach; placeholders in {braces} are filled by the backend
-- (data_dictionary.md §4.1). Also the fallback when the LLM fails (NFR9).
-- ---------------------------------------------------------------------
INSERT INTO rule (id, description, explanation) VALUES
  (1, 'The plan has three phases in this order: warm-up, main part, cool-down.',
      'The plan needs a warm-up, a main part and a cool-down, in this order: {problem}.'),
  (2, 'The warm-up contains only dynamic exercises (stato-dynamic exercises are not allowed in the warm-up).',
      '"{exercise}" is {mode} and is placed in the warm-up; the warm-up contains only dynamic exercises.'),
  (3, 'High-difficulty exercises (difficulty 3) are not placed in the warm-up or the cool-down.',
      '"{exercise}" is a high-difficulty exercise placed in the {phase}.'),
  (4, 'Every static exercise is preceded, in an earlier phase or earlier in the same phase, by at least one dynamic exercise for the same joint, muscle or body part. A stato-dynamic exercise does not count as dynamic.',
      'No dynamic exercise for the same joint, muscle or body part comes before the static exercise "{exercise}".'),
  (5, 'Static exercises make up no more than 40% of the exercises in the main part. Stato-dynamic exercises are not counted as static.',
      'Static exercises make up {share}% of the main part (limit 40%).'),
  (6, 'An exercise that requires compensation is followed by one of its compensating exercises before the end of the class; any one of the listed compensating exercises satisfies the rule. If the nearest one comes more than five exercises later, the platform suggests moving it closer.',
      '"{exercise}" needs a compensating exercise later in the class: {problem}. Options: {options}.'),
  (7, 'An asymmetric exercise is performed on both sides within the same phase.',
      '"{exercise}" is planned only for the {side} side in the {phase}.'),
  (8, 'The calculated plan duration differs from the target class duration by no more than 5 minutes. Duration = repetitions x repetition duration, x2 for an asymmetric exercise planned on both sides in one item.',
      'The plan lasts {plan_minutes} min; the target is {target_minutes} min (allowed difference: 5 min).'),
  (9, 'Alternative. Each factor is counted separately: discomfort in a body part, low energy, poor sleep; base = participants present (the number of check-ins if it is higher). If from one participant up to less than 50% of the base report a factor, an alternative is proposed next to the original exercise for: (1) low energy or poor sleep: exercises with the balance starting pose and high-difficulty exercises; (2) discomfort in a body part: exercises with a high load on any joint of that body part.',
      '{affected} of {base} participants ({share}%) reported {factor}. "{candidate}" is offered next to "{exercise}" for those who need it: {reason}.'),
  (10, 'Replacement. Same conditions as BR9, when a factor is reported by at least 50% of the base and by at least two participants: the replacement of the exercise for the whole group is proposed, and only one variant is shown.',
      '{affected} of {base} participants ({share}%) reported {factor}. Replacing "{exercise}" with "{candidate}" for the whole group is suggested: {reason}.'),
  (11, 'Candidate. A candidate shares at least one main (target) muscle with the original, shares a family with it or is linked to it by manual progressions, takes the same place in the same phase and keeps the plan compliant with BR1–BR8. Candidates come only from the graphs: variations and regressions (progressions followed backwards); a progression of the original (a harder version) is never offered, even if it is also a variation. Search is a cascade; on each step first a same-level variation (no progression in either direction), then a regression. Discomfort in a body part: (1) no load on its joints, (2) a lower load on its joints, (3) any regression. Low energy or poor sleep: balance exercise: (1) a variation without balance, (2) a regression without balance, (3) any regression; high-difficulty exercise: (1) a regression. If no step finds a candidate, a warning with general advice is shown (fewer repetitions, smaller amplitude, slower pace).',
      'No suitable substitute for "{exercise}" was found in the library ({factor}). Consider fewer repetitions, a smaller amplitude or a slower pace.');

-- ---------------------------------------------------------------------
-- Move identity sequences past the explicitly set ids
-- ---------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('kinetune.role',       'id'), (SELECT max(id) FROM role));
SELECT setval(pg_get_serial_sequence('kinetune.permission', 'id'), (SELECT max(id) FROM permission));
SELECT setval(pg_get_serial_sequence('kinetune.body_area',  'id'), (SELECT max(id) FROM body_area));
SELECT setval(pg_get_serial_sequence('kinetune.joint',      'id'), (SELECT max(id) FROM joint));
SELECT setval(pg_get_serial_sequence('kinetune.muscle',     'id'), (SELECT max(id) FROM muscle));

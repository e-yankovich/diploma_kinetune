-- =====================================================================
-- Kinetune — data quality check queries (data_dictionary.md §6)
-- Each branch returns the rows that VIOLATE a rule; an empty result means
-- every rule holds. severity 'error' = must be fixed (the library import
-- fails on the library checks); 'warning' = reported, data accepted.
-- Run: psql -f db/checks/data_quality_checks.sql   (any role with app_read)
-- The library import runs the same query inside its transaction and fails
-- on error rows of the library checks (DQ09, DQ10, DQ12, DQ14, DQ26, DQ27, DQ34).
-- Rules guaranteed by constraints are not repeated here (e.g. a load level
-- for every listed joint: NOT NULL; no progressions in both directions:
-- unique index, DQ36).
-- =====================================================================

SET search_path TO kinetune;

WITH RECURSIVE progression_path (start_id, current_id, path, is_cycle) AS (
    SELECT from_exercise_id, to_exercise_id, ARRAY[from_exercise_id, to_exercise_id], false
      FROM exercise_relation
    UNION ALL
    SELECT p.start_id, r.to_exercise_id, p.path || r.to_exercise_id, r.to_exercise_id = ANY (p.path)
      FROM progression_path p
      JOIN exercise_relation r ON r.from_exercise_id = p.current_id
     WHERE NOT p.is_cycle
)
SELECT check_id, severity, detail FROM (

    SELECT 'DQ09' AS check_id, 'error' AS severity,
           format('exercise %s "%s" has no main joint and no main muscle', e.id, e.name) AS detail
      FROM exercise e
     WHERE e.is_active
       AND NOT EXISTS (SELECT 1 FROM exercise_muscle m WHERE m.exercise_id = e.id AND m.is_primary)
       AND NOT EXISTS (SELECT 1 FROM exercise_joint  j WHERE j.exercise_id = e.id AND j.is_primary)

    UNION ALL
    SELECT 'DQ10', 'error', format('body area "%s" has no muscle or joint', b.code)
      FROM body_area b
     WHERE NOT EXISTS (SELECT 1 FROM muscle m WHERE m.body_area_id = b.id)
       AND NOT EXISTS (SELECT 1 FROM joint  j WHERE j.body_area_id = b.id)

    UNION ALL
    -- a substitute is searched among variations (a family with another
    -- member) and regressions (progressions followed backwards)
    SELECT 'DQ11', 'warning', format('exercise %s "%s" is used in plans but has no variation and no regression: no substitute can be found', e.id, e.name)
      FROM exercise e
     WHERE e.is_active
       AND EXISTS (SELECT 1 FROM plan_item pi WHERE pi.exercise_id = e.id)
       AND NOT EXISTS (SELECT 1 FROM v_exercise_variation v WHERE v.exercise_id = e.id)
       AND NOT EXISTS (SELECT 1 FROM exercise_relation r WHERE r.to_exercise_id = e.id)

    UNION ALL
    SELECT DISTINCT 'DQ12', 'error', format('progression cycle: %s', array_to_string(path, ' -> '))
      FROM progression_path WHERE is_cycle

    UNION ALL
    SELECT 'DQ13', 'warning', format('plan %s, phase %s: positions are not 1..%s', plan_id, phase, count(*))
      FROM plan_item
     GROUP BY plan_id, phase
    HAVING max(position) <> count(*) OR min(position) <> 1

    UNION ALL
    SELECT 'DQ14', 'error', format('rule table holds %s rows (ids %s), expected BR1–BR11', count(*), string_agg(id::text, ',' ORDER BY id))
      FROM rule
    HAVING count(*) <> 11 OR min(id) <> 1 OR max(id) <> 11

    UNION ALL
    SELECT 'DQ15', 'warning', format('session %s: %s check-ins but %s participants present (base = check-ins; K2 > 100 %%)',
                                     s.id, count(c.id), s.participants_present)
      FROM session s JOIN checkin c ON c.session_id = s.id
     WHERE s.participants_present IS NOT NULL
     GROUP BY s.id
    HAVING count(c.id) > s.participants_present

    UNION ALL
    SELECT 'DQ16', 'warning', format('plan %s uses inactive exercise %s "%s"', pi.plan_id, e.id, e.name)
      FROM plan_item pi JOIN exercise e ON e.id = pi.exercise_id
     WHERE NOT e.is_active

    UNION ALL
    SELECT 'DQ17', 'warning', format('progression %s -> %s goes to an easier exercise (difficulty %s -> %s)',
                                     r.from_exercise_id, r.to_exercise_id, a.difficulty, b.difficulty)
      FROM exercise_relation r
      JOIN exercise a ON a.id = r.from_exercise_id
      JOIN exercise b ON b.id = r.to_exercise_id
     WHERE b.difficulty < a.difficulty

    UNION ALL
    SELECT 'DQ24', 'error', format('role "%s" has no permissions', r.code)
      FROM role r
     WHERE NOT EXISTS (SELECT 1 FROM role_permission rp WHERE rp.role_id = r.id)

    UNION ALL
    SELECT 'DQ26', 'error', format('compensation loop: "%s" and "%s" compensate each other', a.name, b.name)
      FROM exercise_compensation x
      JOIN exercise_compensation y ON y.exercise_id = x.compensation_exercise_id
                                  AND y.compensation_exercise_id = x.exercise_id
      JOIN exercise a ON a.id = x.exercise_id
      JOIN exercise b ON b.id = x.compensation_exercise_id
     WHERE x.exercise_id < x.compensation_exercise_id

    UNION ALL
    SELECT 'DQ27', 'error', format('exercise %s "%s" lists the inactive compensating exercise %s "%s"', a.id, a.name, b.id, b.name)
      FROM exercise_compensation x
      JOIN exercise a ON a.id = x.exercise_id
      JOIN exercise b ON b.id = x.compensation_exercise_id
     WHERE a.is_active AND NOT b.is_active

    UNION ALL
    SELECT 'DQ28', 'warning', format('exercise %s "%s" has no main joint', e.id, e.name)
      FROM exercise e
     WHERE e.is_active
       AND NOT EXISTS (SELECT 1 FROM exercise_joint j WHERE j.exercise_id = e.id AND j.is_primary)

    UNION ALL
    -- a plan used by a session must have been reviewed (it is locked since then)
    SELECT 'DQ30', 'error', format('plan %s is used by session(s) but has status %s', p.id, p.status)
      FROM plan p
     WHERE p.status <> 'reviewed'
       AND EXISTS (SELECT 1 FROM session s WHERE s.plan_id = p.id)

    UNION ALL
    SELECT 'DQ34', 'error', format('body area "%s" is shown in the check-in but has no joint', b.code)
      FROM body_area b
     WHERE b.is_in_checkin
       AND NOT EXISTS (SELECT 1 FROM joint j WHERE j.body_area_id = b.id)

    UNION ALL
    -- allowed in the MVP: the member simply has no variations through the family
    SELECT 'DQ35', 'warning', format('family "%s" has %s exercise(s)', f.name, count(m.exercise_id))
      FROM exercise_family f
      LEFT JOIN exercise_family_member m ON m.family_id = f.id
     GROUP BY f.id, f.name
    HAVING count(m.exercise_id) < 2

) checks
ORDER BY severity, check_id, detail;

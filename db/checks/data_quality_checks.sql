-- =====================================================================
-- Kinetune — data quality check queries (data_dictionary.md §6)
-- Each branch returns the rows that VIOLATE a rule; an empty result means
-- every rule holds. severity 'error' = must be fixed (import fails);
-- 'warning' = reported, data accepted.
-- Run: psql -f db/checks/data_quality_checks.sql   (any role with app_read)
-- =====================================================================

SET search_path TO kinetune;

WITH RECURSIVE progression_path (start_id, current_id, path, is_cycle) AS (
    SELECT from_exercise_id, to_exercise_id, ARRAY[from_exercise_id, to_exercise_id], false
      FROM exercise_relation WHERE type = 'progression'
    UNION ALL
    SELECT p.start_id, r.to_exercise_id, p.path || r.to_exercise_id, r.to_exercise_id = ANY (p.path)
      FROM progression_path p
      JOIN exercise_relation r ON r.from_exercise_id = p.current_id AND r.type = 'progression'
     WHERE NOT p.is_cycle
)
SELECT check_id, severity, detail FROM (

    SELECT 'DQ09' AS check_id, 'error' AS severity,
           format('exercise %s "%s" has no primary muscle or joint', e.id, e.name) AS detail
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
    SELECT 'DQ11', 'warning', format('exercise %s "%s" is used in plans but has no relation: no substitute can be found', e.id, e.name)
      FROM exercise e
     WHERE e.is_active
       AND EXISTS (SELECT 1 FROM plan_item pi WHERE pi.exercise_id = e.id)
       AND NOT EXISTS (SELECT 1 FROM exercise_relation r
                        WHERE e.id IN (r.from_exercise_id, r.to_exercise_id))

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
    SELECT 'DQ15', 'warning', format('session %s: %s check-ins but %s participants present (K2 > 100 %%)',
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
    SELECT 'DQ17', 'warning', format('progression %s -> %s goes to an easier exercise', r.from_exercise_id, r.to_exercise_id)
      FROM exercise_relation r
      JOIN exercise a ON a.id = r.from_exercise_id
      JOIN exercise b ON b.id = r.to_exercise_id
     WHERE r.type = 'progression' AND b.difficulty < a.difficulty

    UNION ALL
    SELECT 'DQ17b', 'warning', format('variation %s -> %s is directed (expected undirected)', from_exercise_id, to_exercise_id)
      FROM exercise_relation WHERE type = 'variation' AND is_directed

    UNION ALL
    SELECT 'DQ24', 'error', format('role "%s" has no permissions', r.code)
      FROM role r
     WHERE NOT EXISTS (SELECT 1 FROM role_permission rp WHERE rp.role_id = r.id)

    UNION ALL
    SELECT 'DQ26', 'error', format('compensation loop between exercises %s and %s', a.id, b.id)
      FROM exercise a JOIN exercise b ON b.id = a.required_compensation_id
     WHERE b.required_compensation_id = a.id AND a.id < b.id

    UNION ALL
    SELECT 'DQ27', 'error', format('exercise %s requires inactive compensation %s', a.id, b.id)
      FROM exercise a JOIN exercise b ON b.id = a.required_compensation_id
     WHERE a.is_active AND NOT b.is_active

    UNION ALL
    SELECT 'DQ28', 'warning', format('exercise %s "%s" has no primary joint', e.id, e.name)
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
    -- only possible for sessions closed before migration 0005
    SELECT 'DQ32', 'warning', format('session %s is %s but %s recommendation(s) have no decision',
                                     s.id, s.status, count(r.id))
      FROM session s
      JOIN recommendation r ON r.session_id = s.id
     WHERE s.status::text IN ('reviewed', 'done')
       AND NOT EXISTS (SELECT 1 FROM recommendation_decision d WHERE d.recommendation_id = r.id)
     GROUP BY s.id

) checks
ORDER BY severity, check_id, detail;

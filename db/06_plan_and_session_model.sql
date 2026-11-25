-- =====================================================================
-- Kinetune — plan and session model
-- Applied by Alembic migration 0005 (one transaction). Manual run:
--   psql -v ON_ERROR_STOP=1 --single-transaction -f 06_plan_and_session_model.sql
--
-- Contents (data_dictionary.md §3, §4, §6, §8; data_integrity_and_transactions.md §2.7):
--   1. exercise_joint.load (load_level) next to is_primary          (BR9, BR11)
--   2. durations are calculated: exercise.rep_duration_sec,
--      plan_item.reps_count NOT NULL, plan_item.duration_sec removed (BR8)
--   3. plan.target_duration_min and plan.status (plan_status)
--   4. session_status gets 'reviewed' (open -> closed -> reviewed -> done)
--   5. item_duration_sec(), plan_is_locked(), duplicate_plan(),
--      views v_plan_item and v_session_plan
--   6. triggers: plan status order, plan lock, session only from a reviewed
--      plan, 'reviewed' only when every recommendation is decided,
--      at most one accepted replacement per plan item and session
--   7. privileges for the new objects
--
-- Works on an empty database and on a database with data: existing rows
-- are converted before the new NOT NULL / CHECK rules are added.
-- Note: the new enum value 'reviewed' cannot be used by plain SQL in the
-- same transaction that adds it, so every check that names it is PL/pgSQL
-- (parsed at run time, after this migration has committed).
-- =====================================================================

SET search_path TO kinetune;

-- ---------------------------------------------------------------------
-- 1. Enumerated types
-- ---------------------------------------------------------------------
CREATE TYPE load_level  AS ENUM ('low', 'medium', 'high');
CREATE TYPE plan_status AS ENUM ('draft', 'completed', 'reviewed');
ALTER TYPE session_status ADD VALUE IF NOT EXISTS 'reviewed' BEFORE 'done';

-- ---------------------------------------------------------------------
-- 2. Joint load level
--    Existing rows: primary joint -> 'medium', other -> 'low'. This is only
--    a starting point; the coach sets the real values in the library.
-- ---------------------------------------------------------------------
ALTER TABLE exercise_joint ADD COLUMN load load_level;
UPDATE exercise_joint SET load = CASE WHEN is_primary THEN 'medium'::load_level ELSE 'low'::load_level END;
ALTER TABLE exercise_joint ALTER COLUMN load SET NOT NULL;

-- ---------------------------------------------------------------------
-- 3. Duration of one repetition (replaces the suggested item duration)
--    Existing values are kept: one repetition = the old default duration.
-- ---------------------------------------------------------------------
ALTER TABLE exercise RENAME COLUMN default_duration_sec TO rep_duration_sec;
ALTER TABLE exercise RENAME CONSTRAINT ck_exercise_duration TO ck_exercise_rep_duration;

-- ---------------------------------------------------------------------
-- 4. Plan: target duration and status
-- ---------------------------------------------------------------------
ALTER TABLE plan
    ADD COLUMN target_duration_min smallint,
    ADD COLUMN status plan_status NOT NULL DEFAULT 'draft',
    ADD CONSTRAINT ck_plan_target_duration CHECK (target_duration_min BETWEEN 15 AND 120);

-- Existing plans that already have sessions were used in class: they become
-- 'reviewed' with the 45-minute class that BR8 assumed before this change.
UPDATE plan p
   SET target_duration_min = 45,
       status = 'reviewed'
 WHERE EXISTS (SELECT 1 FROM session s WHERE s.plan_id = p.id);

ALTER TABLE plan
    ADD CONSTRAINT ck_plan_target_when_not_draft
        CHECK (status = 'draft' OR target_duration_min IS NOT NULL);

-- ---------------------------------------------------------------------
-- 5. Plan item: repetitions instead of a stored duration
--    Existing items without repetitions become one repetition.
-- ---------------------------------------------------------------------
UPDATE plan_item SET reps_count = 1 WHERE reps_count IS NULL;
ALTER TABLE plan_item DROP COLUMN duration_sec;          -- drops ck_plan_item_duration
ALTER TABLE plan_item
    ALTER COLUMN reps_count SET DEFAULT 1,
    ALTER COLUMN reps_count SET NOT NULL;

-- ---------------------------------------------------------------------
-- 6. Functions
-- ---------------------------------------------------------------------

-- The ONLY implementation of the item duration formula. Used by both
-- views below; the backend reads durations from the views (or calls
-- this function) and never repeats the formula.
--   duration = reps_count x rep_duration_sec,
--              x 2 for an asymmetric exercise done on both sides in one item
CREATE FUNCTION item_duration_sec(p_reps_count integer, p_rep_duration_sec integer,
                                  p_is_symmetric boolean, p_side side)
RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN p_reps_count * p_rep_duration_sec
       * CASE WHEN NOT p_is_symmetric AND p_side = 'both' THEN 2 ELSE 1 END;

-- A plan is locked as soon as any session uses it (whatever its status),
-- so the plan of a past or running class never changes. DQ31.
CREATE FUNCTION plan_is_locked(p_plan_id integer)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = kinetune, pg_temp
RETURN EXISTS (SELECT 1 FROM session s WHERE s.plan_id = p_plan_id);

-- Copy a plan with all its items. The copy is a new 'draft' (no target
-- check needed) and is not locked, so the coach can edit it. Runs with the
-- caller's rights; ownership of the source plan is checked by the API.
CREATE FUNCTION duplicate_plan(p_plan_id integer, p_title text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SET search_path = kinetune, pg_temp
AS $$
DECLARE
    v_new_id integer;
BEGIN
    INSERT INTO plan (coach_id, title, notes, target_duration_min)
    SELECT p.coach_id,
           COALESCE(p_title, left(p.title, 113) || ' (copy)'),
           p.notes,
           p.target_duration_min
      FROM plan p
     WHERE p.id = p_plan_id
    RETURNING id INTO v_new_id;

    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'Plan % does not exist', p_plan_id
            USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO plan_item (plan_id, exercise_id, phase, position, side, reps_count)
    SELECT v_new_id, pi.exercise_id, pi.phase, pi.position, pi.side, pi.reps_count
      FROM plan_item pi
     WHERE pi.plan_id = p_plan_id
     ORDER BY pi.phase, pi.position;

    RETURN v_new_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 7. Views: the blueprint and the concrete plan of a session
--    Both return the same item list shape, so the backend runs the same
--    BR1–BR8 check on either. seq = 1..n over the whole plan in class order
--    (phase, position): used by BR6 ("more than 5 exercises later") and
--    BR9 ("first quarter of the class").
-- ---------------------------------------------------------------------
CREATE VIEW v_plan_item AS
SELECT pi.plan_id,
       pi.id                                                   AS plan_item_id,
       row_number() OVER (PARTITION BY pi.plan_id
                          ORDER BY pi.phase, pi.position)::integer AS seq,
       pi.phase,
       pi.position,
       pi.exercise_id,
       pi.side,
       pi.reps_count,
       item_duration_sec(pi.reps_count, e.rep_duration_sec, e.is_symmetric, pi.side) AS duration_sec
  FROM plan_item pi
  JOIN exercise e ON e.id = pi.exercise_id;

CREATE VIEW v_session_plan AS
SELECT s.id                                                    AS session_id,
       s.plan_id,
       pi.id                                                   AS plan_item_id,
       row_number() OVER (PARTITION BY s.id
                          ORDER BY pi.phase, pi.position)::integer AS seq,
       pi.phase,
       pi.position,
       pi.exercise_id                                          AS original_exercise_id,
       COALESCE(rep.candidate_exercise_id, pi.exercise_id)     AS exercise_id,
       rep.recommendation_id                                   AS replacement_recommendation_id,
       COALESCE(alt.exercise_ids, '{}')                        AS alternative_exercise_ids,
       pi.side,
       pi.reps_count,
       item_duration_sec(pi.reps_count, e.rep_duration_sec, e.is_symmetric, pi.side) AS duration_sec
  FROM session s
  JOIN plan_item pi ON pi.plan_id = s.plan_id
  -- accepted replacement (BR10): swaps the exercise of this item;
  -- at most one per item and session (trg_decision_single_replacement, DQ33)
  LEFT JOIN LATERAL (
        SELECT r.id AS recommendation_id, r.candidate_exercise_id
          FROM recommendation r
          JOIN recommendation_decision d ON d.recommendation_id = r.id
         WHERE r.session_id = s.id
           AND r.plan_item_id = pi.id
           AND r.form = 'replacement'
           AND NOT r.is_warning
           AND d.decision = 'accepted'
  ) rep ON true
  -- accepted alternatives (BR9): shown next to the original, the item keeps its exercise
  LEFT JOIN LATERAL (
        SELECT array_agg(r.candidate_exercise_id ORDER BY r.id) AS exercise_ids
          FROM recommendation r
          JOIN recommendation_decision d ON d.recommendation_id = r.id
         WHERE r.session_id = s.id
           AND r.plan_item_id = pi.id
           AND r.form = 'alternative'
           AND NOT r.is_warning
           AND d.decision = 'accepted'
  ) alt ON true
  -- warnings (BR11) change nothing; the duration is that of the effective exercise
  JOIN exercise e ON e.id = COALESCE(rep.candidate_exercise_id, pi.exercise_id);

-- ---------------------------------------------------------------------
-- 8. Triggers
-- ---------------------------------------------------------------------

-- DQ29, DQ31: plan status order and the lock on plan-level columns.
--   A new plan starts as 'draft'. Allowed: draft -> completed -> reviewed,
--   and back to 'draft' from any status (the coach reopens the plan).
--   Changing target_duration_min of a 'completed'/'reviewed' plan moves it
--   back to 'draft' (the check has to be run again).
--   A locked plan (used by a session) keeps its status and target.
CREATE FUNCTION fn_plan_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = kinetune, pg_temp
AS $$
DECLARE
    v_target_changed boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'draft' THEN
            RAISE EXCEPTION 'A new plan must start with status draft'
                USING ERRCODE = 'P0001', HINT = 'DQ29';
        END IF;
        RETURN NEW;
    END IF;

    v_target_changed := NEW.target_duration_min IS DISTINCT FROM OLD.target_duration_min;

    IF NOT v_target_changed AND NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF plan_is_locked(OLD.id) THEN
        RAISE EXCEPTION 'Plan % is used by a session and cannot be changed; duplicate it instead', OLD.id
            USING ERRCODE = 'P0001', HINT = 'DQ31';
    END IF;

    IF v_target_changed AND OLD.status <> 'draft' THEN
        NEW.status := 'draft';
        RETURN NEW;
    END IF;

    IF NEW.status <> OLD.status
       AND NEW.status <> 'draft'
       AND (OLD.status, NEW.status) NOT IN (('draft'::plan_status,     'completed'::plan_status),
                                            ('completed'::plan_status, 'reviewed'::plan_status)) THEN
        RAISE EXCEPTION 'Plan status cannot change from % to %', OLD.status, NEW.status
            USING ERRCODE = 'P0001', HINT = 'DQ29';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_plan_status
    BEFORE INSERT OR UPDATE OF status, target_duration_min ON plan
    FOR EACH ROW EXECUTE FUNCTION fn_plan_status();

-- DQ29, DQ31: any change to the items of a plan
--   - is rejected if the plan is locked (used by a session);
--   - otherwise moves a 'completed'/'reviewed' plan back to 'draft'.
-- The plan row is locked FOR UPDATE, so an item change and the creation
-- of a session for the same plan wait for each other (see §3.4).
CREATE FUNCTION fn_plan_item_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = kinetune, pg_temp
AS $$
DECLARE
    v_plan_id integer;
    v_status  plan_status;
BEGIN
    FOREACH v_plan_id IN ARRAY
        CASE TG_OP WHEN 'INSERT' THEN ARRAY[NEW.plan_id]
                   WHEN 'DELETE' THEN ARRAY[OLD.plan_id]
                   ELSE ARRAY(SELECT DISTINCT unnest(ARRAY[OLD.plan_id, NEW.plan_id])) END
    LOOP
        SELECT p.status INTO v_status FROM plan p WHERE p.id = v_plan_id FOR UPDATE;
        IF NOT FOUND THEN
            CONTINUE;          -- the plan itself is being deleted (cascade)
        END IF;
        IF plan_is_locked(v_plan_id) THEN
            RAISE EXCEPTION 'Plan % is used by a session and cannot be changed; duplicate it instead', v_plan_id
                USING ERRCODE = 'P0001', HINT = 'DQ31';
        END IF;
        IF v_status <> 'draft' THEN
            UPDATE plan SET status = 'draft' WHERE id = v_plan_id;
        END IF;
    END LOOP;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER trg_plan_item_guard
    BEFORE INSERT OR UPDATE OR DELETE ON plan_item
    FOR EACH ROW EXECUTE FUNCTION fn_plan_item_guard();

-- DQ30: a session is created only from a 'reviewed' plan.
-- FOR SHARE on the plan row: see fn_plan_item_guard.
CREATE FUNCTION fn_session_plan_reviewed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = kinetune, pg_temp
AS $$
DECLARE
    v_status plan_status;
BEGIN
    SELECT p.status INTO v_status FROM plan p WHERE p.id = NEW.plan_id FOR SHARE;
    IF v_status IS DISTINCT FROM 'reviewed' THEN
        RAISE EXCEPTION 'Plan % has status %; a session can be created only from a reviewed plan',
                        NEW.plan_id, coalesce(v_status::text, 'unknown')
            USING ERRCODE = 'P0001', HINT = 'DQ30';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_session_plan_reviewed
    BEFORE INSERT OR UPDATE OF plan_id ON session
    FOR EACH ROW EXECUTE FUNCTION fn_session_plan_reviewed();

-- DQ04, DQ32: session status moves only forward
--   open -> closed -> reviewed -> done;
-- 'reviewed' only when every recommendation of the session has a decision
-- (allowed at once when there are no recommendations);
-- checkin_closed_at is set automatically when the check-in is closed.
-- Replaces the function from 02_triggers.sql (same trigger, same rights).
CREATE OR REPLACE FUNCTION fn_session_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = kinetune, pg_temp
AS $$
DECLARE
    v_undecided integer;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'open' THEN
            RAISE EXCEPTION 'A new session must start with status open'
                USING ERRCODE = 'P0001', HINT = 'DQ04';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF (OLD.status::text, NEW.status::text) NOT IN (('open',     'closed'),
                                                    ('closed',   'reviewed'),
                                                    ('reviewed', 'done')) THEN
        RAISE EXCEPTION 'Session status cannot change from % to %', OLD.status, NEW.status
            USING ERRCODE = 'P0001', HINT = 'DQ04';
    END IF;

    IF NEW.status::text = 'reviewed' THEN
        SELECT count(*) INTO v_undecided
          FROM recommendation r
         WHERE r.session_id = NEW.id
           AND NOT EXISTS (SELECT 1 FROM recommendation_decision d WHERE d.recommendation_id = r.id);
        IF v_undecided > 0 THEN
            RAISE EXCEPTION 'Session % has % recommendation(s) without a decision', NEW.id, v_undecided
                USING ERRCODE = 'P0001', HINT = 'DQ32';
        END IF;
    END IF;

    IF OLD.status = 'open' THEN
        NEW.checkin_closed_at := now();
    END IF;
    RETURN NEW;
END;
$$;

-- DQ33: at most one accepted replacement per plan item and session, so the
-- concrete plan (v_session_plan) has exactly one exercise per item.
-- The plan item row is locked, so two accepts for the same item wait for
-- each other instead of both succeeding.
CREATE FUNCTION fn_decision_single_replacement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = kinetune, pg_temp
AS $$
DECLARE
    v_session_id integer;
    v_item_id    integer;
    v_form       recommendation_form;
    v_is_warning boolean;
BEGIN
    IF NEW.decision <> 'accepted' THEN
        RETURN NEW;
    END IF;

    SELECT r.session_id, r.plan_item_id, r.form, r.is_warning
      INTO v_session_id, v_item_id, v_form, v_is_warning
      FROM recommendation r
     WHERE r.id = NEW.recommendation_id;

    IF v_form <> 'replacement' OR v_is_warning THEN
        RETURN NEW;
    END IF;

    PERFORM 1 FROM plan_item pi WHERE pi.id = v_item_id FOR NO KEY UPDATE;

    IF EXISTS (SELECT 1
                 FROM recommendation r
                 JOIN recommendation_decision d ON d.recommendation_id = r.id
                WHERE r.session_id   = v_session_id
                  AND r.plan_item_id = v_item_id
                  AND r.form = 'replacement'
                  AND NOT r.is_warning
                  AND d.decision = 'accepted'
                  AND r.id <> NEW.recommendation_id) THEN
        RAISE EXCEPTION 'Plan item % already has an accepted replacement in session %', v_item_id, v_session_id
            USING ERRCODE = 'P0001', HINT = 'DQ33';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_decision_single_replacement
    BEFORE INSERT OR UPDATE OF decision ON recommendation_decision
    FOR EACH ROW EXECUTE FUNCTION fn_decision_single_replacement();

-- ---------------------------------------------------------------------
-- 9. Comments
-- ---------------------------------------------------------------------
COMMENT ON TYPE load_level  IS 'How much an exercise loads a joint (BR9, BR11); expert estimate of the coach';
COMMENT ON TYPE plan_status IS 'draft -> completed -> reviewed; any change of a plan moves it back to draft';

COMMENT ON TABLE plan IS 'Plan blueprint built by the coach; checked by BR1–BR8 and reviewed before use';
COMMENT ON TABLE session IS 'One class: a reviewed plan + decisions on recommendations + time, group, check-ins, attendance';

COMMENT ON COLUMN exercise.rep_duration_sec    IS 'Seconds for ONE repetition; for a static exercise one repetition = one hold';
COMMENT ON COLUMN exercise_joint.is_primary    IS 'Main joint of the exercise (what it is about); used for sorting, filtering, display';
COMMENT ON COLUMN exercise_joint.load          IS 'Load on this joint: BR9 (medium/high triggers) and BR11 (candidate must have a lower load or not use the joint)';
COMMENT ON COLUMN plan.target_duration_min     IS 'Planned class length in minutes (BR8: calculated duration within ±5 min); required unless draft';
COMMENT ON COLUMN plan.status                  IS 'draft / completed / reviewed (BR1–BR8 check run and reviewed by the coach)';
COMMENT ON COLUMN plan_item.reps_count         IS 'Repetitions (per side if side is left/right); item duration is calculated, see item_duration_sec()';
COMMENT ON COLUMN session.status               IS 'open -> closed -> reviewed (every recommendation decided, concrete plan re-checked) -> done';

COMMENT ON FUNCTION item_duration_sec(integer, integer, boolean, side) IS
    'Item duration in seconds: reps x rep duration, x2 for an asymmetric exercise with side both';
COMMENT ON FUNCTION plan_is_locked(integer) IS
    'true when any session uses the plan: its items, status and target can no longer change';
COMMENT ON FUNCTION duplicate_plan(integer, text) IS
    'Copies a plan and its items into a new draft plan; returns the new plan id';
COMMENT ON VIEW v_plan_item IS
    'Blueprint item list in class order with calculated duration; input of the BR1–BR8 plan check';
COMMENT ON VIEW v_session_plan IS
    'Concrete plan of a session: blueprint + accepted replacements (swap) and alternatives (next to the original); input of the BR1–BR8 session check';

-- ---------------------------------------------------------------------
-- 10. Privileges (data_dictionary.md §4; README "Roles and access")
--     Views: SELECT for app_read also comes from default privileges;
--     stated explicitly here. New functions: EXECUTE is never PUBLIC.
-- ---------------------------------------------------------------------
GRANT UPDATE (target_duration_min, status) ON plan TO app_write;
-- plan_item: the column grant on duration_sec went away with the column;
-- reps_count was already granted (04_roles_privileges.sql)

GRANT SELECT ON v_plan_item, v_session_plan TO app_read;

REVOKE EXECUTE ON FUNCTION item_duration_sec(integer, integer, boolean, side),
                           plan_is_locked(integer),
                           duplicate_plan(integer, text),
                           fn_plan_status(), fn_plan_item_guard(),
                           fn_session_plan_reviewed(), fn_decision_single_replacement()
       FROM PUBLIC;
GRANT EXECUTE ON FUNCTION item_duration_sec(integer, integer, boolean, side) TO app_read;
GRANT EXECUTE ON FUNCTION plan_is_locked(integer)                             TO app_read;
GRANT EXECUTE ON FUNCTION duplicate_plan(integer, text)                       TO app_write;

-- =====================================================================
-- Kinetune — database structure (DDL)
-- File 2 of 2: functions and triggers for cross-table business rules,
-- functions and views for calculated data (item duration, plan lock,
-- duplicate_plan, v_plan_item, v_session_plan)
-- Rule IDs (DQ..) refer to data_dictionary.md §6; calculated data: §7;
-- design and concurrency notes: data_integrity_and_transactions.md §2.3, §2.7, §3.4
-- Normally applied by Alembic migration 0001, after 01_schema.sql.
-- Rights: 04_roles_privileges.sql (migration 0003) makes the trigger
-- functions SECURITY DEFINER with a fixed search_path and grants EXECUTE.
-- Manual run:  psql -v ON_ERROR_STOP=1 --single-transaction -f 02_triggers.sql
-- =====================================================================


SET search_path TO kinetune;

-- ---------------------------------------------------------------------
-- Helper: does a user hold a given application role (and is active)?
-- ---------------------------------------------------------------------
CREATE FUNCTION has_role(p_user_id integer, p_role_code text)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM user_role ur
          JOIN role r      ON r.id = ur.role_id
          JOIN app_user u  ON u.id = ur.user_id
         WHERE ur.user_id = p_user_id
           AND r.code     = p_role_code
           AND u.is_active
    );
$$;

-- ---------------------------------------------------------------------
-- DQ03: check-ins are accepted only while the session is open.
-- FOR SHARE on the session row serialises a check-in with the coach
-- closing the session (UPDATE needs a stronger lock), so a check-in
-- can never slip in after recommendations were calculated.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_checkin_session_open()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id integer;
    v_status     session_status;
BEGIN
    IF TG_TABLE_NAME = 'checkin' THEN
        v_session_id := NEW.session_id;
    ELSE  -- checkin_discomfort
        SELECT c.session_id INTO v_session_id FROM checkin c WHERE c.id = NEW.checkin_id;
    END IF;

    SELECT s.status INTO v_status
      FROM session s
     WHERE s.id = v_session_id
       FOR SHARE;

    IF v_status IS DISTINCT FROM 'open' THEN
        RAISE EXCEPTION 'Check-in for session % is closed', v_session_id
            USING ERRCODE = 'P0001', HINT = 'DQ03';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_checkin_session_open
    BEFORE INSERT ON checkin
    FOR EACH ROW EXECUTE FUNCTION fn_checkin_session_open();

CREATE TRIGGER trg_checkin_discomfort_session_open
    BEFORE INSERT ON checkin_discomfort
    FOR EACH ROW EXECUTE FUNCTION fn_checkin_session_open();

-- ---------------------------------------------------------------------
-- Feedback is accepted only after the check-in was closed.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_feedback_session_closed()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (SELECT s.status FROM session s WHERE s.id = NEW.session_id) = 'open' THEN
        RAISE EXCEPTION 'Feedback for session % is not open yet', NEW.session_id
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_feedback_session_closed
    BEFORE INSERT ON feedback
    FOR EACH ROW EXECUTE FUNCTION fn_feedback_session_closed();

-- ---------------------------------------------------------------------
-- DQ04, DQ32: session status moves only forward
--   open -> closed -> reviewed -> done;
-- 'reviewed' only when every recommendation of the session has a decision
-- (allowed at once when there are no recommendations);
-- checkin_closed_at is set automatically when the check-in is closed.
-- participants_present is required from 'closed' on (CHECK, DQ05).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_session_status()
RETURNS trigger
LANGUAGE plpgsql
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

    IF (OLD.status, NEW.status) NOT IN (('open'::session_status,     'closed'::session_status),
                                        ('closed'::session_status,   'reviewed'::session_status),
                                        ('reviewed'::session_status, 'done'::session_status)) THEN
        RAISE EXCEPTION 'Session status cannot change from % to %', OLD.status, NEW.status
            USING ERRCODE = 'P0001', HINT = 'DQ04';
    END IF;

    IF NEW.status = 'reviewed' THEN
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

CREATE TRIGGER trg_session_status
    BEFORE INSERT OR UPDATE OF status ON session
    FOR EACH ROW EXECUTE FUNCTION fn_session_status();

-- ---------------------------------------------------------------------
-- DQ08, DQ21: a session's coach owns the plan and holds the coach role.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_session_owner()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT has_role(NEW.coach_id, 'coach') THEN
        RAISE EXCEPTION 'User % does not hold the coach role', NEW.coach_id
            USING ERRCODE = 'P0001', HINT = 'DQ21';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM plan p WHERE p.id = NEW.plan_id AND p.coach_id = NEW.coach_id) THEN
        RAISE EXCEPTION 'Plan % does not belong to coach %', NEW.plan_id, NEW.coach_id
            USING ERRCODE = 'P0001', HINT = 'DQ08';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_session_owner
    BEFORE INSERT OR UPDATE OF coach_id, plan_id ON session
    FOR EACH ROW EXECUTE FUNCTION fn_session_owner();

-- ---------------------------------------------------------------------
-- DQ30: a session is created only from a 'reviewed' plan.
-- FOR SHARE on the plan row: an item change of the same plan (which locks
-- it FOR UPDATE, see fn_plan_item_guard) and the new session wait for
-- each other (data_integrity_and_transactions.md §3.4).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_session_plan_reviewed()
RETURNS trigger
LANGUAGE plpgsql
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

-- ---------------------------------------------------------------------
-- DQ21: a plan's owner holds the coach role.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_plan_owner()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT has_role(NEW.coach_id, 'coach') THEN
        RAISE EXCEPTION 'User % does not hold the coach role', NEW.coach_id
            USING ERRCODE = 'P0001', HINT = 'DQ21';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_plan_owner
    BEFORE INSERT OR UPDATE OF coach_id ON plan
    FOR EACH ROW EXECUTE FUNCTION fn_plan_owner();

-- ---------------------------------------------------------------------
-- plan.updated_at is maintained automatically (used for optimistic
-- locking when the plan is saved, see T5).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_plan_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_plan_set_updated_at
    BEFORE UPDATE ON plan
    FOR EACH ROW EXECUTE FUNCTION fn_plan_set_updated_at();

CREATE FUNCTION fn_plan_touch_from_item()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE plan SET updated_at = now()
     WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.plan_id ELSE NEW.plan_id END;
    RETURN NULL;   -- AFTER trigger: return value ignored
END;
$$;

CREATE TRIGGER trg_plan_touch_from_item
    AFTER INSERT OR UPDATE OR DELETE ON plan_item
    FOR EACH ROW EXECUTE FUNCTION fn_plan_touch_from_item();

-- ---------------------------------------------------------------------
-- Plan lock (DQ31): a plan is locked as soon as any session uses it,
-- whatever the session's status, so the plan of a past or running class
-- never changes. Calculated, not stored.
-- ---------------------------------------------------------------------
CREATE FUNCTION plan_is_locked(p_plan_id integer)
RETURNS boolean
LANGUAGE sql STABLE
RETURN EXISTS (SELECT 1 FROM session s WHERE s.plan_id = p_plan_id);

-- ---------------------------------------------------------------------
-- DQ29, DQ31: plan status and the lock on plan fields.
--   A new plan starts as 'draft'.
--   Any change of a plan field (coach, title, notes, target duration)
--   moves the plan back to 'draft' — also when the same statement sets
--   another status: the check has to be run again.
--   A status change on its own follows draft -> completed -> reviewed,
--   or goes back to 'draft' from any status.
--   A locked plan (used by a session) cannot change at all; updated_at
--   alone is not a change (it is touched by the item triggers).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_plan_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_fields_changed boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'draft' THEN
            RAISE EXCEPTION 'A new plan must start with status draft'
                USING ERRCODE = 'P0001', HINT = 'DQ29';
        END IF;
        RETURN NEW;
    END IF;

    v_fields_changed := (NEW.coach_id, NEW.title, NEW.notes, NEW.target_duration_min)
                        IS DISTINCT FROM
                        (OLD.coach_id, OLD.title, OLD.notes, OLD.target_duration_min);

    IF NOT v_fields_changed AND NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF plan_is_locked(OLD.id) THEN
        RAISE EXCEPTION 'Plan % is used by a session and cannot be changed; duplicate it instead', OLD.id
            USING ERRCODE = 'P0001', HINT = 'DQ31';
    END IF;

    IF v_fields_changed THEN
        NEW.status := 'draft';
        RETURN NEW;
    END IF;

    IF NEW.status <> 'draft'
       AND (OLD.status, NEW.status) NOT IN (('draft'::plan_status,     'completed'::plan_status),
                                            ('completed'::plan_status, 'reviewed'::plan_status)) THEN
        RAISE EXCEPTION 'Plan status cannot change from % to %', OLD.status, NEW.status
            USING ERRCODE = 'P0001', HINT = 'DQ29';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_plan_status
    BEFORE INSERT OR UPDATE ON plan
    FOR EACH ROW EXECUTE FUNCTION fn_plan_status();

-- ---------------------------------------------------------------------
-- DQ29, DQ31: any change to the items of a plan
--   - is rejected if the plan is locked (used by a session);
--   - otherwise moves a 'completed' / 'reviewed' plan back to 'draft'.
-- The plan row is locked FOR UPDATE, so an item change and the creation
-- of a session for the same plan wait for each other (§3.4).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_plan_item_guard()
RETURNS trigger
LANGUAGE plpgsql
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

-- ---------------------------------------------------------------------
-- DQ25: a plan item of a symmetric exercise has side = 'both'.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_plan_item_side()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.side <> 'both'
       AND (SELECT e.is_symmetric FROM exercise e WHERE e.id = NEW.exercise_id) THEN
        RAISE EXCEPTION 'Exercise % is symmetric: side must be both', NEW.exercise_id
            USING ERRCODE = 'P0001', HINT = 'DQ25';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_plan_item_side
    BEFORE INSERT OR UPDATE OF exercise_id, side ON plan_item
    FOR EACH ROW EXECUTE FUNCTION fn_plan_item_side();

-- ---------------------------------------------------------------------
-- DQ01, DQ02: a recommendation's plan item belongs to the session's
-- plan, and the candidate differs from the exercise it replaces.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_recommendation_consistency()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_item_plan_id    integer;
    v_item_exercise   integer;
    v_session_plan_id integer;
BEGIN
    SELECT pi.plan_id, pi.exercise_id INTO v_item_plan_id, v_item_exercise
      FROM plan_item pi WHERE pi.id = NEW.plan_item_id;
    SELECT s.plan_id INTO v_session_plan_id
      FROM session s WHERE s.id = NEW.session_id;

    IF v_item_plan_id IS DISTINCT FROM v_session_plan_id THEN
        RAISE EXCEPTION 'Plan item % is not part of the plan of session %',
                        NEW.plan_item_id, NEW.session_id
            USING ERRCODE = 'P0001', HINT = 'DQ01';
    END IF;
    IF NEW.candidate_exercise_id = v_item_exercise THEN
        RAISE EXCEPTION 'Candidate exercise % is the same as the original', NEW.candidate_exercise_id
            USING ERRCODE = 'P0001', HINT = 'DQ02';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_recommendation_consistency
    BEFORE INSERT OR UPDATE OF session_id, plan_item_id, candidate_exercise_id ON recommendation
    FOR EACH ROW EXECUTE FUNCTION fn_recommendation_consistency();

-- ---------------------------------------------------------------------
-- DQ07: a decision is not earlier than its recommendation.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_decision_time()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.decided_at < (SELECT r.created_at FROM recommendation r WHERE r.id = NEW.recommendation_id) THEN
        RAISE EXCEPTION 'Decision time is earlier than the recommendation'
            USING ERRCODE = 'P0001', HINT = 'DQ07';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_decision_time
    BEFORE INSERT OR UPDATE OF decided_at ON recommendation_decision
    FOR EACH ROW EXECUTE FUNCTION fn_decision_time();

-- ---------------------------------------------------------------------
-- DQ33: at most one accepted replacement per plan item and session, so
-- the concrete plan (v_session_plan) has exactly one exercise per item.
-- The plan item row is locked, so two accepts for the same item wait for
-- each other instead of both succeeding.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_decision_single_replacement()
RETURNS trigger
LANGUAGE plpgsql
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
-- DQ22: at least one active admin always exists.
-- All admin assignments are locked FOR UPDATE first, so two concurrent
-- revocations wait for each other instead of both succeeding.
-- Also fires on cascaded deletes when a user is deleted.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_last_admin()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_role smallint;
    v_user_id    integer;
    v_others     integer;
BEGIN
    SELECT id INTO v_admin_role FROM role WHERE code = 'admin';

    IF TG_TABLE_NAME = 'user_role' THEN
        IF OLD.role_id IS DISTINCT FROM v_admin_role THEN
            RETURN OLD;                       -- not an admin assignment
        END IF;
        v_user_id := OLD.user_id;
    ELSE  -- app_user: deactivation
        IF NOT (OLD.is_active AND NOT NEW.is_active) THEN
            RETURN NEW;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM user_role
                        WHERE user_id = OLD.id AND role_id = v_admin_role) THEN
            RETURN NEW;                       -- not an admin
        END IF;
        v_user_id := OLD.id;
    END IF;

    PERFORM 1 FROM user_role WHERE role_id = v_admin_role FOR UPDATE;

    SELECT count(*) INTO v_others
      FROM user_role ur
      JOIN app_user u ON u.id = ur.user_id
     WHERE ur.role_id = v_admin_role
       AND u.is_active
       AND ur.user_id <> v_user_id;

    IF v_others = 0 THEN
        RAISE EXCEPTION 'Cannot remove the last active admin'
            USING ERRCODE = 'P0001', HINT = 'DQ22';
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER trg_last_admin_role
    BEFORE DELETE ON user_role
    FOR EACH ROW EXECUTE FUNCTION fn_last_admin();

CREATE TRIGGER trg_last_admin_deactivate
    BEFORE UPDATE OF is_active ON app_user
    FOR EACH ROW EXECUTE FUNCTION fn_last_admin();

-- ---------------------------------------------------------------------
-- DQ23: a role can be granted only by an admin (granted_by NULL = seed).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_granted_by_admin()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.granted_by IS NOT NULL AND NOT has_role(NEW.granted_by, 'admin') THEN
        RAISE EXCEPTION 'User % is not an admin and cannot grant roles', NEW.granted_by
            USING ERRCODE = 'P0001', HINT = 'DQ23';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_granted_by_admin
    BEFORE INSERT OR UPDATE OF granted_by ON user_role
    FOR EACH ROW EXECUTE FUNCTION fn_granted_by_admin();

-- =====================================================================
-- Calculated data: item duration, plan copy, blueprint and concrete plan
-- (data_dictionary.md §7). Derived values are calculated when read,
-- not stored; each formula exists once, here.
-- =====================================================================

-- The ONLY implementation of the item duration formula (BR8). Used by both
-- views below; the backend reads durations from the views (or calls this
-- function) and never repeats the formula.
--   duration = reps_count x rep_duration_sec,
--              x 2 for an asymmetric exercise done on both sides in one item
CREATE FUNCTION item_duration_sec(p_reps_count integer, p_rep_duration_sec integer,
                                  p_is_symmetric boolean, p_side side)
RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN p_reps_count * p_rep_duration_sec
       * CASE WHEN NOT p_is_symmetric AND p_side = 'both' THEN 2 ELSE 1 END;

-- Copy a plan with all its items (T9). The copy is a new 'draft' without
-- sessions, so it is not locked and the coach can edit it. Runs with the
-- caller's rights; ownership of the source plan is checked by the API.
CREATE FUNCTION duplicate_plan(p_plan_id integer, p_title text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
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
-- Views: the blueprint and the concrete plan of a session.
-- Both return the same item list shape, so the backend runs the same
-- BR1–BR8 check on either. seq = 1..n over the whole plan in class order
-- (phase, position): used by BR6 ("more than five exercises later").
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
       COALESCE(rep.candidate_exercise_id, pi.exercise_id)     AS exercise_id,
       pi.exercise_id                                          AS original_exercise_id,
       (rep.recommendation_id IS NOT NULL)                     AS is_replaced,
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

COMMENT ON FUNCTION item_duration_sec(integer, integer, boolean, side) IS
    'Item duration in seconds: reps x rep duration, x2 for an asymmetric exercise with side both';
COMMENT ON FUNCTION plan_is_locked(integer) IS
    'true when any session uses the plan: its items and fields can no longer change';
COMMENT ON FUNCTION duplicate_plan(integer, text) IS
    'Copies a plan and its items into a new draft plan; returns the new plan id';
COMMENT ON VIEW v_plan_item IS
    'Blueprint item list in class order with calculated duration; input of the BR1–BR8 plan check';
COMMENT ON VIEW v_session_plan IS
    'Concrete plan of a session: blueprint + accepted replacements (swap) and alternatives (next to the original); input of the BR1–BR8 session check';

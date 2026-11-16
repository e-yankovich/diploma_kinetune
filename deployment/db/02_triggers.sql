-- =====================================================================
-- Kinetune — database structure (DDL)
-- File 2 of 2: functions and triggers for cross-table business rules
-- Rule IDs (DQ..) refer to data_dictionary.md §6;
-- design and concurrency notes: data_integrity_and_transactions.md §2.3, §3.4
-- Normally applied by Alembic migration 0001, after 01_schema.sql.
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
-- DQ04: session status moves only forward (open -> closed -> done);
-- checkin_closed_at is set automatically when the check-in is closed.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_session_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
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

    IF (OLD.status, NEW.status) NOT IN (('open'::session_status,   'closed'::session_status),
                                        ('closed'::session_status, 'done'::session_status)) THEN
        RAISE EXCEPTION 'Session status cannot change from % to %', OLD.status, NEW.status
            USING ERRCODE = 'P0001', HINT = 'DQ04';
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

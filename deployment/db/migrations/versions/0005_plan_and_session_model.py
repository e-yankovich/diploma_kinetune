"""Plan and session model: joint load level, calculated durations, plan status and target duration, session status 'reviewed', plan lock, v_plan_item / v_session_plan, duplicate_plan()

Revision ID: 0005
Revises: 0004
Create Date: 2026-11-23

The downgrade loses information that the old schema cannot hold:
- exercise_joint.load, plan.status and plan.target_duration_min are dropped;
- plan_item.duration_sec is restored as the calculated duration;
  reps_count stays filled (it was NULL for holds before);
- exercise.rep_duration_sec is renamed back to default_duration_sec as is;
- sessions in status 'reviewed' go back to 'closed'.
"""
from pathlib import Path

from alembic import context, op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None

SQL_DIR = Path(__file__).resolve().parents[2]  # db/


def _run_sql_file(name: str) -> None:
    sql = (SQL_DIR / name).read_text(encoding="utf-8")
    if context.is_offline_mode():
        op.execute(sql)
        return
    op.get_bind().connection.driver_connection.execute(sql)


def _run_sql(sql: str) -> None:
    # same as _run_sql_file: no parameter parsing, so ':=' and '%' are safe
    if context.is_offline_mode():
        op.execute(sql)
        return
    op.get_bind().connection.driver_connection.execute(sql)


def upgrade() -> None:
    _run_sql_file("06_plan_and_session_model.sql")


def downgrade() -> None:
    _run_sql("""
        SET LOCAL search_path TO kinetune;

        -- views and functions
        DROP VIEW v_session_plan;
        DROP VIEW v_plan_item;
        DROP FUNCTION duplicate_plan(integer, text);

        -- triggers added by 0005
        DROP TRIGGER trg_decision_single_replacement ON recommendation_decision;
        DROP TRIGGER trg_session_plan_reviewed       ON session;
        DROP TRIGGER trg_plan_item_guard             ON plan_item;
        DROP TRIGGER trg_plan_status                 ON plan;
        DROP FUNCTION fn_decision_single_replacement();
        DROP FUNCTION fn_session_plan_reviewed();
        DROP FUNCTION fn_plan_item_guard();
        DROP FUNCTION fn_plan_status();
        DROP FUNCTION plan_is_locked(integer);

        -- session status: remove 'reviewed' (an enum value cannot be dropped,
        -- so the type is recreated); 'reviewed' sessions go back to 'closed'
        -- the trigger (UPDATE OF status) blocks the column type change;
        -- it is recreated below with the 0001 function
        DROP TRIGGER trg_session_status ON session;
        UPDATE session SET status = 'closed' WHERE status = 'reviewed';

        ALTER TABLE session DROP CONSTRAINT ck_session_closed_at;
        ALTER TABLE session DROP CONSTRAINT ck_session_present_when_done;
        ALTER TABLE session ALTER COLUMN status DROP DEFAULT;
        ALTER TYPE session_status RENAME TO session_status_0005;
        CREATE TYPE session_status AS ENUM ('open', 'closed', 'done');
        ALTER TABLE session ALTER COLUMN status TYPE session_status USING status::text::session_status;
        ALTER TABLE session ALTER COLUMN status SET DEFAULT 'open';
        DROP TYPE session_status_0005;
        ALTER TABLE session
            ADD CONSTRAINT ck_session_closed_at CHECK ((status = 'open') = (checkin_closed_at IS NULL)),
            ADD CONSTRAINT ck_session_present_when_done
                CHECK (status <> 'done' OR participants_present IS NOT NULL);
        COMMENT ON COLUMN session.status IS NULL;
        COMMENT ON TABLE session IS 'One class held with a plan; owns the check-in link';
    """)

    # fn_session_status as defined in 02_triggers.sql (+ rights from 04)
    _run_sql("""
        SET LOCAL search_path TO kinetune;

        CREATE OR REPLACE FUNCTION fn_session_status()
        RETURNS trigger
        LANGUAGE plpgsql
        SECURITY DEFINER SET search_path = kinetune, pg_temp
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
    """)

    _run_sql("""
        SET LOCAL search_path TO kinetune;

        -- plan_item: stored duration back (calculated with the 0005 formula)
        ALTER TABLE plan_item ADD COLUMN duration_sec integer;
        UPDATE plan_item pi
           SET duration_sec = item_duration_sec(pi.reps_count, e.rep_duration_sec, e.is_symmetric, pi.side)
          FROM exercise e
         WHERE e.id = pi.exercise_id;
        ALTER TABLE plan_item
            ALTER COLUMN duration_sec SET NOT NULL,
            ADD CONSTRAINT ck_plan_item_duration CHECK (duration_sec > 0),
            ALTER COLUMN reps_count DROP NOT NULL,
            ALTER COLUMN reps_count DROP DEFAULT;
        COMMENT ON COLUMN plan_item.reps_count IS NULL;
        GRANT UPDATE (duration_sec) ON plan_item TO app_write;
        DROP FUNCTION item_duration_sec(integer, integer, boolean, side);

        -- plan
        ALTER TABLE plan DROP COLUMN status, DROP COLUMN target_duration_min;
        DROP TYPE plan_status;
        COMMENT ON TABLE plan IS 'Reusable class plan (template)';

        -- exercise
        ALTER TABLE exercise RENAME CONSTRAINT ck_exercise_rep_duration TO ck_exercise_duration;
        ALTER TABLE exercise RENAME COLUMN rep_duration_sec TO default_duration_sec;
        COMMENT ON COLUMN exercise.default_duration_sec IS NULL;

        -- exercise_joint
        ALTER TABLE exercise_joint DROP COLUMN load;
        DROP TYPE load_level;
        COMMENT ON COLUMN exercise_joint.is_primary IS NULL;
    """)

"""Database roles app_read / app_write / app_admin, privileges, default privileges, SECURITY DEFINER triggers

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-16

Every later migration that creates a table must also grant write access
explicitly if the backend needs it (SELECT for app_read is automatic via
default privileges). tests/privileges_test.sql checks this.
"""
from pathlib import Path

from alembic import context, op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

SQL_DIR = Path(__file__).resolve().parents[2]  # db/

TRIGGER_FUNCTIONS = [
    "fn_checkin_session_open", "fn_feedback_session_closed", "fn_session_status",
    "fn_session_owner", "fn_plan_owner", "fn_plan_set_updated_at",
    "fn_plan_touch_from_item", "fn_plan_item_side", "fn_recommendation_consistency",
    "fn_decision_time", "fn_last_admin", "fn_granted_by_admin",
]


def _run_sql_file(name: str) -> None:
    sql = (SQL_DIR / name).read_text(encoding="utf-8")
    if context.is_offline_mode():
        op.execute(sql)
        return
    op.get_bind().connection.driver_connection.execute(sql)


def upgrade() -> None:
    _run_sql_file("04_roles_privileges.sql")


def downgrade() -> None:
    functions = "\n".join(
        f"ALTER FUNCTION kinetune.{fn}() SECURITY INVOKER RESET search_path;"
        for fn in TRIGGER_FUNCTIONS
    )
    op.execute(f"""
        {functions}
        ALTER FUNCTION kinetune.has_role(integer, text) RESET search_path;

        ALTER DEFAULT PRIVILEGES IN SCHEMA kinetune REVOKE SELECT ON TABLES    FROM app_read;
        ALTER DEFAULT PRIVILEGES IN SCHEMA kinetune REVOKE USAGE  ON SEQUENCES FROM app_write;
        ALTER DEFAULT PRIVILEGES IN SCHEMA kinetune GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

        REVOKE ALL ON ALL TABLES    IN SCHEMA kinetune FROM app_read, app_write, app_admin;
        REVOKE ALL ON ALL SEQUENCES IN SCHEMA kinetune FROM app_read, app_write, app_admin;
        REVOKE ALL ON ALL FUNCTIONS IN SCHEMA kinetune FROM app_read, app_write, app_admin;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA kinetune TO PUBLIC;
        REVOKE ALL ON SCHEMA kinetune FROM app_read, app_write, app_admin;

    """)
    # Roles are cluster-wide: keep them if another database still uses them
    op.execute("""
        DO $$
        DECLARE r text;
        BEGIN
            FOREACH r IN ARRAY ARRAY['app_admin', 'app_write', 'app_read'] LOOP
                BEGIN
                    EXECUTE format('DROP ROLE %I', r);
                EXCEPTION WHEN dependent_objects_still_exist THEN
                    RAISE NOTICE 'Role % kept: still used in another database', r;
                END;
            END LOOP;
        END
        $$;
    """)

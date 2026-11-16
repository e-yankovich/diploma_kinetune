"""Reference data: application roles and permissions, body areas, muscles, joints, rules BR1–BR11

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-16
"""
from pathlib import Path

from alembic import context, op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

SQL_DIR = Path(__file__).resolve().parents[2]  # db/


def _run_sql_file(name: str) -> None:
    sql = (SQL_DIR / name).read_text(encoding="utf-8")
    if context.is_offline_mode():
        op.execute(sql)
        return
    op.get_bind().connection.driver_connection.execute(sql)


def upgrade() -> None:
    _run_sql_file("03_reference_data.sql")


def downgrade() -> None:
    # reverse order of dependencies; fails (RESTRICT) if the data is in use,
    # which is intended: reference data must not disappear under live data
    op.execute("""
        DELETE FROM kinetune.rule;
        DELETE FROM kinetune.muscle;
        DELETE FROM kinetune.joint;
        DELETE FROM kinetune.body_area;
        DELETE FROM kinetune.role_permission;
        DELETE FROM kinetune.permission;
        DELETE FROM kinetune.role;
    """)

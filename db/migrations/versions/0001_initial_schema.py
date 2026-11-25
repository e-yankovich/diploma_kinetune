"""Initial schema: tables, constraints, indexes (01_schema.sql) and triggers (02_triggers.sql)

Revision ID: 0001
Revises:
Create Date: 2026-11-14
"""
from pathlib import Path

from alembic import context, op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

SQL_DIR = Path(__file__).resolve().parents[2]  # db/


def _run_sql_file(name: str) -> None:
    sql = (SQL_DIR / name).read_text(encoding="utf-8")
    if context.is_offline_mode():          # `alembic upgrade head --sql`
        op.execute(sql)
        return
    # Send the file to the driver as is, without parameters, so that
    # PL/pgSQL ':=', '::' casts and '%' in RAISE messages are not treated
    # as placeholders. Same connection, so same transaction as Alembic.
    driver_conn = op.get_bind().connection.driver_connection
    driver_conn.execute(sql)


def upgrade() -> None:
    _run_sql_file("01_schema.sql")
    _run_sql_file("02_triggers.sql")


def downgrade() -> None:
    op.execute("DROP SCHEMA kinetune CASCADE")

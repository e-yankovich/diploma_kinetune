"""Password policy: app_user.password_hash must be an argon2id PHC string

Revision ID: 0004
Revises: 0003
Create Date: 2026-11-16
"""
from pathlib import Path

from alembic import context, op

revision = "0004"
down_revision = "0003"
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
    _run_sql_file("05_password_policy.sql")


def downgrade() -> None:
    op.execute("""
        ALTER TABLE kinetune.app_user DROP CONSTRAINT ck_app_user_password_argon2id;
        COMMENT ON COLUMN kinetune.app_user.password_hash IS NULL;
    """)

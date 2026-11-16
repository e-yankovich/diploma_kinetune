"""Alembic environment: connects using environment variables, never hard-coded credentials."""
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy import URL, create_engine

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)


def database_url() -> URL:
    # URL.create escapes special characters in the password correctly
    return URL.create(
        "postgresql+psycopg",
        username=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", "5432")),
        database=os.environ["POSTGRES_DB"],
    )


def run_migrations_offline() -> None:
    """`alembic upgrade head --sql`: print the SQL instead of running it."""
    context.configure(url=database_url(), literal_binds=True, version_table_schema="public")
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    engine = create_engine(database_url())
    with engine.connect() as connection:
        context.configure(
            connection=connection,
            # every migration runs in its own transaction: a failing
            # migration is rolled back completely (PostgreSQL has transactional DDL)
            transaction_per_migration=True,
            # migration history table lives in "public", outside the app schema
            # (the SQL files switch search_path to "kinetune")
            version_table_schema="public",
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

"""Declarative base: every table lives in the PostgreSQL schema "kinetune".

The schema is created and changed only by the Alembic migrations in db/;
the ORM models map existing tables and never create them.
"""

from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase

SCHEMA = "kinetune"


class Base(DeclarativeBase):
    metadata = MetaData(schema=SCHEMA)

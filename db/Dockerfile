# One-shot image that applies database migrations (alembic upgrade head)
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini \
     01_schema.sql 02_triggers.sql 03_reference_data.sql \
     04_roles_privileges.sql 05_password_policy.sql ./
COPY migrations ./migrations
# library import script; the workbook itself is mounted at run time (/data)
COPY library/import_library.py ./library/
# data quality checks, run by the import inside its transaction
COPY checks ./checks

# run without root privileges
RUN useradd --system --no-create-home migrator
USER migrator

CMD ["alembic", "upgrade", "head"]

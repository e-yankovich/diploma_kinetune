# One-shot image that applies database migrations (alembic upgrade head)
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini \
     01_schema.sql 02_triggers.sql 03_reference_data.sql \
     04_roles_privileges.sql 05_password_policy.sql \
     06_plan_and_session_model.sql ./
COPY migrations ./migrations

# run without root privileges
RUN useradd --system --no-create-home migrator
USER migrator

CMD ["alembic", "upgrade", "head"]

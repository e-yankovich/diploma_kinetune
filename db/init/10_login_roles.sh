#!/usr/bin/env bash
# Runs once, when the PostgreSQL container initialises an empty data volume
# (/docker-entrypoint-initdb.d). Creates the non-superuser login roles with
# passwords from .env. The superuser (POSTGRES_USER) is used only here and
# for maintenance — never by the application or by migrations.
set -euo pipefail

: "${MIGRATOR_PASSWORD:?MIGRATOR_PASSWORD is not set}"
: "${API_PASSWORD:?API_PASSWORD is not set}"
: "${READER_PASSWORD:?READER_PASSWORD is not set}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD is not set}"

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v db="$POSTGRES_DB" \
     -v migrator_pw="$MIGRATOR_PASSWORD" \
     -v api_pw="$API_PASSWORD" \
     -v reader_pw="$READER_PASSWORD" \
     -v admin_pw="$ADMIN_PASSWORD" \
     -f /docker-entrypoint-initdb.d/login_roles.psql

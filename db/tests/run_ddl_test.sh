#!/usr/bin/env bash
# Recreates a scratch database, applies the DDL and runs the smoke test.
# 03 (reference data) and 05 (password policy) are left out: the test
# inserts its own reference rows and short placeholder hashes.
# Usage: PGHOST=... PGPORT=... PGUSER=... tests/run_ddl_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=kinetune_ddl_test
psql -q -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
psql -q -d $DB -v ON_ERROR_STOP=1 --single-transaction -f 01_schema.sql
psql -q -d $DB -v ON_ERROR_STOP=1 --single-transaction -f 02_triggers.sql
PGOPTIONS="-c client_min_messages=warning" psql -q -d $DB -v ON_ERROR_STOP=1 --single-transaction -f 04_roles_privileges.sql
psql -q -d $DB -v ON_ERROR_STOP=1 -o /dev/null -f tests/ddl_smoke_test.sql 2>&1 | sed 's/^psql:[^ ]* //'
psql -q -d postgres -c "DROP DATABASE $DB"

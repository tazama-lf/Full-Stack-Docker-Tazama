#! /bin/sh
set -e

DBS="configuration event_history raw_history evaluation"

RLS_SCRIPT=/tmp/rls.sql

for db in $DBS; do
  echo "Creating RLS tables in database: $db"

  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" -f "$RLS_SCRIPT"
done


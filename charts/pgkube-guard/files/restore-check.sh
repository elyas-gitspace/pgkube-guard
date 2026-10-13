#!/bin/sh
set -u
[ "$(cat /work/status 2>/dev/null)" = "ok" ] || exit 0

ko() { echo "$1" >> /work/error.log; echo ko > /work/status; exit 0; }

# Start an empty Postgres local to the pod, unix socket only
export PGDATA=/pgdata/data
initdb -U postgres >/dev/null || ko "initdb failed"
pg_ctl -o "-c listen_addresses='' -k /tmp" -w start >/dev/null || ko "throwaway Postgres did not start"
export PGHOST=/tmp PGUSER=postgres

# Restore the dump into it
createdb "$PGDATABASE" || ko "createdb failed"
echo "Restoring $(cat /work/dumpkey)..."
START=$(date +%s)
pg_restore --no-owner --no-privileges -d "$PGDATABASE" /work/latest.dump 2>>/work/error.log \
  || ko "pg_restore failed"
echo $(( $(date +%s) - START )) > /work/duration

# Run the check query
RESULT=$(psql -d "$PGDATABASE" -tAc "$CHECK_QUERY" 2>>/work/error.log) \
  || ko "check query errored"
echo "$CHECK_QUERY -> $RESULT"
if [ "$RESULT" -gt 0 ] 2>/dev/null; then
  echo "$RESULT" > /work/result
  echo ok > /work/status
else
  ko "check query returned '$RESULT' (expected > 0)"
fi
pg_ctl -m fast stop >/dev/null
exit 0

#!/bin/sh
set -u
. /scripts/notify.sh
if [ "$(cat /work/status 2>/dev/null)" = "ok" ]; then
  MSG="✅ Restore test $PGDATABASE OK: $(cat /work/dumpkey), $(cat /work/result) rows, restored in $(cat /work/duration)s"
  echo "$MSG"
  [ "${NOTIFY_ON_SUCCESS:-false}" = "true" ] && notify_slack "$MSG"
  ping_healthcheck "${HEALTHCHECK_URL_RESTORE:-}" ok
  exit 0
else
  ERR=$(tail -n 3 /work/error.log 2>/dev/null)
  echo "FAILED: $ERR"
  notify_slack "❌ Restore test $PGDATABASE failed: $ERR"
  ping_healthcheck "${HEALTHCHECK_URL_RESTORE:-}" fail
  exit 1
fi

#!/bin/sh
# Restore drill, dernière étape (image aws-cli) : verdict, seuils RTO / RPO, notifications, métriques
set -u
. /scripts/notify.sh
. /scripts/metrics.sh

STATUS=$(cat /work/status 2>/dev/null)
LABEL=$(cat /work/backup_label 2>/dev/null)
RESULT=$(cat /work/result 2>/dev/null)
RTO=$(cat /work/rto 2>/dev/null)
LAG=$(cat /work/data_lag 2>/dev/null)
LABELS="database=\"$PGDATABASE\",source=\"$VERIFY_SOURCE\""
METRICS=""
metric() {
  METRICS="${METRICS}pgkube_guard_$1{$LABELS} $2
"
}

# Un restore qui marche mais trop lent (RTO) ou avec des données trop vieilles (RPO) compte aussi comme un échec
if [ "$STATUS" = "ok" ]; then
  if [ "$MAX_RESTORE_SECONDS" -gt 0 ] && [ "$RTO" -gt "$MAX_RESTORE_SECONDS" ]; then
    echo "restore took $(human_duration "$RTO"), above the $(human_duration "$MAX_RESTORE_SECONDS") limit (RTO)" >> /work/error.log
    STATUS=ko
  fi
  if [ "$MAX_DATA_LAG_SECONDS" -gt 0 ] && [ "$LAG" -ge 0 ] && [ "$LAG" -gt "$MAX_DATA_LAG_SECONDS" ]; then
    echo "restored data is $(human_duration "$LAG") old, above the $(human_duration "$MAX_DATA_LAG_SECONDS") limit (RPO)" >> /work/error.log
    STATUS=ko
  fi
fi

# Métriques : publiées même en cas d'échec, pour garder une trace dans Prometheus
metric "restore_drill_last_run_timestamp_seconds" "$(date +%s)"
[ -n "$RTO" ] && metric "restore_duration_seconds" "$RTO"
[ -n "$LAG" ] && [ "$LAG" -ge 0 ] && metric "restore_data_lag_seconds" "$LAG"
[ -n "$RESULT" ] && metric "restore_check_result" "$RESULT"

if [ "$STATUS" = "ok" ]; then
  if [ "$LAG" -ge 0 ]; then LAG_TXT="data lag $(human_duration "$LAG") (RPO)"; else LAG_TXT="data lag unknown"; fi
  MSG="Restore drill $PGDATABASE OK ($VERIFY_SOURCE): $LABEL, check query = $RESULT, restored in $(human_duration "$RTO") (RTO), $LAG_TXT"
  echo "$MSG"
  metric "restore_drill_ok" 1
  push_metrics "pgkube_guard_restore_drill" "$METRICS"
  [ "$NOTIFY_ON_SUCCESS" = "true" ] && notify_slack "$MSG"
  ping_healthcheck "${HEALTHCHECK_URL_RESTORE:-}" ok
  exit 0
fi

ERR=$(tail -n 3 /work/error.log 2>/dev/null | tr '\n' ' ')
echo "FAILED: $ERR"
metric "restore_drill_ok" 0
push_metrics "pgkube_guard_restore_drill" "$METRICS"
notify_slack "Restore drill $PGDATABASE failed ($VERIFY_SOURCE): $ERR"
ping_healthcheck "${HEALTHCHECK_URL_RESTORE:-}" fail
exit 1

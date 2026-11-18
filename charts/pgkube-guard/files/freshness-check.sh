#!/bin/sh
# Freshness check (image aws-cli) : vérifie que les backups sont assez récents, sans rien restaurer
# Lancé souvent (toutes les heures par défaut), il ne fait que lister le bucket : rapide et gratuit
set -u
. /scripts/notify.sh
. /scripts/metrics.sh

NOW=$(date +%s)
PROBLEMS=""
LABELS="database=\"$PGDATABASE\",source=\"$VERIFY_SOURCE\""
METRICS=""

# Ajoute un problème à la liste (on vérifie tout avant de conclure)
problem() {
  echo "PROBLEM: $1"
  PROBLEMS="${PROBLEMS}${PROBLEMS:+ | }$1"
}

# Ajoute une ligne de métrique Prometheus. $1 = nom (sans le préfixe), $2 = valeur
metric() {
  METRICS="${METRICS}pgkube_guard_$1{$LABELS} $2
"
}

# Date (en epoch) de l'objet le plus récent sous un préfixe S3, dont la clé finit par un suffixe donné
# $1 = bucket, $2 = préfixe, $3 = suffixe ("" = tous les objets)
# Affiche l'epoch, rien si aucun objet, ou ERR si S3 répond une erreur (droits, bucket inexistant...)
latest_epoch() {
  TS=$(aws s3api list-objects-v2 --bucket "$1" --prefix "$2" \
    --query "Contents && max_by(Contents[?ends_with(Key, '$3')], &LastModified).LastModified" \
    --output text 2>/tmp/aws.err) || { echo ERR; return 0; }
  if [ -z "$TS" ] || [ "$TS" = "None" ]; then return 0; fi
  date -d "$TS" +%s
}

# Vérifie l'âge d'un objet et publie la métrique correspondante
# $1 = ce qu'on vérifie (pour les messages), $2 = epoch (ou vide / ERR), $3 = âge max en secondes, $4 = nom de la métrique
check_age() {
  if [ "$2" = "ERR" ]; then
    problem "cannot list $1: $(head -c 300 /tmp/aws.err | tr '\n' ' ')"
  elif [ -z "$2" ]; then
    problem "no $1 found"
  else
    AGE=$((NOW - $2))
    metric "$4" "$AGE"
    echo "Last $1: $(human_duration "$AGE") ago (max $(human_duration "$3"))"
    [ "$AGE" -gt "$3" ] && problem "last $1 is $(human_duration "$AGE") old (max $(human_duration "$3"))"
  fi
}

MAX_BACKUP_AGE=$((MAX_BACKUP_AGE_HOURS * 3600))

if [ "$VERIFY_SOURCE" = "pgdump" ]; then
  # Dumps nommés <prefix><database>-<date>.dump
  echo "Checking dumps in s3://$S3_BUCKET/${S3_PREFIX}${PGDATABASE}-*"
  LAST=$(latest_epoch "$S3_BUCKET" "${S3_PREFIX}${PGDATABASE}-" ".dump")
  check_age "dump" "$LAST" "$MAX_BACKUP_AGE" "backup_age_seconds"
else
  # wal-g : découpe s3://bucket/chemin en bucket + chemin
  P=${WALG_S3_PREFIX#s3://}
  WB=${P%%/*}
  WP=${P#"$WB"}
  WP=${WP#/}
  [ -n "$WP" ] && WP="${WP%/}/"
  echo "Checking wal-g backups in s3://$WB/$WP"

  # Un base backup n'est complet que quand wal-g a écrit son fichier "sentinel" de fin
  LAST=$(latest_epoch "$WB" "${WP}basebackups_005/" "_backup_stop_sentinel.json")
  check_age "base backup" "$LAST" "$MAX_BACKUP_AGE" "backup_age_seconds"

  # Les WAL archivés en continu : s'ils n'arrivent plus, le point-in-time recovery est cassé
  LAST_WAL=$(latest_epoch "$WB" "${WP}wal_005/" "")
  check_age "archived WAL" "$LAST_WAL" "$((MAX_WAL_AGE_MINUTES * 60))" "wal_age_seconds"
fi

metric "freshness_last_run_timestamp_seconds" "$NOW"

if [ -z "$PROBLEMS" ]; then
  echo "Freshness OK"
  metric "freshness_ok" 1
  push_metrics "pgkube_guard_freshness" "$METRICS"
  # Pas de message Slack en cas de succès : ce check tourne toutes les heures, ce serait du spam
  ping_healthcheck "${HEALTHCHECK_URL_FRESHNESS:-}" ok
  exit 0
fi

metric "freshness_ok" 0
push_metrics "pgkube_guard_freshness" "$METRICS"
notify_slack "Backup freshness check failed for $PGDATABASE ($VERIFY_SOURCE): $PROBLEMS"
ping_healthcheck "${HEALTHCHECK_URL_FRESHNESS:-}" fail
exit 1

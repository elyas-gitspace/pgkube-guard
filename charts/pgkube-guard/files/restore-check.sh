#!/bin/sh
# Restore drill pgdump, étape 2 (image postgres alpine) : Postgres jetable, pg_restore, check query
set -u
# Si le téléchargement a échoué, on ne fait rien : le rapport s'en occupe
[ "$(cat /work/status 2>/dev/null)" = "ok" ] || exit 0

# Note l'erreur, marque le test en échec et passe la main au rapport
ko() { echo "$1" >> /work/error.log; echo ko > /work/status; exit 0; }

# Postgres vide, local au pod : socket unix seulement, aucun port réseau ouvert
export PGDATA=/pgdata/data
initdb -U postgres >/dev/null || ko "initdb failed"
pg_ctl -o "-c listen_addresses='' -k /tmp" -w start >/dev/null || ko "throwaway Postgres did not start"
export PGHOST=/tmp PGUSER=postgres

# Restaure le dump dedans
createdb "$PGDATABASE" || ko "createdb failed"
echo "Restoring $(cat /work/backup_label)..."
pg_restore --no-owner --no-privileges -d "$PGDATABASE" /work/latest.dump 2>>/work/error.log \
  || ko "pg_restore failed"

# RTO = temps écoulé depuis le début du téléchargement jusqu'à une base restaurée
START=$(cat /work/start_time)
echo $(( $(date +%s) - START )) > /work/rto
# RPO = âge du dump au moment du test (les données plus récentes auraient été perdues)
echo $(( START - $(cat /work/backup_time) )) > /work/data_lag

# Check query : doit renvoyer un nombre > 0
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

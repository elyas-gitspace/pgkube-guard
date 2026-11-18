#!/bin/sh
# Restore drill wal-g, étape 2 (image postgres Debian) : restaure le dernier base backup,
# rejoue tous les WAL disponibles (comme un vrai point-in-time recovery), puis lance la check query
set -u
. /scripts/notify.sh
[ "$(cat /work/status 2>/dev/null)" = "ok" ] || exit 0

ko() { echo "$1" >> /work/error.log; echo ko > /work/status; exit 0; }

# Binaire wal-g : celui téléchargé à l'étape 1, sinon celui présent dans l'image
WALG=/walg/wal-g
[ -x "$WALG" ] || WALG=$(command -v wal-g) \
  || ko "wal-g binary not found: set verify.walg.binaryUrl or use an image that ships wal-g"

export PGDATA=/pgdata/data
mkdir -p "$PGDATA" && chmod 700 "$PGDATA"

# Le chrono du RTO démarre ici : temps pour passer de "rien" à "base utilisable"
date +%s > /work/start_time

# Nom du dernier base backup, juste pour le rapport (dernière ligne du tableau de backup-list)
"$WALG" backup-list 2>/dev/null | tail -n 1 | cut -d' ' -f1 > /work/backup_label
echo "Fetching base backup $(cat /work/backup_label)..."
if ! "$WALG" backup-fetch "$PGDATA" LATEST 2>/tmp/walg.log; then
  tail -n 3 /tmp/walg.log >> /work/error.log
  ko "wal-g backup-fetch failed"
fi

# On ignore la config de la prod (extensions, archive_command, certificats...) : le Postgres jetable a la sienne
[ -f "$PGDATA/postgresql.auto.conf" ] && mv "$PGDATA/postgresql.auto.conf" "$PGDATA/postgresql.auto.conf.prod"
rm -f "$PGDATA/postmaster.pid" "$PGDATA/standby.signal"
printf 'local all all trust\n' > /tmp/pg_hba.conf
: > /tmp/pg_ident.conf

cat > /tmp/drill.conf <<CONF
data_directory = '$PGDATA'
hba_file = '/tmp/pg_hba.conf'
ident_file = '/tmp/pg_ident.conf'
# Aucun port réseau : socket unix uniquement, rien ne peut s'y connecter depuis l'extérieur du pod
listen_addresses = ''
unix_socket_directories = '/tmp'
# Surtout ne jamais archiver de WAL : on ne doit rien écrire dans le bucket de la prod
archive_mode = off
# hot_standby off : sinon Postgres exige au moins les mêmes réglages que la prod (max_connections...)
hot_standby = off
# Va chercher chaque WAL dans S3 via wal-g, rejoue tout ce qui existe, puis redevient une base normale
restore_command = '$WALG wal-fetch %f %p'
recovery_target_timeline = 'latest'
recovery_target_action = 'promote'
$DRILL_EXTRA_CONFIG
CONF
# recovery.signal = "démarre en mode récupération et rejoue les WAL"
touch "$PGDATA/recovery.signal"

# Note les dernières lignes du log Postgres puis marque le test en échec
pg_ko() { tail -n 5 /tmp/postgres.log >> /work/error.log; ko "$1"; }

echo "Replaying WAL (timeout $(human_duration "$RECOVERY_TIMEOUT_SECONDS"))..."
DEADLINE=$(( $(date +%s) + RECOVERY_TIMEOUT_SECONDS ))
pg_ctl -D "$PGDATA" -o "-c config_file=/tmp/drill.conf" -l /tmp/postgres.log start >/dev/null \
  || pg_ko "throwaway Postgres did not start"
export PGHOST=/tmp PGUSER="$WALG_SUPERUSER"

# Attend la fin du replay : la base n'est utilisable qu'une fois sortie du mode récupération
until [ "$(psql -d "$PGDATABASE" -tAc 'SELECT pg_is_in_recovery()' 2>/dev/null)" = "f" ]; do
  # Si Postgres s'est arrêté (WAL corrompu, trou dans la chaîne de WAL...), inutile d'attendre
  pg_ctl -D "$PGDATA" status >/dev/null || pg_ko "Postgres stopped during the WAL replay"
  [ "$(date +%s)" -ge "$DEADLINE" ] && pg_ko "WAL replay did not finish within $(human_duration "$RECOVERY_TIMEOUT_SECONDS")"
  sleep 2
done

# RTO = temps écoulé depuis le début du restore
START=$(cat /work/start_time)
echo $(( $(date +%s) - START )) > /work/rto

# RPO = écart entre le début du test et la dernière transaction rejouée (ce qu'on aurait perdu)
# Si aucune transaction n'a été rejouée (base inactive), le RPO est inconnu : -1
psql -d "$PGDATABASE" -tAc "SELECT COALESCE(($START - EXTRACT(EPOCH FROM pg_last_xact_replay_timestamp()))::bigint, -1)" \
  > /work/data_lag 2>>/work/error.log || echo -1 > /work/data_lag
echo "Last replayed transaction: $(psql -d "$PGDATABASE" -tAc 'SELECT pg_last_xact_replay_timestamp()' 2>/dev/null)"

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

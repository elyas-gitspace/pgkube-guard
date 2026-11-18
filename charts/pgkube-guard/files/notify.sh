# Fonctions partagées pour prévenir l'utilisateur (sourcées par les autres scripts)

# Envoie un message Slack (ne fait rien si SLACK_WEBHOOK_URL est vide)
notify_slack() {
  [ -z "${SLACK_WEBHOOK_URL:-}" ] && return 0
  # Échappe les \ et les " pour garder un JSON valide
  MSG=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
  curl -sS -m 10 -X POST -H 'Content-Type: application/json' \
    -d "{\"text\": \"$MSG\"}" "$SLACK_WEBHOOK_URL" >/dev/null || true
}

# Ping un service de heartbeat (ex: healthchecks.io). $1 = url, $2 = ok | fail
ping_healthcheck() {
  [ -z "${1:-}" ] && return 0
  if [ "$2" = "ok" ]; then URL="$1"; else URL="$1/fail"; fi
  curl -sS -m 10 "$URL" >/dev/null || true
}

# Affiche une durée en secondes de façon lisible, ex: 252 -> 4m12s
human_duration() {
  S=$1
  if [ "$S" -ge 3600 ]; then printf '%dh%02dm' $((S / 3600)) $((S % 3600 / 60))
  elif [ "$S" -ge 60 ]; then printf '%dm%02ds' $((S / 60)) $((S % 60))
  else printf '%ds' "$S"; fi
}

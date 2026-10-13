notify_slack() {
  [ -z "${SLACK_WEBHOOK_URL:-}" ] && return 0
  MSG=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
  curl -sS -m 10 -X POST -H 'Content-Type: application/json' \
    -d "{\"text\": \"$MSG\"}" "$SLACK_WEBHOOK_URL" >/dev/null || true
}
ping_healthcheck() {
  # $1 = url, $2 = ok | fail
  [ -z "${1:-}" ] && return 0
  if [ "$2" = "ok" ]; then URL="$1"; else URL="$1/fail"; fi
  curl -sS -m 10 "$URL" >/dev/null || true
}

# Pousse des métriques Prometheus vers la Pushgateway (ne fait rien si PUSHGATEWAY_URL est vide)
# $1 = nom du job côté Prometheus, $2 = lignes au format texte Prometheus (une métrique par ligne)
push_metrics() {
  [ -z "${PUSHGATEWAY_URL:-}" ] && return 0
  # Les métriques sont rangées par job + instance (= nom de la release), pour ne pas écraser une autre release
  printf '%s\n' "$2" | curl -sS -m 10 --data-binary @- \
    "${PUSHGATEWAY_URL%/}/metrics/job/$1/instance/${INSTANCE_NAME}" >/dev/null \
    || echo "warning: could not push metrics to $PUSHGATEWAY_URL"
}

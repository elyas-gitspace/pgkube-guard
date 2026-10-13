#!/bin/sh
set -u
. /scripts/notify.sh

fail() {
  echo "FAILED: $1"
  notify_slack "❌ Backup $PGDATABASE failed: $1"
  ping_healthcheck "${HEALTHCHECK_URL_BACKUP:-}" fail
  exit 1
}

[ "$(cat /work/status 2>/dev/null)" = "ok" ] \
  || fail "pg_dump error: $(tail -n 3 /work/error.log 2>/dev/null)"

FILE=$(cat /work/dumpfile)
KEY="${S3_PREFIX}$(basename "$FILE")"
SIZE=$(du -h "$FILE" | cut -f1)

echo "Uploading to s3://$S3_BUCKET/$KEY ($SIZE)..."
aws s3 cp "$FILE" "s3://$S3_BUCKET/$KEY" --only-show-errors \
  || fail "S3 upload error"

# Keep only the $RETENTION most recent dumps
KEYS=$(aws s3api list-objects-v2 --bucket "$S3_BUCKET" \
  --prefix "${S3_PREFIX}${PGDATABASE}-" \
  --query 'sort_by(Contents,&LastModified)[].Key' --output text)
[ "$KEYS" = "None" ] && KEYS=""
COUNT=$(echo $KEYS | wc -w)
TO_DELETE=$((COUNT - RETENTION))
if [ "$TO_DELETE" -gt 0 ]; then
  for K in $(echo $KEYS | tr ' ' '\n' | head -n "$TO_DELETE"); do
    echo "Retention: deleting $K"
    aws s3 rm "s3://$S3_BUCKET/$K" --only-show-errors
  done
fi

echo "Backup OK !"
[ "${NOTIFY_ON_SUCCESS:-false}" = "true" ] && notify_slack "Backup $PGDATABASE OK ! ($SIZE)"
ping_healthcheck "${HEALTHCHECK_URL_BACKUP:-}" ok
exit 0

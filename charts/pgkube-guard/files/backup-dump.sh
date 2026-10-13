#!/bin/sh
set -u
FILE="/work/${PGDATABASE}-$(date -u +%Y-%m-%dT%H%M%SZ).dump"
echo "Dumping $PGDATABASE from $PGHOST..."
if pg_dump -Fc -f "$FILE" "$PGDATABASE" 2>/work/error.log; then
  echo "$FILE" > /work/dumpfile
  echo ok > /work/status
  echo "Dump OK: $(du -h "$FILE" | cut -f1)"
else
  echo ko > /work/status
  cat /work/error.log
fi
exit 0

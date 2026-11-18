#!/bin/sh
# Restore drill pgdump, étape 1 (image aws-cli) : télécharge le dernier dump dans /work
set -u
# Le chrono du RTO démarre ici : on mesure le temps total pour revenir à une base utilisable
date +%s > /work/start_time

# Clé et date du dump le plus récent (sortie "clé<TAB>date")
LATEST=$(aws s3api list-objects-v2 --bucket "$S3_BUCKET" \
  --prefix "${S3_PREFIX}${PGDATABASE}-" \
  --query 'sort_by(Contents,&LastModified)[-1].[Key,LastModified]' --output text 2>/work/error.log)
KEY=$(printf '%s' "$LATEST" | cut -f1)
if [ -z "$KEY" ] || [ "$KEY" = "None" ]; then
  echo "no dump found in s3://$S3_BUCKET/${S3_PREFIX}${PGDATABASE}-*" >> /work/error.log
  echo ko > /work/status
  exit 0
fi
echo "$KEY" > /work/backup_label
# Date du dump en epoch, sert à calculer le RPO (âge des données restaurées)
date -d "$(printf '%s' "$LATEST" | cut -f2)" +%s > /work/backup_time

echo "Downloading $KEY..."
if aws s3 cp "s3://$S3_BUCKET/$KEY" /work/latest.dump --only-show-errors 2>>/work/error.log; then
  echo ok > /work/status
else
  echo ko > /work/status
fi
exit 0

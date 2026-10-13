#!/bin/sh
set -u
KEY=$(aws s3api list-objects-v2 --bucket "$S3_BUCKET" \
  --prefix "${S3_PREFIX}${PGDATABASE}-" \
  --query 'sort_by(Contents,&LastModified)[-1].Key' --output text 2>/work/error.log)
if [ -z "$KEY" ] || [ "$KEY" = "None" ]; then
  echo "no dump found in s3://$S3_BUCKET/$S3_PREFIX" >> /work/error.log
  echo ko > /work/status
  exit 0
fi
echo "Downloading $KEY..."
if aws s3 cp "s3://$S3_BUCKET/$KEY" /work/latest.dump --only-show-errors 2>>/work/error.log; then
  echo "$KEY" > /work/dumpkey
  echo ok > /work/status
else
  echo ko > /work/status
fi
exit 0

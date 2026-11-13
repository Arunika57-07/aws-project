#!/bin/bash
# Archive Apache logs to S3 using the EC2 instance role (no access keys).
# Usage: sudo ./sync-logs.sh my-internship-bucket
set -euo pipefail
BUCKET="${1:?Usage: sync-logs.sh <bucket-name>}"
DEST="s3://${BUCKET}/logs/$(date +%F)/"
aws s3 sync /var/log/apache2/ "$DEST" --exclude "*.gz.tmp"
aws s3 ls "$DEST"

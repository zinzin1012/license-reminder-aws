#!/bin/bash
# Phase 1.6: Store all parameters in SSM Parameter Store
# Run AFTER other setup scripts have created resources

set -euo pipefail

REGION="ap-southeast-1"

# ─── Fill these in before running ──────────────────────────────
DATABASE_URL=""           # postgres://lr_admin:PASS@ENDPOINT:5432/licensereminder
TELEGRAM_BOT_TOKEN=""     # From BotFather
TELEGRAM_CHAT_ID=""       # Target chat/group ID
# ────────────────────────────────────────────────────────────────

if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: Fill in DATABASE_URL before running"
  exit 1
fi

echo "=== Storing parameters in SSM ==="

aws ssm put-parameter \
  --name "/licensereminder/DATABASE_URL" \
  --type SecureString \
  --value "$DATABASE_URL" \
  --region "$REGION" \
  --overwrite
echo "✓ DATABASE_URL"

if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
  aws ssm put-parameter \
    --name "/licensereminder/TELEGRAM_BOT_TOKEN" \
    --type SecureString \
    --value "$TELEGRAM_BOT_TOKEN" \
    --region "$REGION" \
    --overwrite
  echo "✓ TELEGRAM_BOT_TOKEN"
fi

if [ -n "$TELEGRAM_CHAT_ID" ]; then
  aws ssm put-parameter \
    --name "/licensereminder/TELEGRAM_CHAT_ID" \
    --type String \
    --value "$TELEGRAM_CHAT_ID" \
    --region "$REGION" \
    --overwrite
  echo "✓ TELEGRAM_CHAT_ID"
fi

echo ""
echo "=== All /licensereminder/ parameters ==="
aws ssm get-parameters-by-path \
  --path "/licensereminder/" \
  --region "$REGION" \
  --query 'Parameters[].Name' --output table

echo "=== Done ==="

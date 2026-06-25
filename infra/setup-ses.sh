#!/bin/bash
# Phase 1.3: Setup Amazon SES
# Verify domain for sending emails

set -euo pipefail

REGION="ap-southeast-1"
DOMAIN="dauhai1012.online"
FROM_EMAIL="noreply@dauhai1012.online"

echo "=== Verifying domain identity in SES ==="

aws sesv2 create-email-identity \
  --email-identity "$DOMAIN" \
  --region "$REGION"

echo "Domain identity created."
echo ""

echo "=== DKIM Records (add to Route53) ==="
aws sesv2 get-email-identity \
  --email-identity "$DOMAIN" \
  --region "$REGION" \
  --query 'DkimAttributes.Tokens' --output text | \
  tr '\t' '\n' | while read -r token; do
    echo "CNAME: ${token}._domainkey.${DOMAIN} → ${token}.dkim.amazonses.com"
  done

echo ""
echo "=== Store FROM email in SSM ==="

aws ssm put-parameter \
  --name "/licensereminder/SES_FROM_EMAIL" \
  --type String \
  --value "$FROM_EMAIL" \
  --region "$REGION" \
  --overwrite

echo ""
echo "=== Next steps ==="
echo "1. Add DKIM CNAME records to Route53"
echo "2. Verify: aws sesv2 get-email-identity --email-identity $DOMAIN --region $REGION"
echo "3. Request production access in SES console"

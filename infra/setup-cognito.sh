#!/bin/bash
# Phase 1.2: Create Cognito User Pool
# Replaces Supabase Auth (magic link + password)

set -euo pipefail

REGION="ap-southeast-1"

echo "=== Creating Cognito User Pool ==="

POOL_ID=$(aws cognito-idp create-user-pool \
  --pool-name licensereminder-users \
  --auto-verified-attributes email \
  --username-attributes email \
  --policies '{
    "PasswordPolicy": {
      "MinimumLength": 8,
      "RequireUppercase": false,
      "RequireLowercase": true,
      "RequireNumbers": true,
      "RequireSymbols": false,
      "TemporaryPasswordValidityDays": 7
    }
  }' \
  --schema '[
    {"Name":"email","Required":true,"Mutable":true,"AttributeDataType":"String"}
  ]' \
  --account-recovery-setting '{
    "RecoveryMechanisms": [{"Priority":1,"Name":"verified_email"}]
  }' \
  --region "$REGION" \
  --query 'UserPool.Id' --output text)

echo "User Pool ID: $POOL_ID"

echo "=== Creating App Client ==="

CLIENT_ID=$(aws cognito-idp create-user-pool-client \
  --user-pool-id "$POOL_ID" \
  --client-name licensereminder-web \
  --explicit-auth-flows \
    ALLOW_USER_PASSWORD_AUTH \
    ALLOW_USER_SRP_AUTH \
    ALLOW_REFRESH_TOKEN_AUTH \
  --prevent-user-existence-errors ENABLED \
  --access-token-validity 1 \
  --id-token-validity 1 \
  --refresh-token-validity 30 \
  --token-validity-units '{
    "AccessToken":"hours",
    "IdToken":"hours",
    "RefreshToken":"days"
  }' \
  --region "$REGION" \
  --query 'UserPoolClient.ClientId' --output text)

echo "Client ID: $CLIENT_ID"

echo "=== Storing in SSM ==="

aws ssm put-parameter \
  --name "/licensereminder/COGNITO_USER_POOL_ID" \
  --type String \
  --value "$POOL_ID" \
  --region "$REGION" \
  --overwrite

aws ssm put-parameter \
  --name "/licensereminder/COGNITO_CLIENT_ID" \
  --type String \
  --value "$CLIENT_ID" \
  --region "$REGION" \
  --overwrite

echo ""
echo "=== Done ==="
echo "COGNITO_USER_POOL_ID=$POOL_ID"
echo "COGNITO_CLIENT_ID=$CLIENT_ID"

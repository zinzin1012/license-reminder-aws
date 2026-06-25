#!/bin/bash
# Phase 1.4: Create S3 buckets
# Frontend hosting + attachment storage

set -euo pipefail

REGION="ap-southeast-1"
FRONTEND_BUCKET="licensereminder-frontend-dauhai"
ATTACHMENTS_BUCKET="licensereminder-attachments-dauhai"

echo "=== Creating frontend bucket (static hosting) ==="

aws s3api create-bucket \
  --bucket "$FRONTEND_BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

aws s3api put-public-access-block \
  --bucket "$FRONTEND_BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Frontend bucket: $FRONTEND_BUCKET"

echo "=== Creating attachments bucket ==="

aws s3api create-bucket \
  --bucket "$ATTACHMENTS_BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

aws s3api put-public-access-block \
  --bucket "$ATTACHMENTS_BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# CORS for presigned uploads
aws s3api put-bucket-cors \
  --bucket "$ATTACHMENTS_BUCKET" \
  --cors-configuration '{
    "CORSRules": [{
      "AllowedOrigins": ["https://license.dauhai1012.online","http://localhost:5173"],
      "AllowedMethods": ["GET","PUT","POST"],
      "AllowedHeaders": ["*"],
      "MaxAgeSeconds": 3600
    }]
  }'

echo "Attachments bucket: $ATTACHMENTS_BUCKET"
echo ""
echo "=== Done ==="

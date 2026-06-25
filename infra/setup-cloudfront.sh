#!/bin/bash
# Phase 1.5: Create CloudFront distribution + ACM certificate
# Single distribution: S3 (frontend) + API Gateway (/api/*)

set -euo pipefail

REGION="ap-southeast-1"
DOMAIN="license.dauhai1012.online"
FRONTEND_BUCKET="licensereminder-frontend-dauhai"

echo "=== Requesting ACM certificate (us-east-1 required for CF) ==="

CERT_ARN=$(aws acm request-certificate \
  --domain-name "$DOMAIN" \
  --validation-method DNS \
  --region us-east-1 \
  --query 'CertificateArn' --output text)

echo "Certificate ARN: $CERT_ARN"
sleep 5

echo "=== DNS validation record (add to Route53) ==="
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output table

echo ""
echo "=== Creating Origin Access Control ==="

OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config '{
    "Name": "licensereminder-oac",
    "Description": "OAC for LicenseReminder S3",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
  }' \
  --query 'OriginAccessControl.Id' --output text)

echo "OAC ID: $OAC_ID"
echo ""
echo "=== Save these values ==="
echo "CERT_ARN=$CERT_ARN"
echo "OAC_ID=$OAC_ID"
echo ""
echo "=== After cert is issued + API deployed ==="
echo "Create CloudFront distribution with:"
echo "  - Origin 1: ${FRONTEND_BUCKET}.s3.${REGION}.amazonaws.com (OAC)"
echo "  - Origin 2: API Gateway domain (/api/* behavior)"
echo "  - Alternate domain: $DOMAIN"
echo "  - Certificate: $CERT_ARN"
echo "  - CloudFront Function (SPA routing) on default behavior"
echo ""
echo "Then add Route53 CNAME:"
echo "  license.dauhai1012.online → <distribution>.cloudfront.net"

#!/bin/bash
# Phase 1.1: Create RDS PostgreSQL instance
# Idempotent — safe to re-run if previous attempt partially succeeded

set -euo pipefail

REGION="ap-southeast-1"
DB_INSTANCE_ID="licensereminder-db"
DB_NAME="licensereminder"
DB_MASTER_USER="lr_admin"
DB_MASTER_PASSWORD="${DB_MASTER_PASSWORD:-}"

if [ -z "$DB_MASTER_PASSWORD" ]; then
  echo "ERROR: DB_MASTER_PASSWORD is required"
  echo "Usage: DB_MASTER_PASSWORD='yourpassword' ./setup-rds.sh"
  echo "Password: 8+ chars, letters and numbers only (no @, /, quotes)"
  exit 1
fi

# ── VPC ───────────────────────────────────────────────────────
echo "=== VPC ==="
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=tag:Name,Values=licensereminder-vpc \
  --region "$REGION" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
  VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 --region "$REGION" \
    --query 'Vpc.VpcId' --output text)
  aws ec2 create-tags --resources "$VPC_ID" \
    --tags Key=Name,Value=licensereminder-vpc --region "$REGION"
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" \
    --enable-dns-support '{"Value":true}' --region "$REGION"
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" \
    --enable-dns-hostnames '{"Value":true}' --region "$REGION"
  echo "✓ VPC created: $VPC_ID"
else
  echo "✓ VPC exists: $VPC_ID"
fi

# ── Subnets ───────────────────────────────────────────────────
echo "=== Subnets ==="
SUBNET_A=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" Name=cidrBlock,Values=10.0.1.0/24 \
  --region "$REGION" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)

if [ -z "$SUBNET_A" ] || [ "$SUBNET_A" = "None" ]; then
  SUBNET_A=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 \
    --availability-zone "${REGION}a" --region "$REGION" \
    --query 'Subnet.SubnetId' --output text)
  echo "✓ Subnet A created: $SUBNET_A"
else
  echo "✓ Subnet A exists: $SUBNET_A"
fi

SUBNET_B=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" Name=cidrBlock,Values=10.0.2.0/24 \
  --region "$REGION" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)

if [ -z "$SUBNET_B" ] || [ "$SUBNET_B" = "None" ]; then
  SUBNET_B=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 \
    --availability-zone "${REGION}b" --region "$REGION" \
    --query 'Subnet.SubnetId' --output text)
  echo "✓ Subnet B created: $SUBNET_B"
else
  echo "✓ Subnet B exists: $SUBNET_B"
fi

# ── Internet Gateway ──────────────────────────────────────────
echo "=== Internet Gateway ==="
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters Name=attachment.vpc-id,Values="$VPC_ID" \
  --region "$REGION" \
  --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || true)

if [ -z "$IGW_ID" ] || [ "$IGW_ID" = "None" ]; then
  IGW_ID=$(aws ec2 create-internet-gateway \
    --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 attach-internet-gateway \
    --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"
  echo "✓ IGW created: $IGW_ID"
else
  echo "✓ IGW exists: $IGW_ID"
fi

# ── Route Table ───────────────────────────────────────────────
RTB_ID=$(aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --region "$REGION" --query 'RouteTables[0].RouteTableId' --output text)

ROUTE_EXISTS=$(aws ec2 describe-route-tables \
  --route-table-ids "$RTB_ID" --region "$REGION" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId" \
  --output text 2>/dev/null || true)

if [ -z "$ROUTE_EXISTS" ] || [ "$ROUTE_EXISTS" = "None" ]; then
  aws ec2 create-route --route-table-id "$RTB_ID" \
    --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION"
fi

aws ec2 associate-route-table --subnet-id "$SUBNET_A" \
  --route-table-id "$RTB_ID" --region "$REGION" 2>/dev/null || true
aws ec2 associate-route-table --subnet-id "$SUBNET_B" \
  --route-table-id "$RTB_ID" --region "$REGION" 2>/dev/null || true

# ── Security Group ────────────────────────────────────────────
echo "=== Security Group ==="
SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=licensereminder-rds-sg Name=vpc-id,Values="$VPC_ID" \
  --region "$REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group \
    --group-name licensereminder-rds-sg \
    --description "LicenseReminder RDS access" \
    --vpc-id "$VPC_ID" --region "$REGION" \
    --query 'GroupId' --output text)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" --protocol tcp --port 5432 \
    --cidr 10.0.0.0/16 --region "$REGION"
  echo "✓ Security group created: $SG_ID"
else
  echo "✓ Security group exists: $SG_ID"
fi

# ── DB Subnet Group ───────────────────────────────────────────
echo "=== DB Subnet Group ==="
SUBNET_GRP=$(aws rds describe-db-subnet-groups \
  --db-subnet-group-name licensereminder-subnet-group \
  --region "$REGION" \
  --query 'DBSubnetGroups[0].DBSubnetGroupName' --output text 2>/dev/null || echo "None")

if [ -z "$SUBNET_GRP" ] || [ "$SUBNET_GRP" = "None" ]; then
  aws rds create-db-subnet-group \
    --db-subnet-group-name licensereminder-subnet-group \
    --db-subnet-group-description "LicenseReminder subnets" \
    --subnet-ids "$SUBNET_A" "$SUBNET_B" \
    --region "$REGION"
  echo "✓ DB subnet group created"
else
  echo "✓ DB subnet group exists"
fi

# ── RDS Instance ──────────────────────────────────────────────
echo "=== RDS Instance ==="
DB_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" --region "$REGION" \
  --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || true)

if [ -n "$DB_STATUS" ] && [ "$DB_STATUS" != "None" ]; then
  echo "✓ RDS instance exists (status: $DB_STATUS)"
else
  aws rds create-db-instance \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --db-instance-class db.t4g.micro \
    --engine postgres \
    --engine-version "16.4" \
    --master-username "$DB_MASTER_USER" \
    --master-user-password "$DB_MASTER_PASSWORD" \
    --allocated-storage 20 \
    --storage-type gp3 \
    --db-name "$DB_NAME" \
    --db-subnet-group-name licensereminder-subnet-group \
    --vpc-security-group-ids "$SG_ID" \
    --publicly-accessible \
    --backup-retention-period 0 \
    --no-multi-az \
    --region "$REGION"
  echo "✓ RDS instance creating (5-10 min)..."
fi

echo ""
echo "=== Monitor status ==="
echo "aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_ID --region $REGION --query 'DBInstances[0].DBInstanceStatus' --output text"
echo ""
echo "=== Get endpoint (once 'available') ==="
echo "aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_ID --region $REGION --query 'DBInstances[0].Endpoint.Address' --output text"
echo ""
echo "VPC_ID=$VPC_ID"
echo "SUBNET_A=$SUBNET_A"
echo "SUBNET_B=$SUBNET_B"
echo "SG_ID=$SG_ID"
echo "IGW_ID=$IGW_ID"

#!/bin/bash
# Phase 1.1: Create RDS PostgreSQL instance
# Region: ap-southeast-1 (Singapore)
# Instance: db.t4g.micro (free tier eligible)

set -euo pipefail

REGION="ap-southeast-1"
DB_INSTANCE_ID="licensereminder-db"
DB_NAME="licensereminder"
DB_MASTER_USER="lr_admin"
DB_MASTER_PASSWORD="" # SET THIS BEFORE RUNNING

if [ -z "$DB_MASTER_PASSWORD" ]; then
  echo "ERROR: Set DB_MASTER_PASSWORD before running this script"
  exit 1
fi

echo "=== Creating VPC and Security Group ==="

# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region "$REGION" \
  --query 'Vpc.VpcId' --output text)

aws ec2 create-tags --resources "$VPC_ID" \
  --tags Key=Name,Value=licensereminder-vpc \
  --region "$REGION"

aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" \
  --enable-dns-support '{"Value":true}' --region "$REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" \
  --enable-dns-hostnames '{"Value":true}' --region "$REGION"

echo "VPC: $VPC_ID"

# Create 2 subnets in different AZs (required for RDS subnet group)
SUBNET_A=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone "${REGION}a" \
  --region "$REGION" \
  --query 'Subnet.SubnetId' --output text)

SUBNET_B=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.2.0/24 \
  --availability-zone "${REGION}b" \
  --region "$REGION" \
  --query 'Subnet.SubnetId' --output text)

echo "Subnets: $SUBNET_A, $SUBNET_B"

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$REGION" \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway \
  --internet-gateway-id "$IGW_ID" \
  --vpc-id "$VPC_ID" \
  --region "$REGION"

# Route table — add default route to IGW
RTB_ID=$(aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --region "$REGION" \
  --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 create-route \
  --route-table-id "$RTB_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" \
  --region "$REGION"

aws ec2 associate-route-table --subnet-id "$SUBNET_A" \
  --route-table-id "$RTB_ID" --region "$REGION"
aws ec2 associate-route-table --subnet-id "$SUBNET_B" \
  --route-table-id "$RTB_ID" --region "$REGION"

# Security group for RDS
SG_ID=$(aws ec2 create-security-group \
  --group-name licensereminder-rds-sg \
  --description "LicenseReminder RDS access" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' --output text)

# Allow PostgreSQL from within VPC
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 5432 \
  --cidr 10.0.0.0/16 \
  --region "$REGION"

echo "Security Group: $SG_ID"

# DB Subnet Group
aws rds create-db-subnet-group \
  --db-subnet-group-name licensereminder-subnet-group \
  --db-subnet-group-description "LicenseReminder subnets" \
  --subnet-ids "$SUBNET_A" "$SUBNET_B" \
  --region "$REGION"

echo "=== Creating RDS Instance ==="

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
  --backup-retention-period 7 \
  --no-multi-az \
  --region "$REGION"

echo ""
echo "=== RDS creating (5-10 min). Monitor with: ==="
echo "aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_ID --region $REGION --query 'DBInstances[0].DBInstanceStatus'"
echo ""
echo "Get endpoint once available:"
echo "aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_ID --region $REGION --query 'DBInstances[0].Endpoint.Address' --output text"
echo ""
echo "=== SAVE THESE VALUES ==="
echo "VPC_ID=$VPC_ID"
echo "SUBNET_A=$SUBNET_A"
echo "SUBNET_B=$SUBNET_B"
echo "SG_ID=$SG_ID"
echo "IGW_ID=$IGW_ID"

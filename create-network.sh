#!/bin/bash
# Creates the custom VPC, public subnet, IGW and route table (all Free) via AWS CLI.
# Run with your IAM user credentials. Region: ap-south-1 (Mumbai).
set -euo pipefail
REGION=ap-south-1
OWNER="${1:?Usage: create-network.sh <your-name>}"
TAGS="ResourceType=%s,Tags=[{Key=Project,Value=InternshipAWS},{Key=Env,Value=Demo},{Key=Owner,Value=$OWNER}]"

VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region $REGION \
  --tag-specifications "$(printf "$TAGS" vpc)" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region $REGION

SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 \
  --availability-zone ${REGION}a --region $REGION \
  --tag-specifications "$(printf "$TAGS" subnet)" --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region $REGION

IGW_ID=$(aws ec2 create-internet-gateway --region $REGION \
  --tag-specifications "$(printf "$TAGS" internet-gateway)" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region $REGION

RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region $REGION \
  --tag-specifications "$(printf "$TAGS" route-table)" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region $REGION
aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$SUBNET_ID" --region $REGION

MYIP=$(curl -s https://checkip.amazonaws.com)
SG_ID=$(aws ec2 create-security-group --group-name internship-web-sg --description "SSH from my IP, HTTP open" \
  --vpc-id "$VPC_ID" --region $REGION --tag-specifications "$(printf "$TAGS" security-group)" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "${MYIP}/32" --region $REGION
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION

echo "VPC=$VPC_ID SUBNET=$SUBNET_ID IGW=$IGW_ID RT=$RT_ID SG=$SG_ID"

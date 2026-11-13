#!/bin/bash
# Cleanup for the Free Tier safety checklist. Review each step; this deletes demo resources.
# Usage: ./cleanup.sh <instance-id> <snapshot-id> <bucket-name> <vpc-id>
set -uo pipefail
REGION=ap-south-1
INSTANCE_ID="${1:?instance id}"; SNAP_ID="${2:?snapshot id}"; BUCKET="${3:?bucket}"; VPC_ID="${4:?vpc id}"

aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region $REGION
aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region $REGION
aws ec2 delete-snapshot --snapshot-id "$SNAP_ID" --region $REGION
aws s3 rm "s3://$BUCKET" --recursive && aws s3 rb "s3://$BUCKET"

for SG in $(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query "SecurityGroups[?GroupName!='default'].GroupId" --output text --region $REGION); do
  aws ec2 delete-security-group --group-id "$SG" --region $REGION
done
for IGW in $(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --query "InternetGateways[].InternetGatewayId" --output text --region $REGION); do
  aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" --region $REGION
  aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" --region $REGION
done
for SUB in $(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query "Subnets[].SubnetId" --output text --region $REGION); do
  aws ec2 delete-subnet --subnet-id "$SUB" --region $REGION
done
for RT in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" --output text --region $REGION); do
  aws ec2 delete-route-table --route-table-id "$RT" --region $REGION
done
aws ec2 delete-vpc --vpc-id "$VPC_ID" --region $REGION
echo "Cleanup done. Also delete CloudWatch alarms, the SNS topic and the Budget in the console."

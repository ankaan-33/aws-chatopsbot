#!/usr/bin/env bash
# Empty the dashboard bucket (CloudFormation can't delete a non-empty bucket), then delete the stack.
# Usage: ./scripts/destroy.sh [stack-name] [region]
set -euo pipefail
STACK="${1:-chatopsbot}"
REGION="${2:-$(aws configure get region)}"

BUCKET=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='DashboardBucketName'].OutputValue" --output text)

if [ -n "$BUCKET" ] && [ "$BUCKET" != "None" ]; then
  aws s3 rm "s3://$BUCKET" --recursive --region "$REGION"
fi

aws cloudformation delete-stack --region "$REGION" --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$STACK"
echo "Deleted $STACK"

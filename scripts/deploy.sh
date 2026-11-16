#!/usr/bin/env bash
# Package the Lambda, deploy the stack, and upload the dashboard.
# Usage: ./scripts/deploy.sh <artifact-bucket> [stack-name] [region] [Param=Value ...]
#   e.g. ./scripts/deploy.sh my-artifacts chatopsbot eu-west-2 \
#          AlertEmail=me@example.com SlackWorkspaceId=T0123ABCD SlackChannelId=C0123ABCD
set -euo pipefail

BUCKET="${1:?Usage: deploy.sh <artifact-bucket> [stack-name] [region] [Param=Value ...]}"
STACK="${2:-chatopsbot}"
REGION="${3:-$(aws configure get region)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
shift $(( $# < 3 ? $# : 3 ))
OVERRIDES=()
if [ $# -gt 0 ]; then OVERRIDES=(--parameter-overrides "$@"); fi

aws cloudformation package --region "$REGION" \
  --template-file "$ROOT/infrastructure/template.yaml" \
  --s3-bucket "$BUCKET" --s3-prefix "$STACK" \
  --output-template-file "$ROOT/infrastructure/packaged.yaml"

aws cloudformation deploy --region "$REGION" --stack-name "$STACK" \
  --template-file "$ROOT/infrastructure/packaged.yaml" \
  --capabilities CAPABILITY_IAM \
  ${OVERRIDES[@]+"${OVERRIDES[@]}"}

out() { aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
          --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

echo "==> Uploading dashboard"
aws s3 cp "$ROOT/dashboard/index.html" "s3://$(out DashboardBucketName)/index.html" \
  --region "$REGION" --content-type "text/html" --cache-control "max-age=300"

aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs" --output table

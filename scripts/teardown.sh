#!/usr/bin/env bash
# Deletes everything the lab created. The bucket is emptied first; CloudFormation refuses to delete a bucket with objects.
set -euo pipefail
cd "$(dirname "$0")/.."
R="${AWS_REGION:-ap-northeast-2}"
S=devops-day-lab
scripts/chaos.sh stop || true
# Stop the consumer first so no new order lands in the bucket between emptying it and CloudFormation deleting it.
aws lambda put-function-concurrency --function-name "$S-consumer" --reserved-concurrent-executions 0 --region "$R" >/dev/null 2>&1 || true
B=$(aws cloudformation describe-stacks --stack-name "$S" --region "$R" --query "Stacks[0].Outputs[?OutputKey=='ArchiveBucket'].OutputValue" --output text 2>/dev/null || true)
empty() { [ -n "$B" ] && [ "$B" != None ] && aws s3 rm "s3://$B" --recursive --quiet 2>/dev/null; true; }
# Empty the bucket right before each attempt; retry a couple of times in case something still landed.
for i in 1 2 3; do
  empty
  sam delete --stack-name "$S" --region "$R" --no-prompts && break
  [ "$i" = 3 ] && { echo "Stack delete failed three times. Empty the bucket in the S3 console and run this again."; exit 1; }
  sleep 10
done
echo "Gone. OpsItems stay in OpsCenter (resolve them there); a verified SMS sandbox number stays verified."

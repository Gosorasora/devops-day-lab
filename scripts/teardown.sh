#!/usr/bin/env bash
# Deletes everything the lab created. The bucket is emptied first; CloudFormation refuses to delete a bucket with objects.
set -euo pipefail
cd "$(dirname "$0")/.."
R="${AWS_REGION:-ap-northeast-2}"
S=devops-day-lab
scripts/chaos.sh stop || true
B=$(aws cloudformation describe-stacks --stack-name "$S" --region "$R" --query "Stacks[0].Outputs[?OutputKey=='ArchiveBucket'].OutputValue" --output text 2>/dev/null || true)
empty() { [ -n "$B" ] && [ "$B" != None ] && aws s3 rm "s3://$B" --recursive --quiet; }
empty
# Orders keep landing in archive/ until the function is gone, so the bucket may fill up again: empty it and retry once.
sam delete --stack-name "$S" --region "$R" --no-prompts || { empty; sam delete --stack-name "$S" --region "$R" --no-prompts; }
echo "Gone. OpsItems stay in OpsCenter (resolve them there); a verified SMS sandbox number stays verified."

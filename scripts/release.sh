#!/usr/bin/env bash
# release.sh on   ship the broken consumer ("v2") as a 10% canary. The canary alarm fires, CodeDeploy rolls back,
#                 CloudFormation reports the update as failed. That failure is the point.
# release.sh off  ship the healthy consumer again (only needed if you interrupted the rollback).
set -euo pipefail
cd "$(dirname "$0")/.."
R="${AWS_REGION:-ap-northeast-2}"
case "${1:-}" in on|off) ;; *) echo "usage: $0 on|off"; exit 1 ;; esac
echo "Deployments: https://$R.console.aws.amazon.com/codesuite/codedeploy/deployments?region=$R"
sam deploy --region "$R" --no-fail-on-empty-changeset --parameter-overrides "Bug=$1" \
  || echo "Deploy failed and rolled back. With Bug=on, that is the canary doing its job."

#!/usr/bin/env bash
# chaos.sh start error|delay   run one of the stack's AWS FIS experiment templates (4 minutes; the blast-radius alarm stops it early)
# chaos.sh stop                stop every running experiment
# chaos.sh status              list experiments
set -euo pipefail
R="${AWS_REGION:-ap-northeast-2}"
S=devops-day-lab
out() { aws cloudformation describe-stacks --stack-name "$S" --region "$R" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

case "${1:-}" in
  start)
    case "${2:-}" in
      error) T=$(out FisErrorTemplate) ;;
      delay) T=$(out FisDelayTemplate) ;;
      *) echo "usage: $0 start error|delay"; exit 1 ;;
    esac
    ID=$(aws fis start-experiment --experiment-template-id "$T" --tags "Name=$S-$2" --region "$R" --query experiment.id --output text)
    echo "experiment $ID started ($2) at $(date +%H:%M:%S). Write that time down: it is when the outage began."
    echo "https://$R.console.aws.amazon.com/fis/home?region=$R#Experiments/$ID"
    ;;
  stop)
    T1=$(out FisErrorTemplate); T2=$(out FisDelayTemplate)
    for ID in $(aws fis list-experiments --region "$R" --query "experiments[?(experimentTemplateId=='$T1' || experimentTemplateId=='$T2') && (state.status=='running' || state.status=='initiating' || state.status=='pending')].id" --output text); do
      echo "stopping $ID: $(aws fis stop-experiment --id "$ID" --region "$R" --query experiment.state.status --output text)"
    done
    ;;
  status)
    aws fis list-experiments --region "$R" --query 'experiments[].[id, state.status, creationTime]' --output table
    ;;
  *) echo "usage: $0 start error|delay | stop | status"; exit 1 ;;
esac

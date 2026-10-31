#!/usr/bin/env bash
# Run the stack's runbook: move every dead-lettered order back to the orders queue.
# Same as "Execute automation" on the OpsItem in the console, from the terminal.
set -euo pipefail
R="${AWS_REGION:-ap-northeast-2}"
S=devops-day-lab
out() { aws cloudformation describe-stacks --stack-name "$S" --region "$R" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

EX=$(aws ssm start-automation-execution --document-name "$(out Runbook)" --region "$R" --query AutomationExecutionId --output text)
echo "automation $EX started"
for _ in $(seq 1 12); do
  st=$(aws ssm get-automation-execution --automation-execution-id "$EX" --region "$R" --query AutomationExecution.AutomationExecutionStatus --output text)
  echo "  $st"
  case $st in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 5
done
echo "orders still in the dead-letter queue: $(aws sqs get-queue-attributes --queue-url "$(out DlqUrl)" --attribute-names ApproximateNumberOfMessages --region "$R" --query Attributes.ApproximateNumberOfMessages --output text) (the move takes up to a minute)"

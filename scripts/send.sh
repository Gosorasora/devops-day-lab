#!/usr/bin/env bash
# The shop's "API": put N OrderPlaced events on the bus (default 1). Prints the failed-entry count, so 0 is good.
set -euo pipefail
R="${AWS_REGION:-ap-northeast-2}"
N="${1:-1}"
for i in $(seq 1 "$N"); do
  aws events put-events --region "$R" --query FailedEntryCount --output text --cli-input-json "$(cat <<JSON
{"Entries": [{"EventBusName": "devops-day-lab-bus", "Source": "lab.shop", "DetailType": "OrderPlaced",
  "Detail": "{\"order_id\": \"manual-$(date +%s)-$i\", \"item\": \"espresso\", \"amount\": 3000}"}]}
JSON
)"
done

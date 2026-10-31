#!/usr/bin/env bash
# One-shot install. Made for AWS CloudShell (aws, sam preinstalled); works anywhere with those two.
# Safe to re-run: Enter at a prompt keeps the value the stack already has, and Bug goes back to "off".
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
R=$AWS_REGION
S=devops-day-lab

for t in aws sam; do command -v "$t" >/dev/null || { echo "missing: $t"; exit 1; }; done
echo "AWS account $(aws sts get-caller-identity --query Account --output text), region $R"

current() { aws cloudformation describe-stacks --stack-name "$S" --region "$R" --query "Stacks[0].Parameters[?ParameterKey=='$1'].ParameterValue" --output text 2>/dev/null || true; }
E=$(current Email); P=$(current Phone)

read -rp "On-call email${E:+ [Enter = $E]}: " v || true; EMAIL="${v:-$E}"
[ -n "$EMAIL" ] || { echo "an email is required"; exit 1; }
read -rp "On-call phone for SMS, like +821012345678 [Enter = ${P:-none}]: " v || true; PHONE="${v:-$P}"

if [ -n "$PHONE" ]; then
  # Every account starts in the SNS SMS sandbox: it only texts numbers you verified with a one-time code.
  st=$(aws sns list-sms-sandbox-phone-numbers --region "$R" --query "PhoneNumbers[?PhoneNumber=='$PHONE'].Status" --output text)
  if [ "$st" != Verified ]; then
    [ "$st" = Pending ] || aws sns create-sms-sandbox-phone-number --phone-number "$PHONE" --language-code en-US --region "$R"
    read -rp "SNS sent a code to $PHONE. Enter it: " code || true
    aws sns verify-sms-sandbox-phone-number --phone-number "$PHONE" --one-time-password "$code" --region "$R"
  fi
fi

PARAMS=("Email=$EMAIL" "Bug=off" "Release=off$(cksum src/consumer.py | cut -d' ' -f1)")
[ -n "$PHONE" ] && PARAMS+=("Phone=$PHONE")
# No `sam build`: the function has no dependencies, so deploy packages src/ as is.
# --on-failure DELETE: a failed first create is deleted, so the script can simply be run again.
sam deploy --region "$R" --no-fail-on-empty-changeset --on-failure DELETE --parameter-overrides "${PARAMS[@]}"

echo
echo "1. Confirm the 'AWS Notification - Subscription Confirmation' mail sent to $EMAIL. Until then no alarm reaches you."
echo "2. Dashboard: $(aws cloudformation describe-stacks --stack-name "$S" --region "$R" --query "Stacks[0].Outputs[?OutputKey=='Dashboard'].OutputValue" --output text)"
echo "   Orders start flowing within a minute (10 per minute)."

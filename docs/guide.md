# Hands-on DevOps: Chaos Engineering (AWS FIS) and On-call Response (CloudWatch, SNS, OpsCenter)

Lab guide (55 minutes, with a 30-minute short path)

You deploy one order pipeline, learn what normal looks like, break it on purpose, get paged and respond, then ship a broken version as a canary and watch the automatic rollback. Every command runs in AWS CloudShell from the repository root.

**30-minute short path:** do steps 1, 3, 4 and 6 only. Spend 1 to 2 minutes on step 2 while the deploy runs. Skip step 5. Steps on the short path have `[30 min]` in their title.

## Before the session

- An AWS account. Attach `iam/lab-policy.json` to the user or role you deploy with. Use a sandbox account.
- Sign in to the console and set the region to Seoul (`ap-northeast-2`). CloudShell is the `>_` icon in the top bar.
- An email address for the alarms.
- Optional: a phone number for SMS (`+8210...` form). SMS is charged per message.
- Optional: install the AWS Console Mobile App and sign in with the same account (step 0).

## Step 0 (optional, 5 min): Console Mobile App push

AWS User Notifications can push CloudWatch alarm state changes to your phone. This step is done by hand in the console. The AWS User Notifications permissions it needs are part of `iam/lab-policy.json`.

1. In the Console Mobile App on your phone, turn notifications on. This registers the device with User Notifications.
2. In the console open **User Notifications > Notification configurations > Create notification configuration**.
3. Event rule: source `aws.cloudwatch`, event type **CloudWatch Alarm State Change**, region `ap-northeast-2`.
4. Delivery channel: **AWS Console Mobile App**, pick the registered device.

From step 3 on, every alarm arrives as a push as well as a mail.

## Step 1 [30 min] (10 min): Deploy

```bash
git clone https://github.com/Gosorasora/devops-day-lab.git
cd devops-day-lab
./scripts/setup.sh
```

The script asks for your email. If you gave a phone number, it asks for the one-time code SNS texts you. When `sam deploy` finishes it prints the dashboard URL.

Two things to do before the deploy finishes:

1. Open the "AWS Notification - Subscription Confirmation" mail and click **Confirm subscription**. Until you do, no alarm reaches you.
2. Open the printed dashboard URL in a new tab.

Within a minute orders start flowing at 10 per minute. The stack is `devops-day-lab`, the function is `devops-day-lab-consumer`.

## Step 2 (10 min): Baseline

If you do not know what normal looks like, you cannot see an outage. Check three places before you break anything.

**The dashboard.** Read the widgets.

- Alarms: all five OK.
- Orders: invocations vs errors: 10 per minute, 0 errors.
- Latency p50 / p95: around 100 ms.
- Queue depth: orders vs dead-letter: both near 0.
- Orders archived: the metric the app writes itself. 10 per minute.
- Last orders: the structured log table with `order_id`, `item`, `amount` and `ms` columns.

**Logs Insights.** In CloudWatch > Logs Insights pick the log group `/aws/lambda/devops-day-lab-consumer` and run:

```
fields @timestamp, order_id, item, amount, ms | filter level = 'INFO' | stats sum(amount) by item
```

Revenue per item. The query works because every log line is one JSON object.

**The X-Ray service map.** Open CloudWatch > X-Ray traces > Service map. You see the Lambda service node and the function node (the S3 call inside the function is not drawn, there is no X-Ray SDK in the code). Click a node for its response-time distribution.

Write down: the normal error rate (0), the normal p95 in milliseconds, the normal dead-letter depth (0).

## Step 3 [30 min] (10 min): Break it

```bash
scripts/chaos.sh start error
```

The AWS FIS experiment `devops-day-lab-error` starts. For 4 minutes every invocation fails before the handler runs. **Write down the start time the script prints.** That is when the outage began.

This is what happens next. Watch the dashboard and note each time.

1. Within a minute the Errors graph climbs. The FIS extension checks for a fault configuration every 10 seconds, so the effect starts a few dozen seconds in. Each order fails three times, 30 seconds apart.
2. After 1 to 2 minutes the alarm `devops-day-lab-consumer-errors` goes to ALARM (5 or more errors in a minute). A mail arrives. A push if you did step 0, an SMS if you gave a number.
3. About a minute later the first order reaches the dead-letter queue and `devops-day-lab-dlq-not-empty` goes to ALARM.
4. OpsItems appear in Systems Manager > OpsCenter: one at severity 2 (Availability), one at severity 3 (Recovery). The first visit to OpsCenter may show a getting-started page; continue through it.

Open the experiment in the FIS console and look at **Stop conditions**. The alarm `devops-day-lab-blast-radius` (more than 100 dead-lettered orders) is attached. The alarm that pages you and the alarm that stops the experiment are different alarms. The experiment limits its own damage.

## Step 4 [30 min] (10 min): Respond

The mail on-call received names the alarm, the reason for the state change and the region. Start there.

1. **Open the OpsItem.** In Systems Manager > OpsCenter open the OpsItem created by `devops-day-lab-consumer-errors`. Related resources lists the function; the alarm timeline shows the state changes.
2. **Find the cause.** In Logs Insights, same log group, run:

   ```
   fields @timestamp, @message | filter @message like /error|Error|FIS/ | sort @timestamp desc | limit 20
   ```

   You see the messages the FIS extension left. In a real outage this is the slowest part.
3. **Remove the cause.** The experiment may already have ended after 4 minutes. If not, stop it.

   ```bash
   scripts/chaos.sh stop
   ```

4. **Run the runbook.** Move the dead-lettered orders back to the orders queue. On the OpsItem page, under **Runbooks**, find `devops-day-lab-redrive-dlq` and execute it, or run it from the terminal.

   ```bash
   scripts/redrive.sh
   ```

   If the cause is still there the orders just come back to the dead-letter queue. That is why item 3 comes first.
5. **Confirm recovery.** Within a minute the dead-letter line in Queue depth drops to 0 and both alarms return to OK. OK mails arrive.
6. **Resolve the OpsItems.** Write one line each for cause, action and prevention on both OpsItems and set them to Resolved.

Compute two numbers from the times you wrote down.

- **MTTD** (time to detect): experiment start to the first alarm mail.
- **MTTR** (time to recover): experiment start to the alarms returning to OK.

## Step 5 (10 min): Ship safely

Deployments are a common cause of outages. Ship a version that crashes on every order.

```bash
scripts/release.sh on
```

`Bug=on` publishes a new version and CodeDeploy rolls it out with `Canary10Percent10Minutes`. Only 10% of traffic goes to the new version. To get orders onto the new version sooner, add some with `scripts/send.sh 20`.

1. Open the CodeDeploy console link the script prints. The deployment is in progress and shows the traffic split.
2. Within 1 to 2 minutes `devops-day-lab-canary-errors` goes to ALARM. This alarm counts errors of the new version only (ExecutedVersion); one error is enough.
3. CodeDeploy marks the deployment Failed and routes traffic back to the previous version. The CloudFormation stack ends in `UPDATE_ROLLBACK_COMPLETE`. The `sam deploy` in your terminal prints a failure message. That is the expected outcome.
4. Look at the dashboard. The on-call alarm `devops-day-lab-consumer-errors` normally does not fire: about 1 of the 10 orders in a minute went to the new version, and the threshold is 5. The canary knew before the customers did.

## Step 6 [30 min] (5 min): Clean up

```bash
./scripts/teardown.sh
```

Stops running experiments, empties the bucket, deletes the stack. OpsItems stay in OpsCenter, so check that you resolved them. The load generator disappears with the stack. If you skip this step it keeps sending 10 orders a minute.

## Going further

- **The slow outage.** `scripts/chaos.sh start delay` adds 3 seconds to every order for 4 minutes. Errors stay at 0, but `devops-day-lab-consumer-slow` (p95 above 2 seconds) fires. An outage you miss if you only watch the error rate.
- **The virtual API.** `scripts/send.sh 5` puts 5 orders on the bus directly, the same way the shop's API would. Check the dashboard and the `archive/` prefix in S3.

## What on-call means here

In this lab, on-call is whoever confirmed the SNS subscription. Alarms go to the topic, the topic goes to that person.

Real on-call has rotations and escalation: the person changes every week, and an unanswered page moves to the next person. On AWS that was the job of Incident Manager, which stopped accepting new customers on November 7, 2025 (the documentation says it is "no longer open to new customers"). The alternatives AWS points to are OpsCenter and partner services such as PagerDuty. That is why this lab uses SNS and User Notifications for paging, OpsCenter for tickets and an Automation runbook for recovery.

## Retro questions

1. How long did it take from the experiment start to the first alarm? Which value on which alarm would you change to shorten it?
2. What would have happened if you had run the runbook before removing the cause? Could the runbook itself guard against that?
3. Why do the canary alarm and the on-call alarm have different thresholds? If they were the same, which one would break first?

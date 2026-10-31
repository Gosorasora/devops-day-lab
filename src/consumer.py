"""Takes one OrderPlaced event at a time from the orders queue and archives it to S3.

Every order leaves two lines in CloudWatch Logs: a JSON log line (Logs Insights can query its fields) and an
embedded-metric-format line that becomes the DevOpsDayLab/OrdersArchived metric without any SDK call.
BUG=on is the deliberately broken release for the canary-rollback drill. Standard library plus the boto3 that
the Lambda runtime ships; nothing to install, nothing to build.
"""
import json
import os
import time

import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["ARCHIVE_BUCKET"]
BUG = os.environ.get("BUG") == "on"


def log(**fields):
    print(json.dumps(fields, ensure_ascii=False))


def metric(name, value):
    print(json.dumps({"_aws": {"Timestamp": int(time.time() * 1000), "CloudWatchMetrics": [
        {"Namespace": "DevOpsDayLab", "Dimensions": [["Service"]], "Metrics": [{"Name": name, "Unit": "Count"}]}]},
        "Service": "consumer", name: value}))


def handler(event, _context):
    for record in event["Records"]:  # BatchSize is 1, so this is one order
        order = json.loads(record["body"])["detail"]
        started = time.time()
        if BUG:  # "v2": crashes on every order, so the canary alarm fires and CodeDeploy rolls back
            raise RuntimeError(f"v2 bug: cannot price order {order.get('order_id')}")
        time.sleep(0.05)  # pretend to do work, so Duration is a real number on the dashboard
        s3.put_object(Bucket=BUCKET, Key=f"archive/{order['order_id']}.json", Body=json.dumps(order).encode())
        log(level="INFO", msg="order archived", order_id=order["order_id"], item=order.get("item"),
            amount=order.get("amount"), ms=round((time.time() - started) * 1000))
        metric("OrdersArchived", 1)
    return {"archived": len(event["Records"])}

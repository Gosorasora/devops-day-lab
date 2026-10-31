"""python3 test_consumer.py - no network, no boto3 needed (a fake is injected)."""
import contextlib
import io
import json
import os
import sys
import types

puts = []
fake_boto3 = types.ModuleType("boto3")
fake_boto3.client = lambda _name: types.SimpleNamespace(put_object=lambda **kw: puts.append(kw))
sys.modules["boto3"] = fake_boto3
os.environ["ARCHIVE_BUCKET"] = "test-bucket"
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "src"))
import consumer  # noqa: E402

event = {"Records": [{"body": json.dumps({"detail-type": "OrderPlaced", "detail": {"order_id": "o-1", "item": "coffee", "amount": 4500}})}]}

out = io.StringIO()
with contextlib.redirect_stdout(out):
    assert consumer.handler(event, None) == {"archived": 1}
assert puts[0]["Bucket"] == "test-bucket" and puts[0]["Key"] == "archive/o-1.json", puts
lines = [json.loads(line) for line in out.getvalue().splitlines()]
assert lines[0]["msg"] == "order archived" and lines[0]["item"] == "coffee" and lines[0]["amount"] == 4500, lines[0]
assert lines[1]["_aws"]["CloudWatchMetrics"][0]["Namespace"] == "DevOpsDayLab" and lines[1]["OrdersArchived"] == 1, lines[1]

consumer.BUG = True
try:
    consumer.handler(event, None)
    raise AssertionError("BUG=on must raise")
except RuntimeError as e:
    assert "o-1" in str(e)
assert len(puts) == 1, "the broken version must not archive anything"
print("ok")

"""ChatOpsBot ops-status function.

Invoked from Slack through Amazon Q Developer in chat applications:

    @Amazon Q lambda invoke --function-name chatopsbot-ops-status --region <region>

Returns a short, human-readable status summary: which CloudWatch alarms are firing
and the health of any EC2 instances they watch. It only reads, so it is safe to run
from a shared channel.
"""
import os

import boto3

cloudwatch = boto3.client("cloudwatch")
ec2 = boto3.client("ec2")

ALARM_PREFIX = os.environ.get("ALARM_PREFIX", "")


def _alarms():
    """Return every alarm whose name starts with ALARM_PREFIX (all alarms if no prefix)."""
    kwargs = {"AlarmNamePrefix": ALARM_PREFIX} if ALARM_PREFIX else {}
    alarms = []
    for page in cloudwatch.get_paginator("describe_alarms").paginate(**kwargs):
        alarms.extend(page.get("MetricAlarms", []))
    return alarms


def _instance_ids(alarms):
    ids = set()
    for alarm in alarms:
        for dim in alarm.get("Dimensions", []):
            if dim["Name"] == "InstanceId":
                ids.add(dim["Value"])
    return sorted(ids)


def _instance_health(instance_ids):
    if not instance_ids:
        return []
    resp = ec2.describe_instance_status(InstanceIds=instance_ids, IncludeAllInstances=True)
    return [
        {
            "instanceId": s["InstanceId"],
            "state": s["InstanceState"]["Name"],
            "systemStatus": s.get("SystemStatus", {}).get("Status", "n/a"),
            "instanceStatus": s.get("InstanceStatus", {}).get("Status", "n/a"),
        }
        for s in resp.get("InstanceStatuses", [])
    ]


def lambda_handler(event, context):
    alarms = _alarms()
    firing = [a for a in alarms if a["StateValue"] == "ALARM"]
    instances = _instance_health(_instance_ids(alarms))

    lines = [f"ChatOpsBot status: {len(firing)} of {len(alarms)} alarm(s) firing"]
    for a in firing:
        lines.append(f"  ALARM  {a['AlarmName']}: {a.get('StateReason', '')[:160]}")
    for i in instances:
        lines.append(
            f"  EC2    {i['instanceId']}: {i['state']}, "
            f"system {i['systemStatus']}, instance {i['instanceStatus']}"
        )
    if not firing:
        lines.append("  All clear.")

    summary = "\n".join(lines)
    print(summary)  # also lands in CloudWatch Logs for the audit trail
    return {
        "summary": summary,
        "alarmsFiring": [a["AlarmName"] for a in firing],
        "instances": instances,
    }

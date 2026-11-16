# ChatOpsBot – AWS Operations from Slack

**AWS Well-Architected Framework: Operational Excellence Pillar**

Every minute spent switching between the AWS Console, CloudWatch and dashboards slows down incident response. ChatOpsBot brings AWS alerts and operations into Slack, so the team can see an issue and act on it without leaving the channel.

```
 EC2 test instance ──CPU──▶ CloudWatch alarm (> 70%)
                                   │
                                   ▼
                              SNS topic ──────────▶ Email
                                   │
                                   ▼
                Amazon Q Developer in chat applications
                                   │  channel role + guardrail policies
                                   ▼
                             Slack channel
                   ├─ alert and recovery notifications
                   ├─ "describe-alarms" and other read-only commands
                   └─ "lambda invoke" ──▶ ops-status Lambda

 Status dashboard: private S3 bucket ──OAC──▶ CloudFront (HTTPS)
```

## What's in this repo

| Path | What it is |
|---|---|
| `infrastructure/template.yaml` | CloudFormation for everything above |
| `lambda/ops-status/handler.py` | Read-only status function, invoked from Slack |
| `dashboard/index.html` | Static ops reference page served through CloudFront |
| `scripts/deploy.sh`, `scripts/destroy.sh` | Deploy and clean up in one command each |

## Design decisions

- **Alerts go out on both state changes.** The alarm notifies the channel when CPU spikes *and* when it recovers, so nobody has to check whether an incident is still open.
- **Guardrails cap what chat can do.** Slack users get read-only access plus permission to invoke one function, whatever the channel role allows. In my first console build I used the broader `AWSLambda_FullAccess` guardrail. This template narrows it to a single function.
- **No SSH.** The test instance has no inbound rules. You reach it through SSM Session Manager, and it requires IMDSv2.
- **Private dashboard bucket.** Only CloudFront can read the bucket, using Origin Access Control, and HTTP redirects to HTTPS.
- **Detailed monitoring** gives 1-minute metrics, so the alarm fires within about 2 minutes.

## Deploy

**You'll need:**
- The AWS CLI, logged in
- A default VPC in your region (for the test instance)
- An S3 bucket for the packaged Lambda code

**Step 1: connect Slack (one-off, in the console).** Open **Amazon Q Developer in chat applications** and choose **Configure new client → Slack**. Authorise your workspace, then copy the workspace ID. Invite `@Amazon Q` to your channel (`/invite @Amazon Q`) and copy the channel ID. You'll find it under the channel's details.

**Step 2: deploy.**

```bash
./scripts/deploy.sh <artifact-bucket> chatopsbot <region> \
  AlertEmail=<you@example.com> SlackWorkspaceId=<T…> SlackChannelId=<C…>
```

Confirm the SNS subscription email when it arrives. Slack is optional: leave out the two Slack parameters to deploy alerting to email only.

**Step 3: test it.**

1. Open the test instance in **Session Manager** and run `stress-ng --cpu 2 --timeout 300`.
2. Within about 2 minutes, the alarm posts to Slack and sends you an email.
3. In Slack, run:
   ```
   @Amazon Q cloudwatch describe-alarms --state-value ALARM --region <region>
   @Amazon Q lambda invoke --function-name chatopsbot-ops-status --region <region>
   ```
4. When `stress-ng` finishes, the recovery notification arrives.

## Cost and clean-up

A t3.micro with detailed monitoring, one alarm, SNS, Lambda and CloudFront cost pennies per day at this scale. Tear everything down when you're finished:

```bash
./scripts/destroy.sh chatopsbot <region>
```

## Next steps

- **Auto-remediation:** a Lambda triggered by the alarm that fixes the problem and reports what it did in Slack
- **An AI triage agent:** Amazon Bedrock reads the metrics, chooses a remediation from an allow-list, and asks a human in Slack before taking risky actions
- **Custom notifications:** richer Slack messages with runbook links

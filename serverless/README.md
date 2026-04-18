# KGeN Eye — MCAP Builder (Server-side Lambda)

Converts the JSON/JSONL artifacts produced by the iOS capture app into a single
**MCAP** file per session, after the session finishes uploading to S3.

- Trigger: `s3:ObjectCreated:*` on `upload_complete_{sessionCode}.json` (sentinel).
- Runtime: Python 3.12 on arm64 (Graviton).
- Output: `{collectorId}/{sessionCode}/{sessionCode}.mcap` in the same bucket.
- Compression: **none** (per product decision — MCAP chunks stored raw).
- Output layout: **side-by-side** (JSONs remain; MCAP is added alongside).

---

## 1. Repository layout

```
serverless/
├── lambda/
│   ├── handler.py              # S3 event entry point
│   ├── mcap_builder.py         # pure conversion logic (no AWS deps)
│   ├── requirements.txt        # mcap library
│   └── schemas/                # one JSON Schema per channel
├── scripts/
│   └── attach_s3_notification.sh   # idempotent S3 notification wiring
├── template.yaml               # SAM template (Lambda, DLQ, alarm)
├── samconfig.toml              # default deploy params (us-east-1, kaivideo)
├── local_test.py               # run the builder locally on a session dir
└── README.md
```

Session → MCAP channel mapping:

| Input file                                  | MCAP topic              | Type       |
| ------------------------------------------- | ----------------------- | ---------- |
| `imu_{code}.jsonl`                          | `/sensors/imu`          | JSONL      |
| `video_timestamps_{code}.jsonl`             | `/camera/frame_meta`    | JSONL      |
| `metadata_{code}.json`                      | `/session/metadata`     | single JSON|
| `technical_validation_{code}.json`          | `/session/validation`   | single JSON|
| `camera_format_diagnostics_{code}.json`     | `/camera/formats`       | single JSON|
| `session_manifest_{code}.json`              | `/session/manifest`     | single JSON|

> `video_{code}.mp4` is **not** embedded in the MCAP — it stays as a separate
> S3 object for efficient browser playback.

---

## 2. Prerequisites

1. Install AWS CLI v2 and authenticate as a principal that can:
   - Create IAM roles, Lambda functions, SQS queues, CloudWatch alarms, and CloudFormation stacks.
   - Put bucket notifications on `kaivideo`.
2. Install [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html).
3. Install `jq` (used by the notification wiring script).
4. Install Docker (SAM uses it to build the Python dependency layer for Linux/arm64).

```bash
aws --version
sam --version
jq --version
docker --version
```

---

## 3. First-time deploy

From `serverless/`:

```bash
# 1) Build the function + deps inside a Linux container (required for native wheels).
sam build --use-container

# 2) Deploy. First run is interactive; subsequent runs honour samconfig.toml.
sam deploy --guided
# When prompted:
#   Stack Name                 : kgen-eye-mcap-builder
#   AWS Region                 : us-east-1
#   Confirm changes before deploy: Y
#   Allow SAM CLI IAM role creation : Y
#   Save arguments to configuration file : Y
```

SAM will create:
- Lambda function `kgen-eye-mcap-builder` (arm64, Python 3.12, 1024 MB, 300 s).
- IAM role with `S3ReadPolicy` + `S3WritePolicy` scoped to `kaivideo`.
- SQS DLQ `kgen-eye-mcap-builder-dlq` (14-day retention).
- CloudWatch alarm `kgen-eye-mcap-builder-dlq-not-empty`.
- `lambda:InvokePermission` allowing S3 to call the function.

### 3.1 Wire up the S3 notification (once)

```bash
./scripts/attach_s3_notification.sh
# Variables (all optional):
#   BUCKET=kaivideo
#   STACK_NAME=kgen-eye-mcap-builder
#   AWS_REGION=us-east-1
```

The script is idempotent: it preserves any pre-existing notification
configurations on the bucket (Queue, Topic, other Lambda targets) and only
replaces/inserts its own entry with `Id=kgen-eye-mcap-builder-sentinel`.

---

## 4. Subsequent deploys

```bash
sam build --use-container && sam deploy
```

The notification script only needs to be re-run if the Lambda ARN changes
(e.g. stack was deleted and recreated).

---

## 5. Local testing (no AWS needed)

```bash
# One-time: set up a venv with the mcap lib.
python3 -m venv .venv && source .venv/bin/activate
pip install -r lambda/requirements.txt

# Run against a real session dumped from the phone/S3.
python3 local_test.py /path/to/qB7nX3_mL9Vz qB7nX3_mL9Vz
# → writes qB7nX3_mL9Vz.mcap into that folder and prints channel counts.
```

Open the resulting file in [Foxglove Studio](https://foxglove.dev/) to verify:
- IMU at ~100 Hz on `/sensors/imu`.
- Frame metadata at ~30 Hz on `/camera/frame_meta`.
- One-shot messages on `/session/metadata`, `/session/validation`, `/camera/formats`, `/session/manifest`.

---

## 6. iOS sentinel (already in this repo)

`EgoCapture/Services/Upload/UploadManager.swift` writes and uploads
`upload_complete_{sessionId}.json` **as the last object** once every other
file has successfully landed. This is what fires the Lambda.

Sentinel payload:
```json
{
  "sessionId":     "qB7nX3_mL9Vz",
  "collectorId":   "alice",
  "completedAt":   1729432800000.0,
  "uploadedFiles": 42,
  "version":       1
}
```

---

## 7. Observability

- **CloudWatch Logs** — log group `/aws/lambda/kgen-eye-mcap-builder`.
  - Each invocation prints downloaded file count, per-channel message counts, and final S3 key.
- **DLQ alarm** — fires when ≥1 message in the SQS DLQ, which means Lambda
  failed every automatic retry (two retries by default).
- **Metrics** — standard Lambda metrics (Invocations, Errors, Duration, Throttles).

### Checking a DLQ message

```bash
aws sqs receive-message --queue-url $(aws cloudformation describe-stacks \
  --stack-name kgen-eye-mcap-builder \
  --query "Stacks[0].Outputs[?OutputKey=='DLQUrl'].OutputValue" --output text) \
  --max-number-of-messages 1
```

The SQS body contains the original S3 event — you can re-invoke the Lambda
manually with it after fixing the root cause.

---

## 8. Troubleshooting

| Symptom                                   | Likely cause                                         | Fix |
| ----------------------------------------- | ---------------------------------------------------- | --- |
| Lambda never fires                         | Bucket notification not attached.                    | Re-run `scripts/attach_s3_notification.sh`. |
| Lambda fires but "not a sentinel"          | Normal — it only builds on the sentinel upload.      | Ignore. |
| `FileNotFoundError: no MCAP-relevant...`   | iOS uploaded the sentinel before the JSONs.           | Bug in iOS sequencing — sentinel must be LAST. |
| `MemoryError` / timeout                    | Very long session (> 1 h).                            | Bump `MemorySize`/`Timeout` in `template.yaml`. |
| `AccessDenied` on `s3:PutObject`            | IAM role lost permissions.                            | Redeploy the stack. |

---

## 9. Re-running a session manually

```bash
aws lambda invoke \
  --function-name kgen-eye-mcap-builder \
  --payload "$(cat <<EOF
{
  "Records": [{
    "s3": {
      "bucket": { "name": "kaivideo" },
      "object": { "key": "alice/qB7nX3_mL9Vz/upload_complete_qB7nX3_mL9Vz.json" }
    }
  }]
}
EOF
)" \
  --cli-binary-format raw-in-base64-out \
  /tmp/mcap-invoke.json

cat /tmp/mcap-invoke.json
```

---

## 10. Tear-down

```bash
# Remove the S3 notification first (optional; leaving it is harmless).
# Then:
sam delete --stack-name kgen-eye-mcap-builder --region us-east-1
```

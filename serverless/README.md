# Humyn Labs MCAP Builder (Server-side Lambda)

Converts the JSON/JSONL + MP4 artifacts produced by the iOS capture app
into a single **Figure-compliant MCAP** per session, once the session has
finished uploading to S3.

- Trigger: `s3:ObjectCreated:*` on `upload_complete_{sessionCode}.json` (sentinel).
- Runtime: Python 3.12 on arm64 (Graviton), 2 GB RAM, 4 GB ephemeral storage.
- Output: `{collectorId}/{sessionCode}/{sessionCode}.mcap` in the same bucket.
- Compression: **zstd** chunks (required by Humyn Labs / Figure spec v1.0.0).
- Video: **H.264 embedded** inside the MCAP (`foxglove.CompressedVideo`) — no MP4 sidecar consumed by downstream.

---

## 1. Output schema (v1.0.0)

Six channels, all JSON bodies validated against JSON Schema Draft 7:

| # | Topic                      | Schema                        | Rate       |
|---|----------------------------|-------------------------------|------------|
| 1 | `/camera/head/video`       | `foxglove.CompressedVideo`    | 30 Hz      |
| 2 | `/camera/head/calibration` | `foxglove.CameraCalibration`  | 1×         |
| 3 | `/sensors/head/imu`        | `foxglove.Imu`                | 100–250 Hz |
| 4 | `/tf`                      | `foxglove.FrameTransform`     | 1×         |
| 5 | `/session/metadata`        | `humynlabs.SessionMetadata`   | 1× (head)  |
| 6 | `/session/metrics`         | `humynlabs.SessionMetrics`    | 1× (tail)  |

Key conversions applied inside the Lambda:

- **IMU accelerometer** → multiplied by `9.80665` (g → m/s²). Gyroscope stays
  in rad/s. Timestamps collapse to a single `{sec, nsec}` epoch domain.
- **Video**: each MP4 sample (or every sample across every `chunk_NNN_*.mp4`)
  is converted from AVCC length-prefix framing to H.264 Annex B start codes,
  SPS/PPS are prepended to every IDR, base64-encoded, and paired with the
  iOS-captured frame timestamp.
- **Camera calibration**: `K = [fx, 0, cx, 0, fy, cy, 0, 0, 1]` built from the
  iOS `cameraIntrinsics`. Distortion model mapped to OpenCV names; coefficients
  emitted as zeros when iOS reports no distortion (AVFoundation rectifies).
- **Frame transform** (`/tf`): static extrinsic `head_center → head_camera` from
  the iOS `cameraExtrinsics.rotationQuaternion` + `translationMeters`.
- **Session metrics**: *measurements only* — no pass/fail verdicts. The old
  `TechnicalValidation.passCriteria` block is intentionally dropped.

Obsolete channels removed: `/camera/formats`, `/session/manifest`,
`/session/validation`, `/camera/frame_meta`, `/sensors/imu`.

---

## 2. Repository layout

```
serverless/
├── lambda/
│   ├── handler.py              # S3 event entry point
│   ├── mcap_builder.py         # channel orchestrator + writer
│   ├── transforms.py           # per-channel unit / schema conversions
│   ├── video_extractor.py      # MP4 (AVCC) → H.264 Annex B (pure Python)
│   ├── requirements.txt        # mcap, zstandard
│   └── schemas/                # 6 JSON schemas (Foxglove + Humyn Labs)
├── scripts/
│   ├── attach_s3_notification.sh    # idempotent S3 notification wiring
│   └── regenerate_mcaps.sh          # re-emit MCAPs for pre-existing sessions
├── template.yaml               # SAM template (Lambda, DLQ, alarm)
├── samconfig.toml              # default deploy params
├── local_test.py               # run the builder locally on a session dir
└── README.md
```

---

## 3. Prerequisites

1. Install AWS CLI v2 and authenticate as a principal that can:
   - Create IAM roles, Lambda functions, SQS queues, CloudWatch alarms, CloudFormation stacks.
   - Put bucket notifications on `kaivideo`.
2. Install [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html).
3. Install `jq` (used by both scripts).
4. Install Docker (SAM uses it to build the `zstandard` native wheel for arm64).

---

## 4. First-time deploy

From `serverless/`:

```bash
# 1) Build the function + deps inside a Linux container (required for native wheels).
sam build --use-container

# 2) Deploy.
sam deploy --guided
#   Stack Name               : kgen-eye-mcap-builder
#   AWS Region               : us-east-1
#   Confirm changes          : Y
#   Allow IAM role creation  : Y
#   Save args                : Y
```

SAM provisions:
- Lambda `kgen-eye-mcap-builder` (arm64, Python 3.12, 2 GB RAM, 600 s timeout, 4 GB ephemeral).
- IAM role with `S3ReadPolicy` + `S3WritePolicy` scoped to `kaivideo`.
- SQS DLQ `kgen-eye-mcap-builder-dlq` (14-day retention).
- CloudWatch alarm on DLQ > 0.

### 4.1 Wire up the S3 notification (once)

```bash
./scripts/attach_s3_notification.sh
```

Idempotent: preserves any unrelated bucket notifications.

---

## 5. Subsequent deploys

```bash
sam build --use-container && sam deploy
```

---

## 6. Regenerating MCAPs for existing sessions

When the schema changes, every pre-existing `.mcap` must be re-emitted.
The source artifacts (JSONs + MP4 chunks) never move, so we just re-invoke
the Lambda for each session's sentinel key:

```bash
# Dry run first (no Lambda calls, just the list of sessions it will touch).
./scripts/regenerate_mcaps.sh --dry-run

# Full re-run (synchronous; prints per-session status).
./scripts/regenerate_mcaps.sh

# Fire-and-forget (much faster; watch CloudWatch for results).
./scripts/regenerate_mcaps.sh --async

# Narrow the blast radius while testing.
./scripts/regenerate_mcaps.sh --prefix alice/ --limit 5
```

Each invocation overwrites the existing `.mcap` in-place.

---

## 7. Local testing (no AWS needed)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r lambda/requirements.txt

python3 local_test.py /path/to/qB7nX3_mL9Vz qB7nX3_mL9Vz
# → writes qB7nX3_mL9Vz.mcap into that folder and prints channel counts.

# Skip the MP4 step for a fast IMU/metadata-only iteration:
python3 local_test.py /path/to/qB7nX3_mL9Vz qB7nX3_mL9Vz --no-video
```

Open the resulting file in [Foxglove Studio](https://foxglove.dev/) to verify:
- Video plays on `/camera/head/video` (Image / Video panel).
- IMU at ~100 Hz on `/sensors/head/imu`.
- TF tree `head_center → head_camera` populated.
- `/session/metadata` and `/session/metrics` each have one row.

---

## 8. iOS sentinel (already in this repo)

`EgoCapture/Services/Upload/UploadManager.swift` writes and uploads
`upload_complete_{sessionId}.json` **as the last object** once every other
file (JSONs + `chunk_NNN_<code>.mp4`) has successfully landed. This is what
fires the Lambda.

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

## 9. Observability

- **CloudWatch Logs** — group `/aws/lambda/kgen-eye-mcap-builder`.
  Every invocation prints: downloaded file count, per-channel message counts,
  number of skipped channels, and the final S3 key.
- **DLQ alarm** — fires on ≥ 1 message (Lambda failed every retry).
- **Metrics** — standard Lambda `Invocations / Errors / Duration / Throttles`.

### Checking a DLQ message

```bash
aws sqs receive-message --queue-url $(aws cloudformation describe-stacks \
  --stack-name kgen-eye-mcap-builder \
  --query "Stacks[0].Outputs[?OutputKey=='DLQUrl'].OutputValue" --output text) \
  --max-number-of-messages 1
```

The SQS body contains the original S3 event — replay it manually after a fix.

---

## 10. Troubleshooting

| Symptom                                      | Likely cause                                              | Fix |
| -------------------------------------------- | --------------------------------------------------------- | --- |
| Lambda never fires                            | Bucket notification not attached.                         | Re-run `scripts/attach_s3_notification.sh`. |
| Lambda fires but `"skipped": true`            | Normal — only builds on the sentinel upload.              | Ignore. |
| `FileNotFoundError: no MCAP-relevant...`      | iOS uploaded the sentinel before the JSONs.               | Bug in iOS sequencing — sentinel must be LAST. |
| `[/camera/head/video] cannot parse MP4`       | Chunked upload where one chunk is truncated.              | Re-upload the chunk; re-run `regenerate_mcaps.sh --prefix <that session>`. |
| `/camera/head/calibration` absent             | `cameraIntrinsics` missing in `metadata_<code>.json`.     | Upgrade the iOS app to a build that populates intrinsics. |
| Duration clamped to 120 s in metadata        | Session shorter than Figure's minimum.                    | Record ≥ 2 min; the metrics body still reports the true duration. |
| `MemoryError` / timeout                       | Very long session (> 15 min) or very large MP4.           | Bump `MemorySize`/`Timeout`/`EphemeralStorage` in `template.yaml`. |
| `AccessDenied` on `s3:PutObject`              | IAM role lost permissions.                                | Redeploy the stack. |

---

## 11. Re-running a single session manually

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

## 12. Tear-down

```bash
sam delete --stack-name kgen-eye-mcap-builder --region us-east-1
```

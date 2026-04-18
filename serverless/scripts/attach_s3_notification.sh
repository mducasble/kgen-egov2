#!/usr/bin/env bash
# Attaches an S3 ObjectCreated notification to the existing `kaivideo` bucket so
# that uploads of the sentinel file (upload_complete_*.json) invoke the MCAP
# builder Lambda. Run this ONCE after the SAM stack is deployed.
#
# Requires: AWS CLI v2 configured for the target account; the SAM stack must be
# deployed first so McapBuilderS3InvokePermission exists.

set -euo pipefail

BUCKET="${BUCKET:-kaivideo}"
STACK_NAME="${STACK_NAME:-kgen-eye-mcap-builder}"
REGION="${AWS_REGION:-us-east-1}"

echo "→ resolving Lambda ARN from stack ${STACK_NAME} in ${REGION}..."
LAMBDA_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionArn'].OutputValue" \
  --output text)

if [[ -z "${LAMBDA_ARN}" || "${LAMBDA_ARN}" == "None" ]]; then
  echo "ERROR: could not find Lambda ARN. Is the stack deployed?" >&2
  exit 1
fi
echo "   Lambda ARN: ${LAMBDA_ARN}"

echo "→ fetching current bucket notification configuration..."
CURRENT=$(aws s3api get-bucket-notification-configuration \
  --bucket "${BUCKET}" \
  --region "${REGION}" 2>/dev/null)
# Treat empty output as an empty configuration object.
[[ -z "${CURRENT// }" ]] && CURRENT='{}'

# Merge: keep any pre-existing Topic/Queue/Lambda configurations and replace/insert
# ours (stable Id makes re-runs idempotent).
NEW_CONFIG=$(jq -c --arg arn "${LAMBDA_ARN}" '
  . as $cur
  | ($cur.LambdaFunctionConfigurations // []) as $existing
  | ($cur // {})
    | del(.LambdaFunctionConfigurations)
    | . + {
        LambdaFunctionConfigurations: (
          ($existing | map(select(.Id != "kgen-eye-mcap-builder-sentinel"))) + [
            {
              Id: "kgen-eye-mcap-builder-sentinel",
              LambdaFunctionArn: $arn,
              Events: ["s3:ObjectCreated:*"],
              Filter: {
                Key: {
                  FilterRules: [
                    { Name: "suffix", Value: ".json" }
                  ]
                }
              }
            }
          ]
        )
      }
' <<< "${CURRENT}")

if [[ -z "${NEW_CONFIG// }" ]]; then
  echo "ERROR: jq produced empty notification config; aborting." >&2
  exit 1
fi

echo "→ putting new notification configuration..."
aws s3api put-bucket-notification-configuration \
  --bucket "${BUCKET}" \
  --region "${REGION}" \
  --notification-configuration "${NEW_CONFIG}"

echo "OK. ${BUCKET} will now invoke ${LAMBDA_ARN} on any .json ObjectCreated event."
echo "The Lambda itself filters for the sentinel pattern (upload_complete_<code>.json)."

#!/usr/bin/env bash
# Re-invokes the Humyn Labs MCAP builder Lambda for every existing session
# in the S3 bucket, so legacy .mcap files are rewritten in the new format.
#
# Each session is identified by the sentinel that originally triggered the
# Lambda (``upload_complete_<sessionCode>.json``). We list every sentinel,
# build a synthetic S3 event mimicking the real trigger, and call
# ``aws lambda invoke`` for each one.
#
# Flags:
#   --dry-run       Print what would be invoked without calling the Lambda.
#   --async         Invoke with InvocationType=Event (fire-and-forget,
#                   fastest; results only visible in CloudWatch).
#   --prefix <p>    Only process sentinels under this S3 key prefix.
#   --limit <n>     Process at most N sessions (handy for smoke tests).
#
# Env vars (all optional):
#   BUCKET=kaivideo
#   STACK_NAME=kgen-eye-mcap-builder
#   AWS_REGION=us-east-1
#   FUNCTION_NAME=kgen-eye-mcap-builder
#
# Requires: aws CLI v2, jq.

set -euo pipefail

BUCKET="${BUCKET:-kaivideo}"
STACK_NAME="${STACK_NAME:-kgen-eye-mcap-builder}"
REGION="${AWS_REGION:-us-east-1}"
FUNCTION_NAME="${FUNCTION_NAME:-kgen-eye-mcap-builder}"

DRY_RUN=0
ASYNC=0
PREFIX=""
LIMIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=1; shift ;;
    --async)    ASYNC=1; shift ;;
    --prefix)   PREFIX="$2"; shift 2 ;;
    --limit)    LIMIT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Resolve the live function name (a rename in template.yaml shouldn't break us).
if ! aws lambda get-function --function-name "${FUNCTION_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "ERROR: Lambda '${FUNCTION_NAME}' not found in ${REGION}. Deploy the stack first." >&2
  exit 1
fi

echo "→ listing sentinels in s3://${BUCKET}/${PREFIX}..."

TMP_LIST="$(mktemp)"
TMP_PAYLOAD="$(mktemp)"
TMP_RESPONSE="$(mktemp)"
trap 'rm -f "${TMP_LIST}" "${TMP_PAYLOAD}" "${TMP_RESPONSE}"' EXIT

aws s3api list-objects-v2 \
  --bucket "${BUCKET}" \
  --prefix "${PREFIX}" \
  --region "${REGION}" \
  --query "Contents[?ends_with(Key, '.json') && contains(Key, 'upload_complete_')].Key" \
  --output text \
  | tr '\t' '\n' \
  | grep -E '^.+/upload_complete_[A-Za-z0-9_-]{8,32}\.json$' \
  > "${TMP_LIST}" || true

TOTAL=$(wc -l < "${TMP_LIST}" | tr -d ' ')
if [[ "${TOTAL}" -eq 0 ]]; then
  echo "no sentinels found — nothing to regenerate."
  exit 0
fi

if [[ "${LIMIT}" -gt 0 ]]; then
  head -n "${LIMIT}" "${TMP_LIST}" > "${TMP_LIST}.limited"
  mv "${TMP_LIST}.limited" "${TMP_LIST}"
  TOTAL=$(wc -l < "${TMP_LIST}" | tr -d ' ')
fi

echo "→ will process ${TOTAL} session(s)."
[[ "${DRY_RUN}" -eq 1 ]] && echo "   (dry-run: no Lambda calls will be made)"

INVOCATION_TYPE="RequestResponse"
[[ "${ASYNC}" -eq 1 ]] && INVOCATION_TYPE="Event"

OK=0
FAIL=0
IDX=0
while IFS= read -r KEY; do
  IDX=$((IDX + 1))
  [[ -z "${KEY}" ]] && continue

  jq -nc --arg bucket "${BUCKET}" --arg key "${KEY}" '{
    Records: [
      { s3: { bucket: { name: $bucket }, object: { key: $key } } }
    ]
  }' > "${TMP_PAYLOAD}"

  printf "[%d/%d] %s ... " "${IDX}" "${TOTAL}" "${KEY}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "skipped (dry-run)"
    continue
  fi

  if aws lambda invoke \
       --function-name "${FUNCTION_NAME}" \
       --region "${REGION}" \
       --invocation-type "${INVOCATION_TYPE}" \
       --payload "fileb://${TMP_PAYLOAD}" \
       --cli-binary-format raw-in-base64-out \
       "${TMP_RESPONSE}" >/dev/null 2>&1; then
    if [[ "${INVOCATION_TYPE}" == "Event" ]]; then
      echo "queued"
    else
      # Pick off the top-level 'ok' field of the first record so users see
      # something actionable without having to pipe through jq themselves.
      SUMMARY=$(jq -rc '.results[0] // .' < "${TMP_RESPONSE}" 2>/dev/null || cat "${TMP_RESPONSE}")
      echo "${SUMMARY}"
    fi
    OK=$((OK + 1))
  else
    echo "FAILED"
    FAIL=$((FAIL + 1))
  fi
done < "${TMP_LIST}"

echo
echo "done: ${OK} ok, ${FAIL} failed, ${TOTAL} total."
[[ "${FAIL}" -gt 0 ]] && exit 2 || exit 0

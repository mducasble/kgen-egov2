"""AWS Lambda entry point for the KGeN Eye MCAP builder.

Trigger: S3 ObjectCreated event filtered to `upload_complete_*.json` (the sentinel file).

Flow:
  1. Parse S3 event → extract bucket + key for each record.
  2. Validate the key ends with the sentinel pattern and lives under `<collectorId>/<sessionCode>/`.
  3. Download the whole session prefix into `/tmp/<sessionCode>/`.
  4. Build `<sessionCode>.mcap` using `mcap_builder.build_mcap`.
  5. Upload it back to `s3://<bucket>/<collectorId>/<sessionCode>/<sessionCode>.mcap`.
  6. Return a per-record result list (for CloudWatch/Lambda Insights).

Layout assumption (Option A): JSONs remain in-place; the `.mcap` is written alongside them.
"""

from __future__ import annotations

import json
import logging
import os
import re
import shutil
from pathlib import Path
from typing import Any
from urllib.parse import unquote_plus

import boto3

from mcap_builder import build_mcap

log = logging.getLogger()
log.setLevel(logging.INFO)

s3 = boto3.client("s3")

# Matches <anything>/<sessionCode>/upload_complete_<sessionCode>.json
SENTINEL_RE = re.compile(
    r"^(?P<prefix>.+?)/(?P<code>[A-Za-z0-9_-]{8,32})/upload_complete_(?P=code)\.json$"
)

# Artifacts we actually need to build the MCAP. Anything else (video_*.mp4,
# chunk_*, upload_state_*) is intentionally skipped to keep /tmp small.
DOWNLOAD_BASES = (
    "imu",
    "video_timestamps",
    "metadata",
    "technical_validation",
    "camera_format_diagnostics",
    "session_manifest",
)


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Lambda entry point. Processes every record in the S3 event."""
    log.info("received event with %d record(s)", len(event.get("Records", [])))

    results: list[dict[str, Any]] = []
    for record in event.get("Records", []):
        try:
            result = _process_record(record)
        except Exception as e:  # noqa: BLE001 — surface every failure to CloudWatch
            log.exception("record failed: %s", e)
            result = {"ok": False, "error": str(e), "record": record.get("s3", {})}
        results.append(result)

    return {"results": results}


def _process_record(record: dict[str, Any]) -> dict[str, Any]:
    s3_info = record["s3"]
    bucket = s3_info["bucket"]["name"]
    key = unquote_plus(s3_info["object"]["key"])

    match = SENTINEL_RE.match(key)
    if not match:
        log.info("ignoring non-sentinel key: %s", key)
        return {"ok": True, "skipped": True, "reason": "not a sentinel", "key": key}

    prefix = match.group("prefix")            # e.g. "collectorA"  (may contain sub-prefixes)
    session_code = match.group("code")         # e.g. "qB7nX3_mL9Vz"
    session_prefix = f"{prefix}/{session_code}/"

    log.info("building MCAP for bucket=%s prefix=%s code=%s", bucket, session_prefix, session_code)

    work_dir = Path("/tmp") / session_code
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)

    try:
        _download_session_artifacts(bucket, session_prefix, session_code, work_dir)

        out_name = f"{session_code}.mcap"
        out_path = work_dir / out_name
        stats = build_mcap(
            session_dir=work_dir,
            session_code=session_code,
            output_path=out_path,
        )

        if stats.total_messages == 0:
            log.warning("no messages emitted — uploading empty MCAP anyway for traceability")

        mcap_key = f"{session_prefix}{out_name}"
        s3.upload_file(
            Filename=str(out_path),
            Bucket=bucket,
            Key=mcap_key,
            ExtraArgs={"ContentType": "application/octet-stream"},
        )
        log.info(
            "uploaded %s (messages=%d, skipped_channels=%s)",
            mcap_key, stats.total_messages, stats.skipped_channels,
        )

        return {
            "ok": True,
            "bucket": bucket,
            "mcapKey": mcap_key,
            "sessionCode": session_code,
            "messages": stats.total_messages,
            "channels": stats.channel_counts,
            "skippedChannels": stats.skipped_channels,
        }
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


def _download_session_artifacts(
    bucket: str,
    session_prefix: str,
    session_code: str,
    dest: Path,
) -> None:
    """Download only the JSON/JSONL artifacts we need to build the MCAP.

    We do NOT download video.mp4 or chunk_*.mp4 — they would blow past /tmp limits
    and are not part of the MCAP output anyway.
    """
    paginator = s3.get_paginator("list_objects_v2")
    needed_suffixes = tuple(
        f"{base}_{session_code}.{ext}"
        for base in DOWNLOAD_BASES
        for ext in ("json", "jsonl")
    ) + tuple(f"{base}.{ext}" for base in DOWNLOAD_BASES for ext in ("json", "jsonl"))

    downloaded = 0
    for page in paginator.paginate(Bucket=bucket, Prefix=session_prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            filename = key.rsplit("/", 1)[-1]
            if not filename.endswith(needed_suffixes):
                continue
            local = dest / filename
            s3.download_file(Bucket=bucket, Key=key, Filename=str(local))
            downloaded += 1
            log.debug("downloaded %s (%d bytes)", filename, obj.get("Size", 0))

    if downloaded == 0:
        raise FileNotFoundError(
            f"no MCAP-relevant artifacts found under s3://{bucket}/{session_prefix}"
        )
    log.info("downloaded %d artifact(s) to %s", downloaded, dest)

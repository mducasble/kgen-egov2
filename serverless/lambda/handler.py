"""AWS Lambda entry point for the Humyn Labs MCAP builder.

Trigger: S3 ObjectCreated event filtered to ``upload_complete_*.json``
(the iOS sentinel upload).

Flow:
  1. Parse the S3 event and extract the bucket + key for each record.
  2. Validate the key ends with the sentinel pattern and lives under
     ``<prefix>/<sessionCode>/``.
  3. Download the session's JSON artifacts **and** every
     ``chunk_<NNN>_<code>.mp4`` video chunk (or a consolidated
     ``video_<code>.mp4`` when present) into ``/tmp/<sessionCode>/``.
  4. Build ``<sessionCode>.mcap`` with :func:`mcap_builder.build_mcap`.
     The builder extracts H.264 NAL units from each chunk in order and
     embeds them as ``foxglove.CompressedVideo`` messages — no sidecar
     MP4 in the output.
  5. Upload the MCAP to
     ``s3://<bucket>/<prefix>/<sessionCode>/<sessionCode>.mcap``.

Deliberately side-by-side: JSONs and chunks stay in place so humans can
still inspect them out-of-band. The .mcap is additive.
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
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

s3 = boto3.client("s3")

# Matches <anything>/<sessionCode>/upload_complete_<sessionCode>.json
SENTINEL_RE = re.compile(
    r"^(?P<prefix>.+?)/(?P<code>[A-Za-z0-9_-]{8,32})/upload_complete_(?P=code)\.json$"
)

# Artifacts required to build the new (Humyn Labs) MCAP. We still skip
# incidental files (upload_state_*, etc.) to keep /tmp usage predictable.
JSON_BASES = (
    "imu",
    "video_timestamps",
    "metadata",
    "technical_validation",
)


def _consolidated_video_name(code: str) -> str:
    """Name the iOS app uses when it uploads the un-chunked MP4 directly."""
    return f"video_{code}.mp4"


# Matches ``chunk_<NNN>_<sessionCode>.mp4`` — the default chunked upload
# (see ``VideoChunkingService.swift``).
def _chunk_re(session_code: str) -> "re.Pattern[str]":
    return re.compile(rf"^chunk_(\d+)_{re.escape(session_code)}\.mp4$")


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

    prefix = match.group("prefix")
    session_code = match.group("code")
    session_prefix = f"{prefix}/{session_code}/"

    log.info(
        "building MCAP for bucket=%s prefix=%s code=%s",
        bucket, session_prefix, session_code,
    )

    work_dir = Path("/tmp") / session_code
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)

    try:
        video_paths = _download_session_artifacts(bucket, session_prefix, session_code, work_dir)

        out_name = f"{session_code}.mcap"
        out_path = work_dir / out_name
        stats = build_mcap(
            session_dir=work_dir,
            session_code=session_code,
            output_path=out_path,
            video_paths=video_paths,
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
            "uploaded %s (messages=%d, skipped_channels=%s, video_embedded=%s)",
            mcap_key, stats.total_messages, stats.skipped_channels, stats.video_embedded,
        )

        return {
            "ok": True,
            "bucket": bucket,
            "mcapKey": mcap_key,
            "sessionCode": session_code,
            "messages": stats.total_messages,
            "channels": stats.channel_counts,
            "skippedChannels": stats.skipped_channels,
            "videoEmbedded": stats.video_embedded,
        }
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


def _download_session_artifacts(
    bucket: str,
    session_prefix: str,
    session_code: str,
    dest: Path,
) -> list[Path]:
    """Download JSON artifacts + every video MP4 chunk into ``dest``.

    Returns an ordered list of MP4 paths (by chunk index) ready to be fed
    to the builder. Each chunk is a standalone, valid MP4 produced by
    iOS's ``AVAssetExportPresetPassthrough``, so they **cannot** be
    concatenated as raw bytes — the builder handles them as a sequence of
    independent containers instead.

    If a legacy consolidated ``video_<code>.mp4`` exists it is returned as
    a single-element list (older sessions, or the local dev path).
    """
    paginator = s3.get_paginator("list_objects_v2")

    json_suffixes = tuple(
        f"{base}_{session_code}.{ext}"
        for base in JSON_BASES
        for ext in ("json", "jsonl")
    ) + tuple(
        f"{base}.{ext}" for base in JSON_BASES for ext in ("json", "jsonl")
    )

    consolidated = _consolidated_video_name(session_code)
    chunk_re = _chunk_re(session_code)

    json_count = 0
    chunks: list[tuple[int, Path]] = []
    consolidated_path: Path | None = None

    for page in paginator.paginate(Bucket=bucket, Prefix=session_prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            filename = key.rsplit("/", 1)[-1]
            local = dest / filename

            if filename == consolidated:
                s3.download_file(Bucket=bucket, Key=key, Filename=str(local))
                consolidated_path = local
                log.info(
                    "downloaded consolidated video %s (%d bytes)",
                    filename, obj.get("Size", 0),
                )
                continue

            m = chunk_re.match(filename)
            if m is not None:
                seq = int(m.group(1))
                s3.download_file(Bucket=bucket, Key=key, Filename=str(local))
                chunks.append((seq, local))
                log.debug("downloaded chunk #%d %s (%d bytes)",
                          seq, filename, obj.get("Size", 0))
                continue

            if filename.endswith(json_suffixes):
                s3.download_file(Bucket=bucket, Key=key, Filename=str(local))
                json_count += 1
                log.debug("downloaded %s (%d bytes)", filename, obj.get("Size", 0))

    if json_count == 0:
        raise FileNotFoundError(
            f"no MCAP-relevant JSON artifacts found under s3://{bucket}/{session_prefix}"
        )
    log.info("downloaded %d JSON artifact(s) to %s", json_count, dest)

    if consolidated_path is not None:
        return [consolidated_path]

    if chunks:
        chunks.sort(key=lambda t: t[0])
        log.info("fetched %d video chunk(s)", len(chunks))
        return [path for _, path in chunks]

    log.info("no MP4 chunks found under s3://%s/%s — video channel will be skipped",
             bucket, session_prefix)
    return []

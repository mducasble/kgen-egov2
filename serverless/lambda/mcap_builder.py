"""Builds a single-session MCAP file from the JSON/JSONL artifacts produced by the iOS capture app.

Design goals:
- **Deterministic.** Re-running on the same inputs produces byte-identical output (modulo MCAP
  library version), so this Lambda is idempotent.
- **Partial-tolerant.** Missing artifacts are logged and skipped — the MCAP still gets written.
- **Wall-clock timestamps.** Every message uses epoch nanoseconds so cross-session inspection
  works in Foxglove.
- **No compression** (per user request — MCAP chunk compression disabled).
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Optional

from mcap.writer import Writer, CompressionType

log = logging.getLogger(__name__)

# ----------------------------------------------------------------------------
# Channel registry — maps input file to channel name, schema file, encoding.
# ----------------------------------------------------------------------------

JSON_SCHEMA_ENCODING = "jsonschema"
JSON_MESSAGE_ENCODING = "json"

SCHEMAS_DIR = Path(__file__).resolve().parent / "schemas"


@dataclass(frozen=True)
class ChannelSpec:
    """A single MCAP channel wired to one of the session's JSON artifacts."""
    topic: str
    schema_file: str
    schema_name: str
    # True if the source file is JSONL (one message per line); False if single-object JSON.
    is_jsonl: bool
    # "base" name (without _{code}) matching the on-disk file in the session dir.
    source_base: str
    source_ext: str


CHANNELS: list[ChannelSpec] = [
    ChannelSpec(
        topic="/sensors/imu",
        schema_file="imu_sample.schema.json",
        schema_name="IMUSample",
        is_jsonl=True,
        source_base="imu",
        source_ext="jsonl",
    ),
    ChannelSpec(
        topic="/camera/frame_meta",
        schema_file="video_frame_meta.schema.json",
        schema_name="VideoFrameMeta",
        is_jsonl=True,
        source_base="video_timestamps",
        source_ext="jsonl",
    ),
    ChannelSpec(
        topic="/session/metadata",
        schema_file="session_metadata.schema.json",
        schema_name="SessionMetadata",
        is_jsonl=False,
        source_base="metadata",
        source_ext="json",
    ),
    ChannelSpec(
        topic="/session/validation",
        schema_file="technical_validation.schema.json",
        schema_name="TechnicalValidation",
        is_jsonl=False,
        source_base="technical_validation",
        source_ext="json",
    ),
    ChannelSpec(
        topic="/camera/formats",
        schema_file="camera_formats.schema.json",
        schema_name="CameraFormats",
        is_jsonl=False,
        source_base="camera_format_diagnostics",
        source_ext="json",
    ),
    ChannelSpec(
        topic="/session/manifest",
        schema_file="session_manifest.schema.json",
        schema_name="SessionManifest",
        is_jsonl=False,
        source_base="session_manifest",
        source_ext="json",
    ),
]


# ----------------------------------------------------------------------------
# File resolution — new format ({base}_{code}.{ext}) with legacy fallback.
# ----------------------------------------------------------------------------

def resolve_artifact(session_dir: Path, session_code: str, base: str, ext: str) -> Optional[Path]:
    """Return the path for an artifact, preferring suffixed filenames."""
    candidates = [
        session_dir / f"{base}_{session_code}.{ext}",
        session_dir / f"{base}.{ext}",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


# ----------------------------------------------------------------------------
# Timestamp helpers
# ----------------------------------------------------------------------------

def epoch_ms_to_ns(epoch_ms: float | int) -> int:
    """Convert float ms → int ns, safe for the full double range we care about."""
    return int(round(float(epoch_ms) * 1_000_000))


def pick_epoch_ms(obj: dict[str, Any], fallback_ns: Optional[int]) -> int:
    """Best-effort extraction of a message timestamp (ns since epoch).

    Order:
      1. timestampEpochMs (IMU / video frame meta).
      2. createdAtEpochMs (manifest).
      3. startTimeEpochMs (session metadata).
      4. fallback_ns provided by the caller.
    """
    for key in ("timestampEpochMs", "createdAtEpochMs", "startTimeEpochMs"):
        val = obj.get(key)
        if isinstance(val, (int, float)) and val > 0:
            return epoch_ms_to_ns(val)
    if fallback_ns is not None:
        return fallback_ns
    raise ValueError("no timestamp available and no fallback provided")


# ----------------------------------------------------------------------------
# Builder
# ----------------------------------------------------------------------------

@dataclass
class BuildStats:
    """Diagnostic counters returned after a build."""
    output_path: Path
    total_messages: int = 0
    channel_counts: dict[str, int] = None  # type: ignore[assignment]
    skipped_channels: list[str] = None     # type: ignore[assignment]

    def __post_init__(self) -> None:
        if self.channel_counts is None:
            self.channel_counts = {}
        if self.skipped_channels is None:
            self.skipped_channels = []


def build_mcap(session_dir: Path, session_code: str, output_path: Path) -> BuildStats:
    """Build `{output_path}` from the artifacts inside `session_dir`.

    Raises OSError if the output path is not writable. All other failures (a
    missing individual artifact, a malformed line) are logged and skipped.
    """
    stats = BuildStats(output_path=output_path)

    # Fallback timestamp: if a single-shot JSON file has no epoch fields and
    # the session_metadata wasn't loaded yet, this is what we anchor to.
    session_start_ns: Optional[int] = None

    with open(output_path, "wb") as out_fp:
        writer = Writer(out_fp, compression=CompressionType.NONE)
        writer.start(profile="", library="kgen-eye-mcap-builder/1.0")

        # Pre-load session metadata first so the fallback timestamp is set.
        meta_channel = next(c for c in CHANNELS if c.source_base == "metadata")
        meta_path = resolve_artifact(session_dir, session_code, meta_channel.source_base, meta_channel.source_ext)
        if meta_path is not None:
            try:
                meta_obj = json.loads(meta_path.read_text())
                start_ms = meta_obj.get("startTimeEpochMs")
                if isinstance(start_ms, (int, float)) and start_ms > 0:
                    session_start_ns = epoch_ms_to_ns(start_ms)
            except (json.JSONDecodeError, OSError) as e:
                log.warning("could not pre-read metadata for fallback ts: %s", e)

        # Register schemas & channels up-front so topic order in Foxglove is stable.
        registered: dict[str, tuple[int, int]] = {}   # topic -> (schema_id, channel_id)
        for spec in CHANNELS:
            schema_path = SCHEMAS_DIR / spec.schema_file
            if not schema_path.exists():
                log.error("schema file missing: %s", schema_path)
                stats.skipped_channels.append(spec.topic)
                continue
            schema_id = writer.register_schema(
                name=spec.schema_name,
                encoding=JSON_SCHEMA_ENCODING,
                data=schema_path.read_bytes(),
            )
            channel_id = writer.register_channel(
                topic=spec.topic,
                message_encoding=JSON_MESSAGE_ENCODING,
                schema_id=schema_id,
            )
            registered[spec.topic] = (schema_id, channel_id)

        # Emit messages per channel.
        for spec in CHANNELS:
            if spec.topic not in registered:
                continue
            _, channel_id = registered[spec.topic]

            path = resolve_artifact(session_dir, session_code, spec.source_base, spec.source_ext)
            if path is None:
                log.info("[%s] artifact missing: %s_%s.%s", spec.topic, spec.source_base, session_code, spec.source_ext)
                stats.skipped_channels.append(spec.topic)
                continue

            count = 0
            try:
                for msg_ns, payload in _iter_messages(spec, path, session_start_ns):
                    writer.add_message(
                        channel_id=channel_id,
                        log_time=msg_ns,
                        publish_time=msg_ns,
                        data=payload,
                    )
                    count += 1
            except (OSError, ValueError) as e:
                log.exception("[%s] failed to emit messages: %s", spec.topic, e)

            stats.channel_counts[spec.topic] = count
            stats.total_messages += count
            log.info("[%s] emitted %d message(s)", spec.topic, count)

        writer.finish()

    return stats


def _iter_messages(
    spec: ChannelSpec,
    path: Path,
    fallback_ns: Optional[int],
) -> Iterable[tuple[int, bytes]]:
    """Yield (timestamp_ns, serialized_bytes) for each message in `path`."""
    if spec.is_jsonl:
        with path.open("r", encoding="utf-8") as fp:
            for line_no, line in enumerate(fp, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError as e:
                    log.warning("[%s] skipping malformed line %d: %s", spec.topic, line_no, e)
                    continue
                try:
                    ts_ns = pick_epoch_ms(obj, fallback_ns)
                except ValueError:
                    log.warning("[%s] skipping line %d: no timestamp", spec.topic, line_no)
                    continue
                yield ts_ns, line.encode("utf-8")
        return

    obj = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(obj, dict):
        log.warning("[%s] expected JSON object, got %s", spec.topic, type(obj).__name__)
        return
    try:
        ts_ns = pick_epoch_ms(obj, fallback_ns)
    except ValueError:
        log.warning("[%s] no timestamp field; anchoring at ns=0", spec.topic)
        ts_ns = 0
    yield ts_ns, path.read_bytes()

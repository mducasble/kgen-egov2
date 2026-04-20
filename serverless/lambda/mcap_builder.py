"""Builds a single-session, Humyn Labs / Figure-compliant MCAP from the
JSON/JSONL + MP4 artifacts produced by the iOS capture app.

Output channels (all ``json`` + ``jsonschema`` encoding, zstd-compressed
chunks):

* ``/camera/head/video``        -> ``foxglove.CompressedVideo``    (30 Hz, H.264)
* ``/camera/head/calibration``  -> ``foxglove.CameraCalibration``  (1x)
* ``/sensors/head/imu``         -> ``foxglove.Imu``                (100-250 Hz)
* ``/tf``                       -> ``foxglove.FrameTransform``     (1x, static)
* ``/session/metadata``         -> ``humynlabs.SessionMetadata``   (1x, head)
* ``/session/metrics``          -> ``humynlabs.SessionMetrics``    (1x, tail)

Design rules:

* Deterministic: the same inputs produce a byte-equivalent MCAP (modulo the
  MCAP library version and the zstd patch level). The Lambda is idempotent.
* Partial-tolerant: a missing artifact is logged and skipped; the MCAP is
  still written with whatever channels are usable.
* Single clock domain in the output: every message timestamp is an epoch
  ``{sec, nsec}`` pair. Mach-absolute times stay inside the iOS app.
* Video is *embedded* (Annex B H.264 per-frame, base64) — no MP4 sidecar.
"""

from __future__ import annotations

import base64
import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional

from mcap.writer import CompressionType, Writer

import transforms
from video_extractor import H264Frame, extract_h264_frames

log = logging.getLogger(__name__)

SCHEMA_ENCODING = "jsonschema"
MESSAGE_ENCODING = "json"

SCHEMAS_DIR = Path(__file__).resolve().parent / "schemas"

# Topics must match Foxglove and ROS conventions for panel auto-detection
# (e.g. the Image panel looks for any CompressedVideo topic, but the tf
# panel specifically expects ``/tf``).
TOPIC_VIDEO = "/camera/head/video"
TOPIC_CALIBRATION = "/camera/head/calibration"
TOPIC_IMU = "/sensors/head/imu"
TOPIC_TF = "/tf"
TOPIC_SESSION_METADATA = "/session/metadata"
TOPIC_SESSION_METRICS = "/session/metrics"


@dataclass(frozen=True)
class ChannelSpec:
    topic: str
    schema_file: str
    schema_name: str


CHANNELS: list[ChannelSpec] = [
    ChannelSpec(TOPIC_VIDEO,            "foxglove.CompressedVideo.schema.json",   "foxglove.CompressedVideo"),
    ChannelSpec(TOPIC_CALIBRATION,      "foxglove.CameraCalibration.schema.json", "foxglove.CameraCalibration"),
    ChannelSpec(TOPIC_IMU,              "foxglove.Imu.schema.json",               "foxglove.Imu"),
    ChannelSpec(TOPIC_TF,               "foxglove.FrameTransform.schema.json",    "foxglove.FrameTransform"),
    ChannelSpec(TOPIC_SESSION_METADATA, "humynlabs.SessionMetadata.schema.json",  "humynlabs.SessionMetadata"),
    ChannelSpec(TOPIC_SESSION_METRICS,  "humynlabs.SessionMetrics.schema.json",   "humynlabs.SessionMetrics"),
]


@dataclass
class BuildStats:
    output_path: Path
    total_messages: int = 0
    channel_counts: dict[str, int] = field(default_factory=dict)
    skipped_channels: list[str] = field(default_factory=list)
    # Optional: helpful when validating a session that didn't include
    # video in the upload batch (iOS "no-video" captures don't ship MP4s).
    video_embedded: bool = False


def build_mcap(
    session_dir: Path,
    session_code: str,
    output_path: Path,
    video_paths: Optional[list[Path]] = None,
) -> BuildStats:
    """Assemble an MCAP at ``output_path``.

    ``session_dir`` must contain the iOS artifacts (``imu_*.jsonl``,
    ``video_timestamps_*.jsonl``, ``metadata_*.json``,
    ``technical_validation_*.json``). ``video_paths`` is the ordered list
    of H.264 MP4s to embed — one entry for a consolidated video, or many
    for iOS chunked uploads (``chunk_NNN_<code>.mp4``). Pass ``None`` or
    an empty list to skip the video channel (useful for re-running on a
    machine that can't afford to download the MP4s).
    """
    stats = BuildStats(output_path=output_path)

    metadata = _load_single_json(session_dir, session_code, "metadata")
    if metadata is None:
        log.error("metadata artifact missing — cannot build a valid MCAP")
        raise FileNotFoundError(f"metadata_{session_code}.json not found in {session_dir}")

    validation = _load_single_json(session_dir, session_code, "technical_validation") or {}

    session_start_ns = transforms.epoch_ms_to_ns(metadata.get("startTimeEpochMs") or 0)
    if session_start_ns <= 0:
        raise ValueError("session metadata missing startTimeEpochMs")

    # Derive the recording's true duration from the video frame timestamps
    # (first-to-last span in capture order). This is the single source of
    # truth for both the SessionMetadata and SessionMetrics messages — see
    # transforms.session_metadata for the rationale.
    frame_timestamps_ms = _load_frame_timestamps(session_dir, session_code)
    video_duration_ns = _compute_video_duration_ns(frame_timestamps_ms)

    with output_path.open("wb") as fp:
        writer = Writer(fp, compression=CompressionType.ZSTD)
        writer.start(profile="", library="humynlabs-mcap-builder/1.0")

        channel_ids = _register_channels(writer, stats)

        _emit_session_metadata(
            writer, channel_ids, stats, metadata, session_code, video_duration_ns
        )
        _emit_calibration(writer, channel_ids, stats, metadata, session_start_ns)
        _emit_frame_transform(writer, channel_ids, stats, metadata, session_start_ns)

        _emit_imu(writer, channel_ids, stats, session_dir, session_code)

        usable_videos = [p for p in (video_paths or []) if p.exists()]
        if usable_videos:
            _emit_video(writer, channel_ids, stats, session_dir, session_code, usable_videos)
            stats.video_embedded = stats.channel_counts.get(TOPIC_VIDEO, 0) > 0
        else:
            stats.skipped_channels.append(TOPIC_VIDEO)
            log.info("[%s] no MP4 supplied; skipping video embedding", TOPIC_VIDEO)

        _emit_session_metrics(
            writer, channel_ids, stats, validation, metadata, session_code,
            session_start_ns, video_duration_ns,
        )

        writer.finish()

    return stats


# ----------------------------------------------------------------------------
# Channel / schema registration
# ----------------------------------------------------------------------------

def _register_channels(writer: Writer, stats: BuildStats) -> dict[str, int]:
    """Register every schema + channel up-front so topic order is stable."""
    ids: dict[str, int] = {}
    for spec in CHANNELS:
        schema_path = SCHEMAS_DIR / spec.schema_file
        if not schema_path.exists():
            log.error("schema file missing on disk: %s", schema_path)
            stats.skipped_channels.append(spec.topic)
            continue
        schema_id = writer.register_schema(
            name=spec.schema_name,
            encoding=SCHEMA_ENCODING,
            data=schema_path.read_bytes(),
        )
        channel_id = writer.register_channel(
            topic=spec.topic,
            message_encoding=MESSAGE_ENCODING,
            schema_id=schema_id,
        )
        ids[spec.topic] = channel_id
    return ids


# ----------------------------------------------------------------------------
# Per-channel emitters
# ----------------------------------------------------------------------------

def _compute_video_duration_ns(frame_timestamps_ms: list[float]) -> int:
    """Return last-frame minus first-frame span in nanoseconds.

    Returns 0 when fewer than two usable timestamps exist (single-frame
    sessions or missing video_timestamps). The caller is expected to
    treat 0 as "no override — fall back to metadata.durationSec".
    """
    if len(frame_timestamps_ms) < 2:
        return 0
    span_ms = frame_timestamps_ms[-1] - frame_timestamps_ms[0]
    if span_ms <= 0:
        return 0
    return int(round(span_ms * 1_000_000))


def _emit_session_metadata(
    writer: Writer,
    channel_ids: dict[str, int],
    stats: BuildStats,
    metadata: dict[str, Any],
    session_code: str,
    measured_duration_ns: int = 0,
) -> None:
    chan = channel_ids.get(TOPIC_SESSION_METADATA)
    if chan is None:
        return
    msg = transforms.session_metadata(
        metadata, session_code,
        measured_duration_ns=measured_duration_ns or None,
    )
    log_ns = msg["recorded_at_epoch_ns"] or 0
    _write(writer, chan, log_ns, msg)
    stats.channel_counts[TOPIC_SESSION_METADATA] = 1
    stats.total_messages += 1


def _emit_calibration(
    writer: Writer,
    channel_ids: dict[str, int],
    stats: BuildStats,
    metadata: dict[str, Any],
    session_start_ns: int,
) -> None:
    chan = channel_ids.get(TOPIC_CALIBRATION)
    if chan is None:
        return
    msg = transforms.camera_calibration(metadata, session_start_ns)
    if msg is None:
        stats.skipped_channels.append(TOPIC_CALIBRATION)
        log.info("[%s] no usable intrinsics in metadata — channel skipped", TOPIC_CALIBRATION)
        return
    _write(writer, chan, session_start_ns, msg)
    stats.channel_counts[TOPIC_CALIBRATION] = 1
    stats.total_messages += 1


def _emit_frame_transform(
    writer: Writer,
    channel_ids: dict[str, int],
    stats: BuildStats,
    metadata: dict[str, Any],
    session_start_ns: int,
) -> None:
    chan = channel_ids.get(TOPIC_TF)
    if chan is None:
        return
    msg = transforms.frame_transform(metadata, session_start_ns)
    if msg is None:
        stats.skipped_channels.append(TOPIC_TF)
        return
    _write(writer, chan, session_start_ns, msg)
    stats.channel_counts[TOPIC_TF] = 1
    stats.total_messages += 1


def _emit_imu(
    writer: Writer,
    channel_ids: dict[str, int],
    stats: BuildStats,
    session_dir: Path,
    session_code: str,
) -> None:
    chan = channel_ids.get(TOPIC_IMU)
    if chan is None:
        return
    imu_path = _resolve(session_dir, session_code, "imu", "jsonl")
    if imu_path is None:
        stats.skipped_channels.append(TOPIC_IMU)
        log.info("[%s] artifact missing", TOPIC_IMU)
        return

    count = 0
    with imu_path.open("r", encoding="utf-8") as fp:
        for obj in transforms.iter_jsonl_objects(fp):
            try:
                log_ns, msg = transforms.imu_sample(obj)
            except ValueError as e:
                log.warning("[%s] skipping sample: %s", TOPIC_IMU, e)
                continue
            _write(writer, chan, log_ns, msg)
            count += 1
    stats.channel_counts[TOPIC_IMU] = count
    stats.total_messages += count
    log.info("[%s] emitted %d samples", TOPIC_IMU, count)


def _emit_video(
    writer: Writer,
    channel_ids: dict[str, int],
    stats: BuildStats,
    session_dir: Path,
    session_code: str,
    video_paths: list[Path],
) -> None:
    chan = channel_ids.get(TOPIC_VIDEO)
    if chan is None:
        return

    timestamps = _load_frame_timestamps(session_dir, session_code)
    if not timestamps:
        stats.skipped_channels.append(TOPIC_VIDEO)
        log.warning(
            "[%s] video_timestamps artifact missing or empty — skipping video", TOPIC_VIDEO
        )
        return

    # Pair H.264 frames with iOS-captured timestamps by index. iOS guarantees
    # one entry in video_timestamps per encoded frame, in presentation order
    # across all chunks. We iterate chunks in order and consume one timestamp
    # per MP4 sample; mismatches are logged but don't abort — a slightly
    # truncated video channel is better than no video at all.
    count = 0
    ts_iter = iter(timestamps)
    for video_path in video_paths:
        try:
            frames = list(extract_h264_frames(video_path))
        except ValueError as e:
            log.error("[%s] cannot parse MP4 %s: %s", TOPIC_VIDEO, video_path.name, e)
            continue

        for frame in frames:
            try:
                ts_ms = next(ts_iter)
            except StopIteration:
                log.warning(
                    "[%s] ran out of timestamps at frame %d — stopping video emission",
                    TOPIC_VIDEO, count,
                )
                break

            log_ns = transforms.epoch_ms_to_ns(ts_ms)
            msg = {
                "timestamp": transforms.epoch_ns_to_sec_nsec(log_ns),
                "frame_id": transforms.FRAME_ID_HEAD_CAMERA,
                "data": base64.b64encode(frame.data).decode("ascii"),
                "format": "h264",
            }
            _write(writer, chan, log_ns, msg)
            count += 1
        else:
            # Python: the else branch of a for runs when the loop completed
            # without a break. Continue to the next chunk in that case.
            continue
        # A break above propagated here: stop consuming further chunks.
        break

    remaining = sum(1 for _ in ts_iter)
    if remaining:
        log.warning(
            "[%s] %d timestamp(s) had no matching MP4 frame", TOPIC_VIDEO, remaining,
        )

    if count == 0:
        stats.skipped_channels.append(TOPIC_VIDEO)
        log.error("[%s] decoded 0 frames across %d MP4(s)", TOPIC_VIDEO, len(video_paths))
        return

    stats.channel_counts[TOPIC_VIDEO] = count
    stats.total_messages += count
    log.info("[%s] embedded %d frames from %d MP4(s)", TOPIC_VIDEO, count, len(video_paths))


def _emit_session_metrics(
    writer: Writer,
    channel_ids: dict[str, int],
    stats: BuildStats,
    validation: dict[str, Any],
    metadata: dict[str, Any],
    session_code: str,
    session_start_ns: int,
    measured_duration_ns: int = 0,
) -> None:
    chan = channel_ids.get(TOPIC_SESSION_METRICS)
    if chan is None:
        return
    # Emit metrics at the end of the session timeline so Foxglove shows them
    # chronologically after all the video/IMU samples. Prefer the measured
    # video-span duration over metadata.durationSec so the metrics message
    # agrees with the SessionMetadata message we emit above.
    if measured_duration_ns > 0:
        duration_ns = measured_duration_ns
        duration_sec_for_metric: Optional[float] = duration_ns / 1_000_000_000
    else:
        duration_ns = 0
        duration_sec = metadata.get("durationSec")
        if isinstance(duration_sec, (int, float)) and duration_sec > 0:
            duration_ns = int(round(duration_sec * 1_000_000_000))
        duration_sec_for_metric = None  # let transforms.session_metrics fall back
    computed_at_ns = session_start_ns + duration_ns
    msg = transforms.session_metrics(
        validation, metadata, computed_at_ns, session_code,
        measured_duration_sec=duration_sec_for_metric,
    )
    _write(writer, chan, computed_at_ns, msg)
    stats.channel_counts[TOPIC_SESSION_METRICS] = 1
    stats.total_messages += 1


# ----------------------------------------------------------------------------
# Writer / artifact helpers
# ----------------------------------------------------------------------------

def _write(writer: Writer, channel_id: int, log_ns: int, body: dict[str, Any]) -> None:
    writer.add_message(
        channel_id=channel_id,
        log_time=log_ns,
        publish_time=log_ns,
        data=json.dumps(body, separators=(",", ":")).encode("utf-8"),
    )


def _resolve(session_dir: Path, session_code: str, base: str, ext: str) -> Optional[Path]:
    """Return the first matching artifact path, suffixed or legacy."""
    for candidate in (
        session_dir / f"{base}_{session_code}.{ext}",
        session_dir / f"{base}.{ext}",
    ):
        if candidate.exists():
            return candidate
    return None


def _load_single_json(
    session_dir: Path, session_code: str, base: str
) -> Optional[dict[str, Any]]:
    path = _resolve(session_dir, session_code, base, "json")
    if path is None:
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        log.error("could not read %s: %s", path, e)
        return None


def _load_frame_timestamps(session_dir: Path, session_code: str) -> list[float]:
    """Return the list of frame timestamps (epoch ms) in capture order."""
    path = _resolve(session_dir, session_code, "video_timestamps", "jsonl")
    if path is None:
        return []
    out: list[float] = []
    with path.open("r", encoding="utf-8") as fp:
        for obj in transforms.iter_jsonl_objects(fp):
            ts = obj.get("timestampEpochMs")
            if isinstance(ts, (int, float)) and ts > 0:
                out.append(float(ts))
    return out

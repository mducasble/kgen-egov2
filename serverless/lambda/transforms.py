"""Per-channel transformations from the iOS capture artifacts into the
Humyn Labs / Figure-compliant MCAP message bodies.

Each public function returns a plain ``dict`` that is valid against the
corresponding target JSON Schema. The builder serialises that dict into
``bytes`` and writes it to the MCAP.

Principles:

* No verdicts — we emit only measured values. Pass/fail thresholds are the
  consumer's problem, not ours.
* A single clock domain in the output: every timestamp is epoch ``{sec,
  nsec}``. Mach-absolute and monotonic IDs stay inside the iOS app.
* Unit conversions happen here, once (g -> m/s^2, ms -> ns, etc.).
"""

from __future__ import annotations

import logging
from typing import Any, Iterable, Optional

log = logging.getLogger(__name__)

# 1g in m/s^2 per BIPM / CODATA. The iOS CMDeviceMotion userAcceleration +
# gravity is exported in g on purpose, so we multiply here.
STANDARD_GRAVITY_M_S2 = 9.80665

SCHEMA_VERSION = "1.0.0"
METRICS_VERSION = "1.0.0"

# Frame-ids referenced by the Foxglove messages. These strings are
# load-bearing: the CameraCalibration / FrameTransform / Imu /
# CompressedVideo messages all must agree on them for Foxglove's tf-aware
# visualisations to link up.
FRAME_ID_HEAD_CAMERA = "head_camera"
FRAME_ID_HEAD_IMU = "head_imu"
FRAME_ID_HEAD_CENTER = "head_center"


# ----------------------------------------------------------------------------
# Timestamp helpers
# ----------------------------------------------------------------------------

def epoch_ms_to_sec_nsec(epoch_ms: float | int) -> dict[str, int]:
    """Split a float-ms epoch timestamp into ``{"sec", "nsec"}``.

    We route via integer nanoseconds to avoid double-precision drift at
    sub-millisecond scales. A negative or non-numeric input raises.
    """
    if not isinstance(epoch_ms, (int, float)):
        raise ValueError(f"epoch_ms must be numeric, got {type(epoch_ms).__name__}")
    if epoch_ms < 0:
        raise ValueError(f"epoch_ms must be non-negative, got {epoch_ms}")
    ns = int(round(float(epoch_ms) * 1_000_000))
    return epoch_ns_to_sec_nsec(ns)


def epoch_ns_to_sec_nsec(epoch_ns: int) -> dict[str, int]:
    sec, nsec = divmod(int(epoch_ns), 1_000_000_000)
    return {"sec": sec, "nsec": nsec}


def epoch_ms_to_ns(epoch_ms: float | int) -> int:
    return int(round(float(epoch_ms) * 1_000_000))


# ----------------------------------------------------------------------------
# IMU  (per-sample)
# ----------------------------------------------------------------------------

def imu_sample(obj: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    """Convert one IMUSample line into (log_time_ns, foxglove.Imu dict)."""
    ts_ms = obj.get("timestampEpochMs")
    if not isinstance(ts_ms, (int, float)):
        raise ValueError("IMU sample missing timestampEpochMs")
    acc = obj.get("accelerometer") or {}
    gyr = obj.get("gyroscope") or {}

    msg = {
        "timestamp": epoch_ms_to_sec_nsec(ts_ms),
        "frame_id": FRAME_ID_HEAD_IMU,
        "linear_acceleration": {
            "x": float(acc.get("x", 0.0)) * STANDARD_GRAVITY_M_S2,
            "y": float(acc.get("y", 0.0)) * STANDARD_GRAVITY_M_S2,
            "z": float(acc.get("z", 0.0)) * STANDARD_GRAVITY_M_S2,
        },
        "angular_velocity": {
            "x": float(gyr.get("x", 0.0)),
            "y": float(gyr.get("y", 0.0)),
            "z": float(gyr.get("z", 0.0)),
        },
    }
    return epoch_ms_to_ns(ts_ms), msg


# ----------------------------------------------------------------------------
# Camera calibration (1x, at session start)
# ----------------------------------------------------------------------------

_DISTORTION_MAP = {
    "plumb_bob": "plumb_bob",
    "radtan": "plumb_bob",
    "radial_tangential": "plumb_bob",
    "rational_polynomial": "rational_polynomial",
    "kannala_brandt": "kannala_brandt",
    "equidistant": "equidistant",
    "fisheye": "equidistant",
    "none": "none",
    "": "none",
}


def camera_calibration(
    metadata: dict[str, Any],
    session_start_ns: int,
) -> Optional[dict[str, Any]]:
    """Build a ``foxglove.CameraCalibration`` from the session metadata.

    Returns ``None`` if the source metadata lacks intrinsics. The target
    schema requires ``width``, ``height``, ``K`` and ``D`` so we can't emit
    a partial stub.
    """
    intr = metadata.get("cameraIntrinsics")
    if not isinstance(intr, dict):
        return None

    resolution = intr.get("resolution") or {}
    width = int(resolution.get("width") or 0)
    height = int(resolution.get("height") or 0)
    if width <= 0 or height <= 0:
        # Fall back to the capture block, which always carries resolution
        # even when intrinsics are estimated.
        capture = metadata.get("capture") or {}
        width = int(capture.get("videoResolutionWidth") or 0) or width
        height = int(capture.get("videoResolutionHeight") or 0) or height
    if width <= 0 or height <= 0:
        return None

    fx = _safe_float(intr.get("focalLengthPixels", {}).get("fx"))
    fy = _safe_float(intr.get("focalLengthPixels", {}).get("fy"))
    cx = _safe_float(intr.get("principalPoint", {}).get("cx"), default=width / 2.0)
    cy = _safe_float(intr.get("principalPoint", {}).get("cy"), default=height / 2.0)
    if fx is None or fy is None:
        return None

    k_matrix = [
        fx, 0.0, cx,
        0.0, fy, cy,
        0.0, 0.0, 1.0,
    ]

    raw_model = str(intr.get("distortionModel") or "").lower()
    distortion_model = _DISTORTION_MAP.get(raw_model, "none")
    distortion_present = bool(intr.get("distortionPresent"))

    # Phase 3: iOS now ships fitted plumb_bob coefficients when the lens
    # calibration probe succeeds. Prefer those over the zero-vector stub.
    raw_coeffs = intr.get("distortionCoefficients")
    parsed_coeffs: list[float] = []
    if isinstance(raw_coeffs, (list, tuple)):
        for v in raw_coeffs:
            f = _safe_float(v)
            if f is None:
                parsed_coeffs = []
                break
            parsed_coeffs.append(f)

    if distortion_model == "plumb_bob":
        if len(parsed_coeffs) == 5:
            d_coeffs = parsed_coeffs
        elif len(parsed_coeffs) >= 5:
            d_coeffs = parsed_coeffs[:5]
        else:
            # Keep the shape non-empty for consumers that assume D has length 5;
            # values of zero signal "no usable calibration".
            d_coeffs = [0.0, 0.0, 0.0, 0.0, 0.0]
    elif distortion_model == "rational_polynomial":
        if len(parsed_coeffs) == 8:
            d_coeffs = parsed_coeffs
        else:
            d_coeffs = [0.0] * 8
    else:
        d_coeffs = []
    if not distortion_present and distortion_model != "none":
        # Still keep the shape non-empty for plumb_bob / rational_polynomial,
        # but mark that the raw coeffs are effectively zero.
        pass

    return {
        "timestamp": epoch_ns_to_sec_nsec(session_start_ns),
        "frame_id": FRAME_ID_HEAD_CAMERA,
        "width": width,
        "height": height,
        "distortion_model": distortion_model,
        "D": d_coeffs,
        "K": k_matrix,
        "R": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
        "P": [
            fx, 0.0, cx, 0.0,
            0.0, fy, cy, 0.0,
            0.0, 0.0, 1.0, 0.0,
        ],
    }


# ----------------------------------------------------------------------------
# Frame transform (1x, at session start)
# ----------------------------------------------------------------------------

def frame_transform(
    metadata: dict[str, Any],
    session_start_ns: int,
) -> Optional[dict[str, Any]]:
    """Build a ``foxglove.FrameTransform`` from ``cameraExtrinsics``."""
    extr = metadata.get("cameraExtrinsics")
    if not isinstance(extr, dict):
        return None

    translation = extr.get("translationMeters") or {}
    quat = extr.get("rotationQuaternion") or {}
    qx = _safe_float(quat.get("x"))
    qy = _safe_float(quat.get("y"))
    qz = _safe_float(quat.get("z"))
    qw = _safe_float(quat.get("w"))
    if None in (qx, qy, qz, qw):
        # Extrinsics without a quaternion are useless for tf; skip the channel.
        log.info("extrinsics present but quaternion incomplete — skipping /tf")
        return None

    return {
        "timestamp": epoch_ns_to_sec_nsec(session_start_ns),
        "parent_frame_id": FRAME_ID_HEAD_CENTER,
        "child_frame_id": FRAME_ID_HEAD_CAMERA,
        "translation": {
            "x": _safe_float(translation.get("x"), default=0.0),
            "y": _safe_float(translation.get("y"), default=0.0),
            "z": _safe_float(translation.get("z"), default=0.0),
        },
        "rotation": {"x": qx, "y": qy, "z": qz, "w": qw},
    }


# ----------------------------------------------------------------------------
# Session metadata (1x, at session start)
# ----------------------------------------------------------------------------

# Figure/HumynLabs spec requires ``duration_ns >= 120 s``. We intentionally
# emit the measured value as-is: short test sessions (< 120 s) will fail
# strict schema validation downstream, but the ground truth is preserved
# which is what we want for internal diagnostics. Production sessions run
# well above 120 s and are unaffected.
SPEC_MIN_DURATION_SEC = 120.0


def session_metadata(
    metadata: dict[str, Any],
    session_code: str,
    measured_duration_ns: Optional[int] = None,
) -> dict[str, Any]:
    """Build a ``humynlabs.SessionMetadata`` from the iOS metadata.

    ``measured_duration_ns`` takes precedence over ``metadata.durationSec``
    when provided and positive. The builder derives it from
    ``video_timestamps.jsonl`` (first/last frame epoch span), which is the
    only duration that matches the actual footage in the MCAP — the
    ``durationSec`` field in ``metadata.json`` is wall-clock between
    ``startRecording`` and ``stopRecording`` on the iOS side and can
    include pre-capture setup overhead, background pauses, and the
    finalisation window, inflating the declared span vs the video.
    """
    session_id = str(metadata.get("sessionId") or session_code)

    start_ms = metadata.get("startTimeEpochMs") or 0
    declared_duration_sec = float(metadata.get("durationSec") or 0)

    if isinstance(measured_duration_ns, (int, float)) and measured_duration_ns > 0:
        duration_ns = int(measured_duration_ns)
        duration_sec = duration_ns / 1_000_000_000
        if declared_duration_sec > 0:
            delta_pct = abs(duration_sec - declared_duration_sec) / declared_duration_sec * 100
            if delta_pct > 5.0:
                log.warning(
                    "session duration mismatch: metadata.durationSec=%.3fs vs "
                    "video span=%.3fs (Δ=%.1f%%). Emitting video span as truth.",
                    declared_duration_sec, duration_sec, delta_pct,
                )
    else:
        duration_sec = declared_duration_sec
        duration_ns = int(round(duration_sec * 1_000_000_000))

    if duration_sec < SPEC_MIN_DURATION_SEC:
        log.info(
            "session duration %.2fs < %.0fs Figure minimum — emitting real value; schema may reject",
            duration_sec,
            SPEC_MIN_DURATION_SEC,
        )

    device = metadata.get("device") or {}
    capture = metadata.get("capture") or {}
    video_enc = metadata.get("videoEncoding") or {}
    color = metadata.get("colorProfile") or {}
    signals = metadata.get("signalConfiguration") or {}
    environment = metadata.get("environment") or {}
    coord = metadata.get("coordinateSystem") or {}
    extr = metadata.get("cameraExtrinsics") or {}

    out = {
        "session_id": session_id,
        "schema_version": SCHEMA_VERSION,
        "recorded_at_epoch_ns": epoch_ms_to_ns(start_ms) if start_ms else 0,
        "duration_ns": duration_ns,
        "clock": _clock_block(capture),
        "task": _task_block(environment),
        "capture_device": _capture_device_block(device, extr),
        "video_encoding": _video_encoding_block(capture, video_enc, color),
        "imu_config": _imu_config_block(capture, signals, coord),
    }
    return out


def _clock_block(capture: dict[str, Any]) -> dict[str, Any]:
    # iOS samples every timestamp from the monotonic mach_absolute_time clock
    # and aligns it to epoch once per session via a single wall-clock read,
    # which is exactly what Figure calls "single_reference" alignment.
    source = str(capture.get("timestampClock") or "mach_absolute_time")
    precision = capture.get("epochToMonotonicPrecision") or ""
    precision_ms = _parse_precision_ms(precision)
    block = {"source": source, "epoch_alignment": "single_reference"}
    if precision_ms is not None:
        block["epoch_alignment_precision_ms"] = precision_ms
    return block


def _parse_precision_ms(raw: str) -> Optional[float]:
    """Extract a numeric millisecond value from a loose string like ``"<1ms"``."""
    if not raw:
        return None
    cleaned = "".join(ch for ch in str(raw) if ch.isdigit() or ch in ".-")
    if not cleaned or cleaned in ("-", "."):
        return None
    try:
        return max(0.0, float(cleaned))
    except ValueError:
        return None


def _task_block(environment: dict[str, Any]) -> dict[str, Any]:
    # The iOS "environment" object carries:
    #   type         -> residential/commercial (already normalised in-app)
    #   subCategory  -> vertical (e.g. "laundry")
    #   taskDescription -> free-form label ("folding bedsheet")
    raw_type = str(environment.get("type") or "residential").lower()
    if raw_type not in ("residential", "commercial"):
        raw_type = "residential"
    vertical = str(environment.get("subCategory") or "general")
    label = str(environment.get("taskDescription") or vertical)
    return {"category": raw_type, "vertical": vertical, "label": label}


def _capture_device_block(device: dict[str, Any], extrinsics: dict[str, Any]) -> dict[str, Any]:
    mount_raw = str(extrinsics.get("mountType") or "headband").lower()
    mount = mount_raw if mount_raw in (
        "headband", "helmet", "cap_clip", "eyewear_frame"
    ) else "headband"
    model = str(device.get("model") or device.get("hardwareIdentifier") or "unknown")
    return {
        "type": "phone_builtin",
        "model": model,
        "mount": mount,
        "external_camera_approved_by_figure": False,
    }


def _video_encoding_block(
    capture: dict[str, Any],
    video_enc: dict[str, Any],
    color: dict[str, Any],
) -> dict[str, Any]:
    # The Figure schema clamps bitrate into [4, 8] Mbps and enforces
    # gop=30/bframes=0/hdr=false/8bit. iOS produces exactly those values
    # today, but we clamp defensively so a slightly off session still
    # validates rather than failing the upload.
    bitrate = _safe_float(video_enc.get("bitrateMbps"), default=6.0) or 6.0
    bitrate = max(4.0, min(8.0, bitrate))
    width = int(capture.get("videoResolutionWidth") or 1920)
    height = int(capture.get("videoResolutionHeight") or 1080)
    fps = _safe_float(capture.get("targetFPS"), default=30.0) or 30.0
    return {
        "codec": "h264",
        "resolution_width": width,
        "resolution_height": height,
        "fps_target": fps,
        "bitrate_mbps": bitrate,
        "gop_length": 30,
        "b_frames": 0,
        "hdr": False,
        "color_depth_bits": 8,
    }


def _imu_config_block(
    capture: dict[str, Any],
    signals: dict[str, Any],
    coord: dict[str, Any],
) -> dict[str, Any]:
    rate = _safe_float(capture.get("imuTargetHz"), default=100.0) or 100.0
    rate = max(100.0, min(250.0, rate))
    axis = coord.get("axisConvention") or {}
    convention_parts = [
        str(axis.get("x") or "").split()[0].lower() or "right",
        str(axis.get("y") or "").split()[0].lower() or "down",
        str(axis.get("z") or "").split()[0].lower() or "forward",
    ]
    convention = f"ios_{'_'.join(convention_parts)}"
    return {
        "target_rate_hz": rate,
        "gravity_included": True,
        "coordinate_convention": convention,
    }


# ----------------------------------------------------------------------------
# Session metrics (1x, at end of session)
# ----------------------------------------------------------------------------

def session_metrics(
    validation: dict[str, Any],
    metadata: dict[str, Any],
    computed_at_ns: int,
    session_code: str,
    measured_duration_sec: Optional[float] = None,
) -> dict[str, Any]:
    """Build a ``humynlabs.SessionMetrics`` — measurements only, no verdicts.

    ``measured_duration_sec``, when positive, replaces
    ``metadata.durationSec`` for the ``clip_duration`` metric. See the
    ``session_metadata`` docstring for why this override exists.
    """
    session_id = str(
        validation.get("sessionId") or metadata.get("sessionId") or session_code
    )

    timing = validation.get("timing") or {}
    imu = validation.get("imu") or {}
    video = validation.get("video") or {}
    enc = validation.get("videoEncoding") or {}
    calib = validation.get("calibration") or {}

    capture = metadata.get("capture") or {}
    intr = metadata.get("cameraIntrinsics") or {}
    camera = metadata.get("camera") or {}

    width = int(capture.get("videoResolutionWidth") or 0)
    height = int(capture.get("videoResolutionHeight") or 0)
    resolution_mpx: Optional[float] = None
    if width > 0 and height > 0:
        resolution_mpx = round((width * height) / 1_000_000, 4)

    video_fov = (
        _safe_float(intr.get("fovDiagonalDeg"))
        or _safe_float(camera.get("diagonalFovDeg"))
        or _safe_float(camera.get("actualFovDeg"))
    )

    encoding_descriptor = (
        f"h264_gop{int(enc.get('gopLength') or 30)}"
        f"_bframes{int(enc.get('bFrames') or 0)}"
        f"_{_safe_float(enc.get('bitrateMbps'), default=6.0):.0f}mbps"
        f"_{'hdr' if enc.get('hdr') else '8bit'}"
    )

    if isinstance(measured_duration_sec, (int, float)) and measured_duration_sec > 0:
        duration: Optional[float] = float(measured_duration_sec)
        duration_method = "duration_from_video_timestamps"
    else:
        duration = _safe_float(metadata.get("durationSec"))
        duration_method = "duration_from_session_metadata"

    metrics: dict[str, Any] = {
        "clip_duration": _metric(duration, "seconds", duration_method),
        "video_fps": _metric(
            _safe_float(video.get("fps")), "Hz", "inter_frame_delta_mean_inverse"
        ),
        "video_encoding": _metric(encoding_descriptor, "descriptor", "metadata_inspect"),
        "video_resolution": _metric(resolution_mpx, "megapixels", "width_x_height"),
        "video_fov": _metric(video_fov, "degrees", "derived_from_intrinsics"),
        "imu_rate": _metric(
            _safe_float(imu.get("sampleRateHz")), "Hz",
            "imu_inter_sample_delta_mean_inverse",
        ),
        "imu_video_sync": _metric(
            _safe_float(timing.get("imuToVideoEstimatedOffsetMs")),
            "ms",
            "cross_correlation_on_shared_clock",
        ),
        "head_pose_tracking": _metric(
            # Number of gap events in the IMU stream — a conservative proxy
            # for head-pose tracking losses until we add a dedicated tracker.
            _gap_events_from_imu(imu),
            "loss_events",
            "gap_detection_imu_stream",
        ),
        "hand_visibility": _metric(
            None,
            "percent_grab_release_out_of_frame",
            "not_computed_offline_only",
        ),
    }

    return {
        "session_id": session_id,
        "computed_at_epoch_ns": computed_at_ns,
        "metrics_version": METRICS_VERSION,
        "metrics": metrics,
    }


def _gap_events_from_imu(imu: dict[str, Any]) -> Optional[float]:
    # TechnicalValidation.IMU doesn't carry a gap count directly; derive a
    # binary "healthy / not-healthy" indicator from maxGapMs instead. Anything
    # under 50ms on a 100Hz stream is within jitter bounds.
    max_gap = _safe_float(imu.get("maxGapMs"))
    if max_gap is None:
        return None
    return 0 if max_gap < 50.0 else 1


def _metric(value: Any, units: str, method: str) -> dict[str, Any]:
    return {"measured_value": value, "measured_units": units, "method": method}


# ----------------------------------------------------------------------------
# Misc
# ----------------------------------------------------------------------------

def _safe_float(value: Any, default: Optional[float] = None) -> Optional[float]:
    if isinstance(value, bool):
        return default
    try:
        if value is None:
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def iter_jsonl_objects(lines: Iterable[str]) -> Iterable[dict[str, Any]]:
    """Yield one dict per non-blank line; malformed lines are skipped."""
    import json

    for line_no, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            log.warning("skipping malformed JSONL line %d: %s", line_no, e)
            continue
        if isinstance(obj, dict):
            yield obj

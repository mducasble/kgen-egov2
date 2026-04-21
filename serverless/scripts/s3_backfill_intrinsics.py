#!/usr/bin/env python3
"""Backfill ``imu_intrinsics_<sessionId>.json`` for every egocentric capture
session already uploaded to S3.

Values are **factory-nominal** (datasheet) and derived from the device's
``hardwareIdentifier`` — no per-device calibration is performed. The file is
honestly marked ``quality: "nominal"`` and ``method: "datasheet_defaults"``
so downstream consumers can upgrade to ``"measured"`` later by running Allan
variance on a static clip and overwriting the file.

The S3 layout matches what the iOS app actually writes:

    s3://<bucket>/<campaign>/<user-slug>/<sessionId>/
        ├─ metadata_<sessionId>.json
        ├─ imu_<sessionId>.jsonl
        ├─ session_manifest_<sessionId>.json
        ├─ imu_intrinsics_<sessionId>.json   ← written by this script
        └─ ... (video, timestamps, etc.)

Legacy sessions with un-suffixed filenames (``metadata.json``) are also
picked up — the script extracts the sessionId from the parent directory
name in that case, matching the Swift-side ``SessionFiles.resolveExisting``
behaviour.

Units recap (kept here as a reminder for the datasheet constants below):
    accelerometer.bias              → G   (native CMMotionManager unit)
    accelerometer.noiseDensity      → (m/s²)/√Hz
    accelerometer.randomWalk        → (m/s²)/√s
    gyroscope.bias                  → rad/s
    gyroscope.noiseDensity          → (rad/s)/√Hz
    gyroscope.randomWalk            → (rad/s)/√s

Safety rails:
    * Only GET and PUT. Never DELETE, never touch any artifact other than
      ``imu_intrinsics_*.json`` and ``session_manifest_*.json``.
    * ``--dry-run`` reports intended actions without writing.
    * Per-session errors are caught and reported in the final summary; a
      single bad session never aborts the batch.
    * Idempotent. Re-running without ``--overwrite`` reports existing
      intrinsics files as ``skipped``.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import logging
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Constants — copied verbatim from CURSOR_PROMPT_s3_backfill.md
# ---------------------------------------------------------------------------

SCHEMA_VERSION = "1.0.0"

FACTORY_DEFAULTS: dict[str, str] = {
    # iPhone 17 family (A19 Pro / A19)
    "iPhone18,1": "apple_a19_class",   # iPhone 17 Pro
    "iPhone18,2": "apple_a19_class",   # iPhone 17 Pro Max
    "iPhone18,3": "apple_a19_class",   # iPhone 17
    "iPhone18,5": "apple_a19_class",   # iPhone 17e
    # iPhone 16 family (A18 Pro / A18)
    "iPhone17,1": "apple_a18_class",
    "iPhone17,2": "apple_a18_class",
    "iPhone17,3": "apple_a18_class",
    "iPhone17,4": "apple_a18_class",
    "iPhone17,5": "apple_a18_class",
    # iPhone 15 Pro / Pro Max (A17 Pro)
    "iPhone16,1": "apple_a17_class",
    "iPhone16,2": "apple_a17_class",
    # iPhone 15 / 15 Plus (A16)
    "iPhone15,4": "apple_a16_class",
    "iPhone15,5": "apple_a16_class",
    # iPhone 14 Pro / 14 Pro Max (also A16)
    "iPhone15,2": "apple_a16_class",
    "iPhone15,3": "apple_a16_class",
    # iPhone 13 family (A15 Bionic)
    "iPhone14,2": "apple_a15_class",   # iPhone 13 Pro
    "iPhone14,3": "apple_a15_class",   # iPhone 13 Pro Max
    "iPhone14,4": "apple_a15_class",   # iPhone 13 mini
    "iPhone14,5": "apple_a15_class",   # iPhone 13
    "iPhone14,6": "apple_a15_class",   # iPhone SE (3rd gen)
    "iPhone14,7": "apple_a15_class",   # iPhone 14
    "iPhone14,8": "apple_a15_class",   # iPhone 14 Plus
    # iPhone 11 family (A13 Bionic)
    "iPhone12,1": "apple_a13_class",   # iPhone 11
    "iPhone12,3": "apple_a13_class",   # iPhone 11 Pro
    "iPhone12,5": "apple_a13_class",   # iPhone 11 Pro Max
    "iPhone12,8": "apple_a13_class",   # iPhone SE (2nd gen)
}

SENSOR_PROFILES: dict[str, dict] = {
    "apple_a19_class": {
        "accelerometer": {"noiseDensity": 0.0020, "randomWalk": 3e-05,
                          "saturationRange": [-8.0, 8.0]},
        "gyroscope":     {"noiseDensity": 0.00017, "randomWalk": 2e-06,
                          "saturationRange": [-34.906585, 34.906585]},
    },
    "apple_a18_class": {
        "accelerometer": {"noiseDensity": 0.0023, "randomWalk": 3e-05,
                          "saturationRange": [-8.0, 8.0]},
        "gyroscope":     {"noiseDensity": 0.00019, "randomWalk": 2e-06,
                          "saturationRange": [-34.906585, 34.906585]},
    },
    "apple_a17_class": {
        "accelerometer": {"noiseDensity": 0.0025, "randomWalk": 4e-05,
                          "saturationRange": [-8.0, 8.0]},
        "gyroscope":     {"noiseDensity": 0.00022, "randomWalk": 3e-06,
                          "saturationRange": [-34.906585, 34.906585]},
    },
    "apple_a16_class": {
        "accelerometer": {"noiseDensity": 0.0028, "randomWalk": 5e-05,
                          "saturationRange": [-8.0, 8.0]},
        "gyroscope":     {"noiseDensity": 0.00025, "randomWalk": 4e-06,
                          "saturationRange": [-34.906585, 34.906585]},
    },
    # A15 Bionic (iPhone 13 family, SE 3rd gen, iPhone 14/14 Plus).
    # Uses the same LSM6DSO-class IMU as A16 devices — nominal values
    # track the A16 profile closely.
    "apple_a15_class": {
        "accelerometer": {"noiseDensity": 0.0030, "randomWalk": 5e-05,
                          "saturationRange": [-8.0, 8.0]},
        "gyroscope":     {"noiseDensity": 0.00028, "randomWalk": 5e-06,
                          "saturationRange": [-34.906585, 34.906585]},
    },
    # A13 Bionic (iPhone 11 family, SE 2nd gen). Older IMU generation with
    # slightly higher noise than A15+; kept conservative.
    "apple_a13_class": {
        "accelerometer": {"noiseDensity": 0.0035, "randomWalk": 7e-05,
                          "saturationRange": [-8.0, 8.0]},
        "gyroscope":     {"noiseDensity": 0.00035, "randomWalk": 7e-06,
                          "saturationRange": [-34.906585, 34.906585]},
    },
}

FALLBACK_PROFILE = "apple_a16_class"

CALIBRATION_NOTE = (
    "Factory-nominal values from sensor datasheet. No per-device measurement "
    "has been performed. Upgrade to quality='measured' by running Allan "
    "variance on a static recording and replacing this file."
)

EXTRINSICS_NOTE = (
    "Nominal extrinsics. IMU and camera share device coordinate frame in "
    "iOS. Translation is approximate offset from device center to ultra-wide "
    "camera sensor. For VIO/SLAM use, calibrate with Kalibr or equivalent."
)

COORDINATE_FRAME_NOTES = (
    "Standard iOS device frame per Apple docs. CMMotionManager reports "
    "accelerometer in G and gyroscope in rad/s."
)

MANIFEST_ARTIFACT_DESCRIPTION = (
    "IMU intrinsics (factory-nominal bias/noise model + camera↔IMU "
    "extrinsics). Out-of-MCAP annotation."
)

log = logging.getLogger("s3_backfill_intrinsics")

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SessionRef:
    """One session's locator on S3.

    ``dir_prefix`` is the S3 key prefix that contains the artifacts for this
    session (no trailing slash), e.g.
    ``EgoTeste-iOS/liliane-brunoro/3MKvYGICFTG6``.

    ``metadata_key`` and ``manifest_key`` are stored verbatim because some
    legacy sessions use the un-suffixed filenames (``metadata.json`` /
    ``session_manifest.json``) while current sessions use the sessionId
    suffix. New intrinsics files we write are always created with the
    suffixed name, regardless of the legacy filenames that coexist in the
    same directory.
    """
    session_id: str
    dir_prefix: str
    metadata_key: str
    manifest_key: str

    @property
    def intrinsics_filename(self) -> str:
        return f"imu_intrinsics_{self.session_id}.json"

    @property
    def intrinsics_key(self) -> str:
        return f"{self.dir_prefix}/{self.intrinsics_filename}"


@dataclass
class SessionResult:
    session_id: str
    status: str             # "written" | "skipped" | "unknown_device" | "error" | "dry_run"
    hardware_identifier: str = ""
    profile_key: str = ""
    error: str = ""
    manifest_updated: bool = False
    manifest_missing: bool = False


@dataclass
class BackfillSummary:
    bucket: str = ""
    prefix: str = ""
    dry_run: bool = False
    sessions_found: int = 0
    results: list[SessionResult] = field(default_factory=list)

    def by_status(self, status: str) -> list[SessionResult]:
        return [r for r in self.results if r.status == status]

    def device_breakdown(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for r in self.results:
            if r.status not in ("written", "dry_run", "unknown_device"):
                continue
            key = r.hardware_identifier or "unknown"
            counts[key] = counts.get(key, 0) + 1
        return counts


# ---------------------------------------------------------------------------
# Pure: build the intrinsics payload
# ---------------------------------------------------------------------------


def _profile_key_for(hardware_identifier: str) -> tuple[str, bool]:
    """Return (profile_key, device_known)."""
    if hardware_identifier in FACTORY_DEFAULTS:
        return FACTORY_DEFAULTS[hardware_identifier], True
    return FALLBACK_PROFILE, False


class LegacyMetadataError(ValueError):
    """Raised when metadata predates the ``device.hardwareIdentifier`` field.

    Separate from plain ``ValueError`` so ``process_session`` can classify it
    as a legacy skip rather than a real error.
    """


def build_intrinsics(metadata: dict, now: Optional[datetime] = None) -> dict:
    """Build the ``imu_intrinsics_<sessionId>.json`` payload from a session's
    ``metadata_<sessionId>.json`` dict.

    Pure function: no I/O, no side effects. Unit-testable via ``--self-test``.

    Raises ``ValueError`` on missing ``sessionId``. Raises
    ``LegacyMetadataError`` when ``device.hardwareIdentifier`` is absent —
    early metadata schemas didn't store it and there's no reliable way to
    infer the IMU class after the fact, so those sessions are skipped.
    """
    session_id = metadata.get("sessionId")
    if not session_id:
        raise ValueError("metadata missing sessionId")

    device = metadata.get("device") or {}
    hardware_identifier = device.get("hardwareIdentifier") or ""
    if not hardware_identifier:
        raise LegacyMetadataError("metadata missing device.hardwareIdentifier")

    collector = metadata.get("collector") or {}
    capture = metadata.get("capture") or {}

    profile_key, device_known = _profile_key_for(hardware_identifier)
    profile = SENSOR_PROFILES[profile_key]

    ts = (now or datetime.now(timezone.utc)).isoformat()

    acc = profile["accelerometer"]
    gyr = profile["gyroscope"]

    return {
        "schemaVersion": SCHEMA_VERSION,
        "sessionId": session_id,
        "deviceId": {
            "vendorId": collector.get("vendorId", ""),
            "hardwareIdentifier": hardware_identifier,
            "systemVersion": device.get("systemVersion", ""),
        },
        "calibration": {
            "method": "datasheet_defaults",
            "timestamp": ts,
            "quality": "nominal",
            "profileKey": profile_key,
            "deviceKnown": device_known,
            "note": CALIBRATION_NOTE,
        },
        "sensor": {
            "source": "CMMotionManager.deviceMotion",
            "clock": capture.get("timestampClock", "mach_absolute_time"),
            "nominalSampleRateHz": capture.get("imuTargetHz", 100),
            "coordinateFrame": {
                "convention": "right_handed",
                "axes": {
                    "x": "right (device landscape, from home button to volume buttons)",
                    "y": "up (along device long edge)",
                    "z": "out of screen (toward user)",
                },
                "notes": COORDINATE_FRAME_NOTES,
            },
        },
        "accelerometer": {
            "units": "g",
            "bias": [0.0, 0.0, 0.0],
            "scaleMisalignment": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
            "noiseDensity": acc["noiseDensity"],
            "randomWalk": acc["randomWalk"],
            "saturationRange": acc["saturationRange"],
        },
        "gyroscope": {
            "units": "rad/s",
            "bias": [0.0, 0.0, 0.0],
            "scaleMisalignment": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
            "noiseDensity": gyr["noiseDensity"],
            "randomWalk": gyr["randomWalk"],
            "saturationRange": gyr["saturationRange"],
        },
        "cameraImuExtrinsics": {
            "T_cam_imu": {
                "translation": [0.0, 0.0, -0.07],
                "rotation": {
                    "quaternion": {"w": 1.0, "x": 0.0, "y": 0.0, "z": 0.0},
                    "matrix": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
                },
            },
            "timeOffsetSec": 0.0,
            "source": "device_spec",
            "note": EXTRINSICS_NOTE,
        },
        "perSessionRefinement": None,
    }


# ---------------------------------------------------------------------------
# S3 helpers
# ---------------------------------------------------------------------------


_METADATA_SUFFIXED_RE = re.compile(r"/metadata_(?P<sid>[^/]+)\.json$")


def discover_sessions(s3, bucket: str, prefix: str) -> list[SessionRef]:
    """Walk the bucket under ``prefix`` and return one ``SessionRef`` per
    session found.

    A session is detected by the presence of ``metadata_<sid>.json`` (new
    format) or ``metadata.json`` (legacy, sessionId derived from parent
    directory name). The actual metadata/manifest key discovered is stored
    verbatim on the ref so downstream code doesn't second-guess the
    filename. Suffixed layout always wins when both are present in the same
    prefix (modern clients write both during migration in theory).
    """
    # We collect *candidates* keyed by dir_prefix. Each candidate knows which
    # metadata key was seen and which manifest key was seen. After listing,
    # we resolve the final SessionRef per prefix.
    candidates: dict[str, dict[str, Optional[str]]] = {}
    paginator = s3.get_paginator("list_objects_v2")
    pagination_args = {"Bucket": bucket}
    if prefix:
        pagination_args["Prefix"] = prefix

    def slot(dir_prefix: str) -> dict[str, Optional[str]]:
        return candidates.setdefault(dir_prefix, {
            "metadata_suffixed": None,
            "metadata_legacy":   None,
            "manifest_suffixed": None,
            "manifest_legacy":   None,
            "session_id":        None,
        })

    for page in paginator.paginate(**pagination_args):
        for obj in page.get("Contents") or ():
            key = obj["Key"]

            m = _METADATA_SUFFIXED_RE.search(key)
            if m:
                sid = m.group("sid")
                dir_prefix = key[: -len(f"/metadata_{sid}.json")]
                s = slot(dir_prefix)
                s["metadata_suffixed"] = key
                s["session_id"] = sid
                continue

            if key.endswith("/metadata.json"):
                dir_prefix = key[: -len("/metadata.json")]
                s = slot(dir_prefix)
                s["metadata_legacy"] = key
                # only use the dir name if we haven't seen a suffixed one
                if s["session_id"] is None:
                    s["session_id"] = dir_prefix.rsplit("/", 1)[-1]
                continue

            # Track manifest presence/filename too.
            sub = key.rsplit("/", 1)
            if len(sub) == 2:
                dir_prefix, fname = sub
                if fname == "session_manifest.json":
                    slot(dir_prefix)["manifest_legacy"] = key
                elif fname.startswith("session_manifest_") and fname.endswith(".json"):
                    slot(dir_prefix)["manifest_suffixed"] = key

    refs: list[SessionRef] = []
    for dir_prefix, s in candidates.items():
        if not (s["metadata_suffixed"] or s["metadata_legacy"]):
            # No metadata → not a backfill candidate. Skipped silently; it
            # will simply not appear in the session list.
            continue
        sid = s["session_id"] or dir_prefix.rsplit("/", 1)[-1]
        metadata_key = s["metadata_suffixed"] or s["metadata_legacy"]
        manifest_key = (
            s["manifest_suffixed"]
            or s["manifest_legacy"]
            or f"{dir_prefix}/session_manifest_{sid}.json"  # speculative; may 404
        )
        refs.append(SessionRef(
            session_id=sid,
            dir_prefix=dir_prefix,
            metadata_key=metadata_key,
            manifest_key=manifest_key,
        ))

    return sorted(refs, key=lambda s: s.dir_prefix)


def session_has_intrinsics(s3, bucket: str, session: SessionRef) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=session.intrinsics_key)
        return True
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def fetch_metadata(s3, bucket: str, session: SessionRef) -> dict:
    resp = s3.get_object(Bucket=bucket, Key=session.metadata_key)
    body = resp["Body"].read()
    return json.loads(body)


def fetch_manifest(s3, bucket: str, session: SessionRef) -> Optional[dict]:
    try:
        resp = s3.get_object(Bucket=bucket, Key=session.manifest_key)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound"):
            return None
        raise
    return json.loads(resp["Body"].read())


def update_manifest(manifest: dict, intrinsics_filename: str, size_bytes: int) -> dict:
    """Add the new artifact to ``manifest["artifacts"]`` in place (and return
    the same object). Idempotent — if an entry with the same filename already
    exists, it's replaced with the fresh size. The list is kept sorted by
    filename to match what the Swift writer produces.
    """
    artifacts = manifest.setdefault("artifacts", [])
    entry = {
        "filename": intrinsics_filename,
        "type": "json",
        "description": MANIFEST_ARTIFACT_DESCRIPTION,
        "sizeBytes": int(size_bytes),
        "rowCount": None,
    }
    filtered = [a for a in artifacts if a.get("filename") != intrinsics_filename]
    filtered.append(entry)
    filtered.sort(key=lambda a: a.get("filename", ""))
    manifest["artifacts"] = filtered
    return manifest


def upload_json(s3, bucket: str, key: str, payload: dict) -> int:
    body = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="application/json",
        ChecksumAlgorithm="SHA256",
    )
    return len(body)


# ---------------------------------------------------------------------------
# Per-session orchestration
# ---------------------------------------------------------------------------


def process_session(
    s3,
    bucket: str,
    session: SessionRef,
    overwrite: bool,
    dry_run: bool,
) -> SessionResult:
    """Process one session end-to-end. Catches all per-session exceptions so a
    single malformed metadata.json cannot abort the batch."""
    try:
        if not overwrite and session_has_intrinsics(s3, bucket, session):
            log.info("[%s] skip — intrinsics already present", session.session_id)
            return SessionResult(session.session_id, "skipped")

        metadata = fetch_metadata(s3, bucket, session)
        intrinsics = build_intrinsics(metadata)

        hw = intrinsics["deviceId"]["hardwareIdentifier"]
        profile_key = intrinsics["calibration"]["profileKey"]
        device_known = intrinsics["calibration"]["deviceKnown"]

        status = "dry_run" if dry_run else ("written" if device_known else "unknown_device")

        if dry_run:
            log.info(
                "[%s] dry-run — would write %s (hw=%s, profile=%s, known=%s)",
                session.session_id, session.intrinsics_key, hw, profile_key, device_known,
            )
            return SessionResult(
                session.session_id, status,
                hardware_identifier=hw, profile_key=profile_key,
            )

        # Real upload.
        size_bytes = upload_json(s3, bucket, session.intrinsics_key, intrinsics)
        log.info(
            "[%s] wrote %s (%d bytes, profile=%s, known=%s)",
            session.session_id, session.intrinsics_filename, size_bytes,
            profile_key, device_known,
        )

        # Manifest update (best-effort, non-fatal).
        manifest_updated = False
        manifest_missing = False
        manifest = fetch_manifest(s3, bucket, session)
        if manifest is None:
            manifest_missing = True
            log.warning(
                "[%s] session_manifest missing — intrinsics uploaded but "
                "manifest not updated", session.session_id,
            )
        else:
            update_manifest(manifest, session.intrinsics_filename, size_bytes)
            upload_json(s3, bucket, session.manifest_key, manifest)
            manifest_updated = True
            log.info("[%s] manifest updated", session.session_id)

        if not device_known:
            log.warning(
                "[%s] unknown hardwareIdentifier %r — used fallback profile %s",
                session.session_id, hw, profile_key,
            )

        return SessionResult(
            session.session_id, status,
            hardware_identifier=hw, profile_key=profile_key,
            manifest_updated=manifest_updated, manifest_missing=manifest_missing,
        )

    except LegacyMetadataError as exc:
        # Pre-hardwareIdentifier schema — silently skip, user asked to
        # ignore old sessions.
        log.info("[%s] skip — legacy metadata (%s)", session.session_id, exc)
        return SessionResult(session.session_id, "skipped_legacy")
    except ValueError as exc:
        # Malformed metadata — log and move on, per spec.
        log.error("[%s] bad metadata: %s", session.session_id, exc)
        return SessionResult(session.session_id, "error", error=str(exc))
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "ClientError")
        msg = f"{code}: {exc.response.get('Error', {}).get('Message', '')}"
        log.error("[%s] S3 error: %s", session.session_id, msg)
        return SessionResult(session.session_id, "error", error=msg)
    except Exception as exc:  # noqa: BLE001 — intentional catch-all per spec
        log.exception("[%s] unexpected error", session.session_id)
        return SessionResult(session.session_id, "error", error=str(exc))


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------


SELF_TEST_METADATA = {
    "sessionId": "3MKvYGICFTG6",
    "device": {
        "deviceName": "iPhone",
        "hardwareIdentifier": "iPhone18,2",
        "model": "iPhone18,2",
        "systemVersion": "26.3.1",
    },
    "collector": {
        "vendorId": "5A98FCA4-DE8A-4263-A2EE-E910D48F7B16",
        "userName": "Liliane Brunoro",
        "userSlug": "liliane-brunoro",
    },
    "capture": {
        "timestampClock": "mach_absolute_time",
        "imuTargetHz": 100,
    },
}


def self_test() -> int:
    out = build_intrinsics(SELF_TEST_METADATA)

    # Structural assertions against the reference example in the spec.
    expected_top_level = {
        "schemaVersion", "sessionId", "deviceId", "calibration", "sensor",
        "accelerometer", "gyroscope", "cameraImuExtrinsics", "perSessionRefinement",
    }
    assert set(out.keys()) == expected_top_level, f"unexpected top-level keys: {set(out.keys()) ^ expected_top_level}"

    assert out["schemaVersion"] == "1.0.0"
    assert out["sessionId"] == "3MKvYGICFTG6"
    assert out["deviceId"]["hardwareIdentifier"] == "iPhone18,2"
    assert out["deviceId"]["vendorId"] == "5A98FCA4-DE8A-4263-A2EE-E910D48F7B16"
    assert out["deviceId"]["systemVersion"] == "26.3.1"

    cal = out["calibration"]
    assert cal["method"] == "datasheet_defaults"
    assert cal["quality"] == "nominal"
    assert cal["profileKey"] == "apple_a19_class"
    assert cal["deviceKnown"] is True
    assert "Factory-nominal" in cal["note"]

    sensor = out["sensor"]
    assert sensor["source"] == "CMMotionManager.deviceMotion"
    assert sensor["clock"] == "mach_absolute_time"
    assert sensor["nominalSampleRateHz"] == 100
    assert sensor["coordinateFrame"]["convention"] == "right_handed"

    acc = out["accelerometer"]
    assert acc["units"] == "g"
    assert acc["bias"] == [0.0, 0.0, 0.0]
    assert acc["noiseDensity"] == 0.0020
    assert acc["randomWalk"] == 3e-05
    assert acc["saturationRange"] == [-8.0, 8.0]

    gyr = out["gyroscope"]
    assert gyr["units"] == "rad/s"
    assert gyr["noiseDensity"] == 0.00017
    assert gyr["randomWalk"] == 2e-06
    assert gyr["saturationRange"] == [-34.906585, 34.906585]

    ext = out["cameraImuExtrinsics"]
    assert ext["T_cam_imu"]["translation"] == [0.0, 0.0, -0.07]
    assert ext["T_cam_imu"]["rotation"]["quaternion"] == {"w": 1.0, "x": 0.0, "y": 0.0, "z": 0.0}
    assert ext["timeOffsetSec"] == 0.0
    assert ext["source"] == "device_spec"

    assert out["perSessionRefinement"] is None

    # Unknown device → fallback, deviceKnown=False.
    unknown_meta = dict(SELF_TEST_METADATA)
    unknown_meta["device"] = dict(SELF_TEST_METADATA["device"])
    unknown_meta["device"]["hardwareIdentifier"] = "iPhone99,99"
    unknown_out = build_intrinsics(unknown_meta)
    assert unknown_out["calibration"]["deviceKnown"] is False
    assert unknown_out["calibration"]["profileKey"] == FALLBACK_PROFILE

    # Missing required fields → ValueError.
    try:
        build_intrinsics({"device": {"hardwareIdentifier": "iPhone18,2"}})
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for missing sessionId")

    # Manifest update idempotency.
    manifest = {"sessionId": "X", "createdAtEpochMs": 0, "artifacts": []}
    update_manifest(manifest, "imu_intrinsics_X.json", 1234)
    update_manifest(manifest, "imu_intrinsics_X.json", 5678)
    assert len(manifest["artifacts"]) == 1
    assert manifest["artifacts"][0]["sizeBytes"] == 5678
    assert manifest["artifacts"][0]["rowCount"] is None

    print("self-test OK")
    return 0


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def print_summary(summary: BackfillSummary) -> None:
    written = summary.by_status("written")
    skipped = summary.by_status("skipped")
    skipped_legacy = summary.by_status("skipped_legacy")
    unknown = summary.by_status("unknown_device")
    dry = summary.by_status("dry_run")
    errors = summary.by_status("error")
    manifest_missing = [r for r in summary.results if r.manifest_missing]

    newly_written = len(written) + len(unknown)

    lines = [
        "",
        "=== S3 IMU Intrinsics Backfill — Summary ===",
        f"Bucket:           {summary.bucket}",
        f"Prefix:           {summary.prefix or '(root)'}",
        f"Sessions found:   {summary.sessions_found}",
        f"Already had file: {len(skipped)} (skipped)",
        f"Legacy skipped:   {len(skipped_legacy)} (pre-hardwareIdentifier metadata)",
    ]

    if summary.dry_run:
        lines.append(f"Would write:      {len(dry)}")
    else:
        lines.append(f"Newly written:    {newly_written}")
        lines.append(f"Unknown device:   {len(unknown)} (used fallback profile)")
        if manifest_missing:
            lines.append(f"Manifest missing: {len(manifest_missing)} (intrinsics uploaded, manifest untouched)")

    lines.append(f"Errors:           {len(errors)}")
    for r in errors[:20]:
        lines.append(f"  - {r.session_id}: {r.error.splitlines()[0] if r.error else 'unknown error'}")
    if len(errors) > 20:
        lines.append(f"  ... and {len(errors) - 20} more")

    breakdown = summary.device_breakdown()
    if breakdown:
        lines.append("")
        label = "Device breakdown (would write):" if summary.dry_run else "Device breakdown (newly written):"
        lines.append(label)
        width = max(len(k) for k in breakdown)
        for hw, n in sorted(breakdown.items(), key=lambda kv: -kv[1]):
            lines.append(f"  {hw.ljust(width)}: {n}")

    if summary.dry_run:
        lines.append("")
        lines.append("Dry run: no changes committed.")

    print("\n".join(lines))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_s3_client(profile: Optional[str], region: Optional[str]):
    session = boto3.Session(profile_name=profile) if profile else boto3.Session()
    cfg = Config(retries={"max_attempts": 10, "mode": "adaptive"})
    return session.client("s3", region_name=region, config=cfg)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Backfill imu_intrinsics_<sessionId>.json for existing egocentric sessions on S3.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--bucket", help="S3 bucket name. Required unless --self-test.")
    parser.add_argument("--prefix", default="", help="S3 key prefix to scan (e.g. 'EgoTeste-iOS/').")
    parser.add_argument("--dry-run", action="store_true", help="Report intended actions, no writes.")
    parser.add_argument("--overwrite", action="store_true", help="Re-write existing imu_intrinsics files.")
    parser.add_argument("--limit", type=int, default=0, help="Process at most N sessions (0 = all).")
    parser.add_argument("--workers", type=int, default=8, help="Parallel worker threads.")
    parser.add_argument("--profile", default=None, help="AWS profile name (uses default credential chain otherwise).")
    parser.add_argument("--region", default=None, help="AWS region override.")
    parser.add_argument("--verbose", action="store_true", help="DEBUG-level logging.")
    parser.add_argument("--self-test", action="store_true", help="Run offline build_intrinsics test and exit.")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        datefmt="%H:%M:%S",
    )

    if args.self_test:
        return self_test()

    if not args.bucket:
        parser.error("--bucket is required (or use --self-test)")

    s3 = _build_s3_client(args.profile, args.region)

    log.info("Discovering sessions in s3://%s/%s ...", args.bucket, args.prefix)
    sessions = discover_sessions(s3, args.bucket, args.prefix)
    log.info("Found %d session(s).", len(sessions))

    if args.limit and args.limit > 0:
        sessions = sessions[: args.limit]
        log.info("Limited to first %d session(s).", len(sessions))

    summary = BackfillSummary(
        bucket=args.bucket,
        prefix=args.prefix,
        dry_run=args.dry_run,
        sessions_found=len(sessions),
    )

    workers = max(1, args.workers)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [
            pool.submit(process_session, s3, args.bucket, s, args.overwrite, args.dry_run)
            for s in sessions
        ]
        for fut in concurrent.futures.as_completed(futures):
            summary.results.append(fut.result())

    print_summary(summary)
    return 1 if summary.by_status("error") else 0


if __name__ == "__main__":
    sys.exit(main())

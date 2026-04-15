# EgoCapture — Egocentric Video Data Collection for AI Training

Native iOS app for capturing egocentric human demonstration data with synchronized video, IMU, head pose, hand landmarks, and structured metadata. Designed for AI dataset ingestion per the Figure Ego Video Data Collection specification.

## Requirements

- **Xcode 15.2+**
- **iOS 17.0+**
- **Physical iPhone** (ARKit and CoreMotion require real hardware — Simulator will not work)
- iPhone with A12 chip or later (for ARKit world tracking and Vision hand pose)

## How to Run

1. Open `EgoCapture.xcodeproj` in Xcode
2. Select your physical iPhone as the build target
3. Set your development team under Signing & Capabilities
4. Build and run (⌘R)
5. Grant camera and motion permissions when prompted

## Architecture

```
EgoCapture/
├── EgoCaptureApp.swift          # App entry point
├── RecordingOrchestrator.swift   # Central recording lifecycle coordinator
├── SessionManager.swift          # Session directory management
│
├── Models/                       # All data models (Codable structs)
│   ├── IMUSample.swift
│   ├── HeadPoseSample.swift
│   ├── CameraCalibration.swift
│   ├── CameraMountConfig.swift
│   ├── HandLandmarkSample.swift
│   ├── HandPoseSample.swift
│   ├── FacePresenceSample.swift
│   ├── FrameQCMetrics.swift
│   ├── VideoTimestamp.swift
│   ├── SessionMetadata.swift
│   └── SessionManifest.swift
│
├── Services/
│   ├── Capture/
│   │   ├── VideoCaptureService.swift       # AVFoundation H.264 recording
│   │   ├── IMUCaptureService.swift         # CoreMotion accel+gyro at ~100Hz
│   │   ├── HeadPoseService.swift           # ARKit world tracking
│   │   ├── CameraCalibrationService.swift  # Intrinsics extraction
│   │   └── MountCalibrationService.swift   # Manual extrinsics config
│   ├── Vision/
│   │   ├── HandLandmarkService.swift       # Hand detection (swappable backend)
│   │   ├── HandPoseDerivationService.swift # Joint angle computation
│   │   ├── FacePresenceService.swift       # Face detection for QC
│   │   └── FrameQCService.swift            # Brightness, blur, presence metrics
│   └── Packaging/
│       └── SessionPackagingService.swift   # Metadata + manifest writer
│
├── Views/
│   ├── ContentView.swift
│   ├── RecordingView.swift
│   └── SessionListView.swift
│
└── Utils/
    └── JSONLWriter.swift                   # Thread-safe JSONL streaming writer
```

## Session Output

Each recording session produces the following directory structure:

```
Documents/sessions/{sessionId}/
  video.mp4                 # H.264 encoded video, 30 FPS, 6 Mbps, GOP=30, no B-frames
  imu.jsonl                 # Accelerometer + gyroscope at ~100 Hz
  head_pose.jsonl           # ARKit camera transform (position + quaternion)
  video_timestamps.jsonl    # Per-frame timestamps from CMSampleBuffer
  camera_calibration.json   # Camera intrinsics (fx, fy, cx, cy, matrix)
  camera_mount.json         # Camera extrinsic mount config (manual)
  hand_landmarks.jsonl      # 21-landmark hand detections per frame
  hand_pose.jsonl           # Derived fingertip positions + joint angles
  face_presence.jsonl       # Per-frame face detection boolean
  frame_qc_metrics.jsonl    # Brightness, blur, detection flags per frame
  metadata.json             # Session info, device, capture config, QC summary
  session_manifest.json     # Artifact inventory with sizes and row counts
```

## Artifact Details

### video.mp4
- Codec: H.264 (NOT H.265/HEVC)
- Container: MP4
- Target: 1920x1080, 30 FPS, ~6 Mbps
- GOP length: 30
- No B-frames (frame reordering disabled)

### imu.jsonl
- Source: CoreMotion `CMDeviceMotion`
- Target rate: 100 Hz (actual rate reported in metadata)
- Accelerometer: total acceleration in G's (user acceleration + gravity)
- Gyroscope: rotation rate in radians/second
- First 10 samples are discarded to avoid startup noise

### head_pose.jsonl
- Source: ARKit `ARWorldTrackingConfiguration`
- Position: meters relative to ARKit world origin
- Rotation: unit quaternion (Hamilton convention)
- Tracking state: `"normal"`, `"limited"`, or `"notAvailable"`

**This is true native head pose from ARKit's visual-inertial odometry, NOT derived from IMU alone.**

### camera_calibration.json
- Source: ARKit `ARCamera.intrinsics`
- Contains: fx, fy, cx, cy, full 3x3 matrix
- Distortion: noted as unavailable if not provided by the device
- Resolution reference included

### camera_mount.json
- **Manually configured** — NOT automatically inferred
- Represents camera position/orientation relative to head center
- Default: forehead mount, 30° downward tilt
- **Must be adjusted** for your specific hardware mounting

### hand_landmarks.jsonl
- Source: Apple Vision `VNDetectHumanHandPoseRequest`
- 21 landmarks per hand (MediaPipe-compatible indexing)
- Coordinates: normalized image space [0,1] for x,y
- **z values are set to 0.0** — Apple Vision does NOT provide metric 3D depth
- Up to 2 hands per frame
- Chirality (left/right) from Vision framework

### hand_pose.jsonl
- Derived from hand_landmarks.jsonl
- Fingertip positions extracted from landmarks
- Joint angles computed geometrically (angle at vertex B in chain A→B→C)
- Thumb opposition angle: angle between thumb-tip and pinky-tip vectors from wrist
- **Null values** indicate unreliable or uncomputable measurements
- Angles are in degrees

### face_presence.jsonl
- Source: Apple Vision `VNDetectFaceRectanglesRequest`
- Boolean face detection per frame
- For privacy screening and QC purposes

### frame_qc_metrics.jsonl
- Brightness: average luminance [0,1] via weighted RGB→luma conversion
- Blur: Laplacian variance (higher = sharper)
- Detection flags: hand and face presence booleans

### metadata.json
- Complete session description
- Device info, capture config, actual sample rates
- QC summary (hand/face presence rates, brightness/blur statistics)
- **Warnings array**: lists all known caveats (estimated timestamps, 2D landmarks, etc.)

### session_manifest.json
- Inventory of all artifacts with file sizes and JSONL row counts
- Machine-readable session index

## Known Limitations

1. **Hand landmarks are 2D only.** Apple Vision provides normalized image coordinates. The z=0 values are NOT metric 3D. The metadata flags this via `handLandmarksAre3D: false`.

2. **Video timestamps are from CMSampleBuffer** and represent presentation time. They are NOT estimated by default — the `isEstimated` field will be `false` for samples captured via the normal pipeline.

3. **Camera mount config is a manual estimate.** The default forehead mount assumes 3cm up, 8cm forward, 30° down. You MUST adjust this for your specific hardware.

4. **Vision processing is throttled.** Hand landmarks, face detection, and QC metrics are computed every 3rd frame (~10 FPS) to maintain video recording performance. Not every video frame has a corresponding vision result.

5. **ARKit and AVFoundation run separate camera sessions.** Head pose timestamps and video timestamps may have slight offset. Both use epoch-relative timing for cross-referencing.

6. **No MediaPipe integration yet.** The `HandLandmarkService` uses Apple Vision as the default backend. The `MediaPipeHandBackend` is a placeholder. To integrate MediaPipe iOS SDK:
   - Add `MediaPipeTasksVision` via Swift Package Manager
   - Implement the `HandLandmarkBackend` protocol in `MediaPipeHandBackend`
   - Switch the backend in `RecordingOrchestrator`

7. **No audio capture.** The spec focuses on video + sensor data.

## Hand Landmark Backend Architecture

The hand detection pipeline is designed for backend swapping:

```swift
protocol HandLandmarkBackend {
    func detectHands(in pixelBuffer: CVPixelBuffer) -> [DetectedHand]
    var backendName: String { get }
    var provides3D: Bool { get }
}
```

Current backends:
- `AppleVisionHandBackend` (default) — uses iOS Vision framework, 2D landmarks
- `MediaPipeHandBackend` (placeholder) — for future MediaPipe iOS SDK integration

To switch backends, change the initializer in `RecordingOrchestrator.startRecording()`:
```swift
let handLandmarks = HandLandmarkService(backend: MediaPipeHandBackend())
```

## Data Integrity Principles

- **Never fake precision**: estimated values are flagged as estimated
- **Null over invention**: unreliable joint angles are null, not guessed
- **2D is 2D**: we don't pretend image-space landmarks are metric 3D
- **Tracking state preserved**: ARKit tracking quality is recorded honestly
- **Startup noise discarded**: first 10 IMU samples are dropped
- **Real sample rates**: actual Hz values are computed and reported, not assumed

## Accessing Session Data

Sessions are stored in the app's Documents directory. To extract data:

1. **Xcode**: Window → Devices and Simulators → select device → EgoCapture → Download Container
2. **Files app**: Sessions are in the app's documents folder
3. **Programmatically**: Use `SessionManager.shared.sessionsRoot` to get the path

## Spec Compliance

| Requirement | Status |
|---|---|
| H.264 MP4 video | ✅ |
| 30 FPS target | ✅ |
| ≥2 MP resolution | ✅ (1920x1080) |
| 4-9 Mbps bitrate | ✅ (6 Mbps target) |
| GOP length 30 | ✅ |
| No B-frames | ✅ |
| IMU at 100 Hz | ✅ |
| Head pose (ARKit) | ✅ |
| Camera intrinsics | ✅ |
| Camera extrinsics (manual) | ✅ |
| Hand landmarks (21 pts) | ✅ |
| Hand pose derivation | ✅ |
| Face presence | ✅ |
| Frame QC metrics | ✅ |
| JSONL format | ✅ |
| Session packaging | ✅ |
| Stereo/depth camera | ❌ Optional |
| MCAP format | ❌ Optional |

package com.kgeneye.eye.capture

import android.content.Context
import android.provider.Settings
import android.util.Log
import android.view.Surface
import android.hardware.camera2.CaptureRequest
import android.util.Range
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExposureState
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.kgeneye.eye.session.CameraFormatDiagnosticsWriter
import com.kgeneye.eye.session.ChunkManifestWriter
import com.kgeneye.eye.session.ImuIntrinsicsWriter
import com.kgeneye.eye.session.SessionFiles
import com.kgeneye.eye.session.SessionManager
import com.kgeneye.eye.session.SessionWriter
import com.kgeneye.eye.session.SyncAnalysis
import com.kgeneye.eye.session.TaxonomyWriter
import com.kgeneye.eye.session.TechnicalValidationWriter
import com.kgeneye.eye.session.ThumbnailGenerator
import com.kgeneye.eye.settings.AppSettings
import com.kgeneye.eye.settings.CampaignConfig
import com.kgeneye.eye.taxonomy.SessionTaxonomy
import com.kgeneye.eye.upload.UploadManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Holds the capture pipeline state for a single recording screen.
 *
 * - starts / stops CameraX (preview + video capture + image analysis)
 * - starts / stops [ImuCaptureService] alongside the recorder
 * - writes video timestamps via [VideoTimestampsService]
 * - on finalize, persists `taxonomy_<code>.json`, `metadata_<code>.json`,
 *   `session_manifest_<code>.json`, and hands the session off to
 *   [UploadManager]
 */
class SessionRecorder(private val context: Context) {

    data class UiState(
        val isRecording: Boolean = false,
        val isReady: Boolean = false,
        val status: String = "Preparing camera…",
        val sessionId: String? = null,
        val taxonomyTitle: String? = null,
        val recordingDurationSec: Double = 0.0,
        val frameCount: Int = 0,
        val imuSamples: Int = 0,
        val imuRateHz: Double = 0.0,
        val lastError: String? = null,
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var tickerJob: Job? = null

    private val sessionManager = SessionManager.get(context)
    private val uploadManager = UploadManager.get(context)

    private var videoCapture: VideoCapture<Recorder>? = null
    private var preview: Preview? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var activeRecording: Recording? = null
    private var pendingTaxonomy: SessionTaxonomy? = null

    /** Resolved camera the pipeline is bound to. Captured for metadata.json. */
    private var selectedCamera: CameraSelectionPolicy.Selected? = null
    private var boundCamera: Camera? = null
    private var appliedExposurePolicy: String = "auto"

    private var currentSession: SessionManager.Session? = null
    private var currentVideoFile: File? = null
    private var currentImuFile: File? = null
    private var currentTimestampsFile: File? = null

    private var imuService: ImuCaptureService? = null
    private val timestampsService = VideoTimestampsService()

    private var recordingStartEpochMs: Double = 0.0

    @androidx.camera.camera2.interop.ExperimentalCamera2Interop
    fun bindToLifecycle(
        lifecycleOwner: LifecycleOwner,
        previewView: PreviewView,
    ) {
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            try {
                val provider = providerFuture.get()
                val rotation = previewView.display?.rotation ?: Surface.ROTATION_0

                val pick = CameraSelectionPolicy.pick(context)
                selectedCamera = pick
                val targetCameraId = pick?.cameraId
                val cameraSelector = buildSelectorFor(targetCameraId)

                val fpsRange = Range(30, 30)

                val previewBuilder = Preview.Builder().setTargetRotation(rotation)
                Camera2Interop.Extender(previewBuilder)
                    .setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)
                val previewUseCase = previewBuilder.build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

                val recorder = Recorder.Builder()
                    .setQualitySelector(
                        QualitySelector.from(
                            Quality.FHD,
                            androidx.camera.video.FallbackStrategy.higherQualityOrLowerThan(Quality.HD)
                        )
                    ).build()
                val captureBuilder = VideoCapture.Builder(recorder).setTargetRotation(rotation)
                Camera2Interop.Extender(captureBuilder)
                    .setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)
                val capture = captureBuilder.build()

                val analysisBuilder = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setTargetRotation(rotation)
                Camera2Interop.Extender(analysisBuilder)
                    .setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)
                val analysis = analysisBuilder.build().also { ia ->
                    ia.setAnalyzer(analysisExecutor, ImageAnalysis.Analyzer { image: ImageProxy ->
                        try { timestampsService.record(image) } finally { image.close() }
                    })
                }

                preview = previewUseCase
                videoCapture = capture
                imageAnalysis = analysis

                provider.unbindAll()
                val camera = provider.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    previewUseCase,
                    capture,
                    analysis,
                )
                boundCamera = camera
                appliedExposurePolicy = applyExposureBias(camera, EXPOSURE_BIAS_EV)

                _state.value = _state.value.copy(isReady = true, status = "Ready — press to record.")
            } catch (t: Throwable) {
                Log.e(TAG, "Binding failed", t)
                _state.value = _state.value.copy(status = "Camera bind failed: ${t.message}", lastError = t.message)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    /**
     * Build a [CameraSelector] that targets [targetCameraId] when provided
     * and falls back to the default back camera otherwise. Mirrors the
     * iOS `AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera])`
     * intent.
     */
    @androidx.camera.camera2.interop.ExperimentalCamera2Interop
    private fun buildSelectorFor(targetCameraId: String?): CameraSelector {
        if (targetCameraId == null) return CameraSelector.DEFAULT_BACK_CAMERA
        return CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_BACK)
            .addCameraFilter { cameraInfos ->
                val matched = cameraInfos.filter { info ->
                    try { Camera2CameraInfo.from(info).cameraId == targetCameraId }
                    catch (_: Throwable) { false }
                }
                matched.ifEmpty { cameraInfos }
            }
            .build()
    }

    /**
     * Apply a static exposure compensation that biases the auto-exposure
     * algorithm toward slightly darker frames — matches the iOS
     * `setExposureTargetBias(-0.25)` policy. Returns a label suitable for
     * `metadata.capture.exposurePolicy`.
     */
    private fun applyExposureBias(camera: Camera, biasEv: Double): String {
        val state: ExposureState = camera.cameraInfo.exposureState
        if (!state.isExposureCompensationSupported) return "auto_unsupported"
        val step = state.exposureCompensationStep
        if (step.numerator == 0 || step.denominator == 0) return "auto"
        val stepFloat = step.numerator.toDouble() / step.denominator.toDouble()
        if (stepFloat <= 0) return "auto"
        val targetIndex = Math.round(biasEv / stepFloat).toInt()
        val range = state.exposureCompensationRange
        val clamped = targetIndex.coerceIn(range.lower, range.upper)
        return try {
            camera.cameraControl.setExposureCompensationIndex(clamped)
            val appliedEv = clamped * stepFloat
            String.format(Locale.US, "bias_%+.2fEV", appliedEv)
        } catch (t: Throwable) {
            Log.w(TAG, "exposure bias failed: ${t.message}")
            "auto_failed"
        }
    }

    /**
     * Re-applies the current display rotation to all CameraX use cases.
     * Called when the activity finishes its landscape rotation so the
     * pipeline stays in landscape regardless of the boot orientation.
     */
    fun applyRotation(rotation: Int) {
        preview?.targetRotation = rotation
        videoCapture?.targetRotation = rotation
        imageAnalysis?.targetRotation = rotation
    }

    fun setPendingTaxonomy(taxonomy: SessionTaxonomy?) {
        pendingTaxonomy = taxonomy
        _state.value = _state.value.copy(taxonomyTitle = taxonomy?.taskCategoryLabelEn)
    }

    fun toggleRecording() {
        val capture = videoCapture ?: return
        val ongoing = activeRecording
        if (ongoing != null) {
            ongoing.stop()
            return
        }
        startNew(capture)
    }

    private fun startNew(capture: VideoCapture<Recorder>) {
        val session = sessionManager.createSession()
        currentSession = session

        val videoFile = SessionFiles.file("video", "mp4", session.directory)
        val imuFile = SessionFiles.file("imu", "jsonl", session.directory)
        val timestampsFile = SessionFiles.file("video_timestamps", "jsonl", session.directory)
        currentVideoFile = videoFile
        currentImuFile = imuFile
        currentTimestampsFile = timestampsFile

        val imu = ImuCaptureService(context)
        if (!imu.isAvailable) {
            _state.value = _state.value.copy(status = "Device is missing accelerometer or gyroscope.",
                lastError = "imu-unavailable")
            return
        }
        try {
            imu.start(imuFile)
            imuService = imu
        } catch (t: Throwable) {
            _state.value = _state.value.copy(status = "IMU start failed: ${t.message}", lastError = t.message)
            return
        }
        timestampsService.start(timestampsFile)

        recordingStartEpochMs = System.currentTimeMillis().toDouble()

        val output = FileOutputOptions.Builder(videoFile).build()
        activeRecording = capture.output
            .prepareRecording(context, output)
            .start(ContextCompat.getMainExecutor(context)) { event ->
                when (event) {
                    is VideoRecordEvent.Start -> {
                        _state.value = _state.value.copy(
                            isRecording = true,
                            sessionId = session.id,
                            status = "Recording ${session.id}…",
                            recordingDurationSec = 0.0,
                            frameCount = 0,
                            imuSamples = 0,
                            imuRateHz = 0.0,
                        )
                        startTicker()
                    }
                    is VideoRecordEvent.Finalize -> finalizeRecording(event)
                    else -> Unit
                }
            }
    }

    /**
     * 0.5 s ticker that mirrors the iOS orchestrator timer: pushes elapsed
     * duration, IMU sample count / rate, and frame count to the UI.
     */
    private fun startTicker() {
        tickerJob?.cancel()
        tickerJob = scope.launch {
            while (isActive && activeRecording != null) {
                val now = System.currentTimeMillis().toDouble()
                val durationSec = ((now - recordingStartEpochMs) / 1000.0).coerceAtLeast(0.0)
                val samples = imuService?.totalSamples ?: 0
                val rate = imuService?.actualSampleRateHz ?: 0.0
                val frames = timestampsService.frameCount
                _state.value = _state.value.copy(
                    recordingDurationSec = durationSec,
                    imuSamples = samples,
                    imuRateHz = rate,
                    frameCount = frames,
                )
                delay(500)
            }
        }
    }

    private fun finalizeRecording(event: VideoRecordEvent.Finalize) {
        tickerJob?.cancel(); tickerJob = null

        val imu = imuService
        imu?.stop()
        imuService = null
        timestampsService.stop()
        activeRecording = null

        val session = currentSession ?: return
        val videoFile = currentVideoFile ?: return
        val imuFile = currentImuFile ?: return
        val timestampsFile = currentTimestampsFile
        currentSession = null
        currentVideoFile = null
        currentImuFile = null
        currentTimestampsFile = null

        if (event.hasError()) {
            val msg = event.cause?.message ?: "error ${event.error}"
            _state.value = _state.value.copy(isRecording = false, status = "Recorder error: $msg",
                lastError = msg)
            return
        }

        pendingTaxonomy?.let { taxonomy ->
            try {
                TaxonomyWriter.write(session.directory, taxonomy)
            } catch (t: Throwable) { Log.e(TAG, "taxonomy write failed", t) }
        }

        val metrics = imu?.metrics() ?: ImuCaptureService.Metrics(0, 0.0, 0, 0.0, 0.0, 0)
        val taxonomy = pendingTaxonomy
        val totalFrames = timestampsService.frameCount
        val videoTsNs = timestampsService.allTimestampsNs()
        val imuTsNs = imu?.allTimestampsNs() ?: LongArray(0)
        val avgFps = computeAvgFps(videoTsNs)
        val frameStdDev = computeFrameIntervalStdDevMs(videoTsNs)
        val sync = SyncAnalysis.computeIMUVideoSync(videoTsNs, imuTsNs)

        val (frameW, frameH) = probeVideoDimensions(videoFile)
        val intrinsicsBlock = selectedCamera?.let { sel ->
            val read = CameraIntrinsicsReader.read(context, sel.cameraId, frameW, frameH)
            SessionWriter.CameraIntrinsics(
                source = read.intrinsicsSource,
                cameraId = sel.cameraId,
                isUltraWide = sel.isUltraWide,
                focalLengthMm = sel.focalLengthMm,
                sensorWidthMm = sel.sensorWidthMm,
                sensorHeightMm = sel.sensorHeightMm,
                fx = read.fx, fy = read.fy, cx = read.cx, cy = read.cy, skew = read.skew,
                distortion = read.distortion,
                horizontalFovDeg = read.horizontalFovDeg,
                diagonalFovDeg = read.diagonalFovDeg,
            )
        }

        val summary = SessionWriter.RecordingSummary(
            sessionId = session.id,
            startEpochMs = recordingStartEpochMs,
            endEpochMs = System.currentTimeMillis().toDouble(),
            video = SessionWriter.VideoInfo(
                filename = videoFile.name,
                sizeBytes = videoFile.length(),
                widthPx = frameW.takeIf { it > 0 },
                heightPx = frameH.takeIf { it > 0 },
                targetFps = 30,
                codec = "avc",
            ),
            imuFilename = imuFile.name,
            imuSizeBytes = imuFile.length(),
            imuRowCount = imu?.totalSamples ?: 0,
            imuMetrics = metrics,
            avgFps = avgFps,
            frameIntervalStdDevMs = frameStdDev,
            totalFrames = totalFrames,
            droppedFrames = 0,
            cameraIntrinsics = intrinsicsBlock,
            exposurePolicy = appliedExposurePolicy,
            taxonomy = taxonomy,
            collector = collectorInfo(),
            pipelineBuild = "android-step7-ios-schema",
        )

        try {
            SessionWriter.writeMetadata(session.directory, summary, sync)
        } catch (t: Throwable) { Log.e(TAG, "metadata write failed", t) }

        try {
            ImuIntrinsicsWriter.write(
                sessionDir = session.directory,
                sessionId = session.id,
                imuTargetHz = 100,
                timestampClock = "elapsed_realtime_nanos",
            )
        } catch (t: Throwable) { Log.e(TAG, "imu_intrinsics write failed", t) }

        try {
            CameraFormatDiagnosticsWriter.write(
                context = context,
                sessionDir = session.directory,
                selectedWidth = summary.video.widthPx,
                selectedHeight = summary.video.heightPx,
                cameraId = selectedCamera?.cameraId,
            )
        } catch (t: Throwable) { Log.e(TAG, "camera_format_diagnostics write failed", t) }

        try {
            TechnicalValidationWriter.write(
                sessionDir = session.directory,
                inputs = TechnicalValidationWriter.Inputs(
                    sessionId = session.id,
                    sync = sync,
                    imuMetrics = metrics,
                    avgFps = avgFps,
                    frameIntervalStdDevMs = frameStdDev,
                    totalFrames = totalFrames,
                    droppedFrames = 0,
                    bitrateMbps = 6.0,
                    gopLength = 30,
                    intrinsicsAvailable = true,
                    distortionAvailable = false,
                ),
            )
        } catch (t: Throwable) { Log.e(TAG, "technical_validation write failed", t) }

        try {
            val vision = PostCaptureVisionAnalyzer.analyze(
                context = context,
                videoFile = videoFile,
                sessionDir = session.directory,
                recordingStartEpochMs = recordingStartEpochMs,
                timestampsNs = videoTsNs,
            )
            Log.i(
                TAG,
                "post-capture QC analyzed ${vision.frameQcRows} frames; hands frames=${vision.framesWithHands}, total hands=${vision.totalHandsDetected}, hand detector ready=${vision.handDetectorReady}, hand rows=${vision.handRows}, face rows=${vision.faceRows}",
            )
        } catch (t: Throwable) { Log.e(TAG, "post-capture vision analysis failed", t) }

        try {
            ChunkManifestWriter.write(
                sessionDir = session.directory,
                sessionId = session.id,
                originalFilename = videoFile.name,
                totalDurationSec = (summary.endEpochMs - summary.startEpochMs) / 1000.0,
            )
        } catch (t: Throwable) { Log.e(TAG, "chunk_manifest write failed", t) }

        try {
            SessionWriter.writeSessionManifest(session.directory, summary)
        } catch (t: Throwable) { Log.e(TAG, "manifest write failed", t) }

        uploadManager.startUpload(session.id, session.directory)

        scope.launch(Dispatchers.IO) {
            try { ThumbnailGenerator.generateIfNeeded(session.directory) }
            catch (t: Throwable) { Log.w(TAG, "thumbnail gen failed: ${t.message}") }
        }

        val rate = String.format(Locale.US, "%.1f", metrics.actualSampleRateHz)
        _state.value = _state.value.copy(
            isRecording = false,
            isReady = true,
            status = "Saved ${session.id} · ${metrics.totalSamples} IMU · $rate Hz",
            sessionId = session.id,
        )
    }

    /**
     * Average effective FPS computed from the spread of frame timestamps.
     * Mirrors `RecordingOrchestrator.computeEffectiveFPS` on iOS — only
     * counts intervals < 100 ms so the metric is robust against
     * pause/resume gaps.
     */
    private fun computeAvgFps(videoTsNs: LongArray): Double {
        if (videoTsNs.size <= 1) return 0.0
        var sumMs = 0.0
        var n = 0
        for (i in 0 until videoTsNs.size - 1) {
            val deltaMs = (videoTsNs[i + 1] - videoTsNs[i]).toDouble() / 1_000_000.0
            if (deltaMs in 0.0..100.0) {
                sumMs += deltaMs
                n += 1
            }
        }
        return if (sumMs > 0) n.toDouble() / (sumMs / 1000.0) else 0.0
    }

    /**
     * Probe the recorded mp4 for its actual frame size via
     * `MediaMetadataRetriever`. Returns `(0, 0)` when the file isn't
     * decodable yet (e.g. the recorder failed mid-flight). Used to
     * populate intrinsics width/height + metadata.json resolution.
     */
    private fun probeVideoDimensions(videoFile: java.io.File): Pair<Int, Int> {
        if (!videoFile.exists() || videoFile.length() == 0L) return 0 to 0
        val mmr = android.media.MediaMetadataRetriever()
        return try {
            mmr.setDataSource(videoFile.absolutePath)
            val w = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            val h = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            // Some encoders emit pre-rotation dimensions and signal the
            // viewing rotation separately. CameraX writes the file already
            // oriented for landscape, so we keep whatever the muxer reports.
            w to h
        } catch (t: Throwable) {
            Log.w(TAG, "probeVideoDimensions failed: ${t.message}")
            0 to 0
        } finally {
            try { mmr.release() } catch (_: Throwable) {}
        }
    }

    /** Std-dev of inter-frame intervals in ms (capped at 100 ms intervals). */
    private fun computeFrameIntervalStdDevMs(videoTsNs: LongArray): Double {
        if (videoTsNs.size <= 1) return 0.0
        var sum = 0.0
        var sumSq = 0.0
        var n = 0
        for (i in 0 until videoTsNs.size - 1) {
            val deltaMs = (videoTsNs[i + 1] - videoTsNs[i]).toDouble() / 1_000_000.0
            if (deltaMs in 0.0..100.0) {
                sum += deltaMs
                sumSq += deltaMs * deltaMs
                n += 1
            }
        }
        if (n <= 1) return 0.0
        val mean = sum / n
        val variance = sumSq / n - mean * mean
        return if (variance > 0) kotlin.math.sqrt(variance) else 0.0
    }

    private fun collectorInfo(): SessionWriter.CollectorInfo {
        val settings = AppSettings.get(context).state.value
        val vendorId = try {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID).orEmpty()
        } catch (_: Throwable) { "" }
        return SessionWriter.CollectorInfo(
            campaign = CampaignConfig.CAMPAIGN,
            collectorId = vendorId,
            userName = settings.contributorName,
            userSlug = CampaignConfig.userSlug(settings, context),
            vendorId = vendorId,
            country = CampaignConfig.countryCode(settings),
        )
    }

    fun shutdown() {
        tickerJob?.cancel(); tickerJob = null
        activeRecording?.stop()
        activeRecording = null
        imuService?.stop()
        imuService = null
        timestampsService.stop()
        analysisExecutor.shutdown()
        scope.cancel()
    }

    companion object {
        private const val TAG = "SessionRecorder"
        /** Same setpoint as iOS `setExposureTargetBias(-0.25)`. */
        private const val EXPOSURE_BIAS_EV = -0.25
    }
}

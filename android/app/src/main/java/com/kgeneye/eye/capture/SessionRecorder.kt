package com.kgeneye.eye.capture

import android.content.Context
import android.util.Log
import androidx.camera.core.CameraSelector
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
import com.kgeneye.eye.session.SessionFiles
import com.kgeneye.eye.session.SessionManager
import com.kgeneye.eye.session.SessionWriter
import com.kgeneye.eye.session.TaxonomyWriter
import com.kgeneye.eye.settings.AppSettings
import com.kgeneye.eye.taxonomy.SessionTaxonomy
import com.kgeneye.eye.upload.UploadManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
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
        val imuSamples: Int = 0,
        val imuRateHz: Double = 0.0,
        val lastError: String? = null,
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private val analysisExecutor = Executors.newSingleThreadExecutor()

    private val sessionManager = SessionManager.get(context)
    private val uploadManager = UploadManager.get(context)

    private var videoCapture: VideoCapture<Recorder>? = null
    private var activeRecording: Recording? = null
    private var pendingTaxonomy: SessionTaxonomy? = null

    private var currentSession: SessionManager.Session? = null
    private var currentVideoFile: File? = null
    private var currentImuFile: File? = null
    private var currentTimestampsFile: File? = null

    private var imuService: ImuCaptureService? = null
    private val timestampsService = VideoTimestampsService()

    private var recordingStartEpochMs: Double = 0.0

    fun bindToLifecycle(
        lifecycleOwner: LifecycleOwner,
        previewView: PreviewView,
    ) {
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            try {
                val provider = providerFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }
                val recorder = Recorder.Builder()
                    .setQualitySelector(
                        QualitySelector.from(
                            Quality.FHD,
                            androidx.camera.video.FallbackStrategy.higherQualityOrLowerThan(Quality.HD)
                        )
                    ).build()
                val capture = VideoCapture.withOutput(recorder)
                videoCapture = capture

                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { ia ->
                        ia.setAnalyzer(analysisExecutor, ImageAnalysis.Analyzer { image: ImageProxy ->
                            try { timestampsService.record(image) } finally { image.close() }
                        })
                    }

                provider.unbindAll()
                provider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    capture,
                    analysis,
                )

                _state.value = _state.value.copy(isReady = true, status = "Ready — press to record.")
            } catch (t: Throwable) {
                Log.e(TAG, "Binding failed", t)
                _state.value = _state.value.copy(status = "Camera bind failed: ${t.message}", lastError = t.message)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun setPendingTaxonomy(taxonomy: SessionTaxonomy?) {
        pendingTaxonomy = taxonomy
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
            .withAudioEnabled()
            .start(ContextCompat.getMainExecutor(context)) { event ->
                when (event) {
                    is VideoRecordEvent.Start -> {
                        _state.value = _state.value.copy(
                            isRecording = true,
                            sessionId = session.id,
                            status = "Recording ${session.id}…",
                        )
                    }
                    is VideoRecordEvent.Status -> {
                        val samples = imuService?.totalSamples ?: 0
                        val rate = imuService?.actualSampleRateHz ?: 0.0
                        _state.value = _state.value.copy(
                            imuSamples = samples,
                            imuRateHz = rate,
                        )
                    }
                    is VideoRecordEvent.Finalize -> finalizeRecording(event)
                    else -> Unit
                }
            }
    }

    private fun finalizeRecording(event: VideoRecordEvent.Finalize) {
        val imu = imuService
        imu?.stop()
        imuService = null
        timestampsService.stop()
        activeRecording = null

        val session = currentSession ?: return
        val videoFile = currentVideoFile ?: return
        val imuFile = currentImuFile ?: return
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
            try { TaxonomyWriter.write(session.directory, taxonomy) }
            catch (t: Throwable) { Log.e(TAG, "taxonomy write failed", t) }
        }

        val metrics = imu?.metrics() ?: ImuCaptureService.Metrics(0, 0.0, 0, 0.0, 0.0, 0)
        val summary = SessionWriter.RecordingSummary(
            sessionId = session.id,
            startEpochMs = recordingStartEpochMs,
            endEpochMs = System.currentTimeMillis().toDouble(),
            video = SessionWriter.VideoInfo(
                filename = videoFile.name,
                sizeBytes = videoFile.length(),
                widthPx = null,
                heightPx = null,
                targetFps = 30,
                codec = "avc",
            ),
            imuFilename = imuFile.name,
            imuSizeBytes = imuFile.length(),
            imuRowCount = imu?.totalSamples ?: 0,
            imuMetrics = metrics,
        )
        try {
            SessionWriter.writeSessionManifest(session.directory, summary)
            SessionWriter.writeMetadata(session.directory, summary)
        } catch (t: Throwable) {
            Log.e(TAG, "sidecar write failed", t)
        }

        val settings = AppSettings.get(context).state.value
        if (settings.hasAwsCredentials) {
            uploadManager.startUpload(session.id, session.directory)
        }

        val rate = String.format("%.1f", metrics.actualSampleRateHz)
        _state.value = UiState(
            isRecording = false,
            isReady = true,
            status = "Saved ${session.id} · ${metrics.totalSamples} IMU · $rate Hz",
            sessionId = session.id,
        )
    }

    fun shutdown() {
        activeRecording?.stop()
        activeRecording = null
        imuService?.stop()
        imuService = null
        timestampsService.stop()
        analysisExecutor.shutdown()
    }

    companion object {
        private const val TAG = "SessionRecorder"
    }
}

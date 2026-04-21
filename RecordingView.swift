import SwiftUI
import AVFoundation

struct RecordingView: View {
    /// Optional taxonomy selection coming from the wizard. When present, it
    /// drives the chrome (top pill, sidebar card) and is persisted as
    /// `taxonomy.json` next to `metadata.json` by the orchestrator. The
    /// `taskCategoryLabelPt` also flows into `environment.taskDescription`
    /// of the session metadata.
    let taxonomy: SessionTaxonomy?

    @StateObject private var orchestrator = RecordingOrchestrator()
    @StateObject private var idlePreview = IdlePreviewSession()
    @Environment(\.dismiss) private var dismiss

    @State private var flashIconOn = false

    init(taxonomy: SessionTaxonomy? = nil) {
        self.taxonomy = taxonomy
    }

    // FOV diagnostic UI state — disabled by default. Re-enable together with
    // `fovDiagnosticCard` and `runFOVDiagnostic()` below when needed.
    // @State private var fovDiagnosticShareURL: URL?
    // @State private var fovDiagnosticError: String?

    /// Persisted capture preset choice. Keep the raw value in AppStorage so
    /// `VideoCaptureService.CapturePreset.current` sees the same value when
    /// the orchestrator starts the recording.
    @AppStorage(VideoCaptureService.CapturePreset.userDefaultsKey)
    private var capturePresetRaw: String = VideoCaptureService.CapturePreset.standard1080p.rawValue

    private var wideFovEnabled: Binding<Bool> {
        Binding(
            get: { capturePresetRaw == VideoCaptureService.CapturePreset.wideFov960p.rawValue },
            set: { enabled in
                capturePresetRaw = enabled
                    ? VideoCaptureService.CapturePreset.wideFov960p.rawValue
                    : VideoCaptureService.CapturePreset.standard1080p.rawValue
            }
        )
    }

    var body: some View {
        ZStack {
            if orchestrator.isRecording {
                Color.black.ignoresSafeArea()
                previewContent
                    .ignoresSafeArea()

                recordingChromeOverlay
            } else {
                AmbientImageBackdrop()
                idleLayout
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(orchestrator.isRecording)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .tint(KE.ink1)
        .onAppear {
            OrientationLock.shared.lock(.landscapeRight)
            orchestrator.activityTitle = taxonomy?.taskCategoryLabelPt
            orchestrator.taxonomySelection = taxonomy
            if !orchestrator.isRecording { idlePreview.start() }
        }
        .onDisappear {
            OrientationLock.shared.lock(.all)
            idlePreview.stop()
        }
        .onChange(of: orchestrator.isRecording) { _, recording in
            if recording {
                idlePreview.stop()
            } else {
                idlePreview.start()
            }
        }
    }

    // MARK: - Idle (pre-recording)

    private var idleLayout: some View {
        GlassPane(insets: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            HStack(spacing: 16) {
                previewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.95), .white.opacity(0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 8)

                VStack(spacing: 14) {
                    if let taxonomy = taxonomy {
                        EGOSidebarCard {
                            VStack(spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: taxonomy.scenarioBucket == "indoor" ? "house.fill" : "tree.fill")
                                        .font(.caption2)
                                        .foregroundStyle(KE.ink3)
                                    Text(taxonomy.locationLabelPt.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .tracking(0.5)
                                        .foregroundStyle(KE.ink3)
                                    Image(systemName: taxonomy.timeOfDay == "day" ? "sun.max.fill" : "moon.stars.fill")
                                        .font(.caption2)
                                        .foregroundStyle(KE.ink3)
                                }
                                Text(taxonomy.taskCategoryLabelPt)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(KE.ink1)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    EGOSidebarCard {
                        VStack(spacing: 6) {
                            statusIndicator
                            Text(orchestrator.statusMessage)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(KE.ink2)
                        }
                        .padding(.vertical, 4)
                    }

                    egoStatsGrid

                    wideFovToggleCard

                    // fovDiagnosticCard  // disabled — see definition below

                    Spacer()

                    if let error = orchestrator.lastError {
                        egoErrorView(error)
                    }

                    egoRecordButton
                }
                .frame(width: 320)
            }
            .padding(16)
        }
    }

    // MARK: - Recording (reference-style chrome)

    private var recordingChromeOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                EGOCaptureTopPill(title: "REC", showDot: true, dotColor: EGOTheme.recordInner)

                Spacer()

                if let taxonomy = taxonomy {
                    EGOCaptureTopPill(title: taxonomy.taskCategoryLabelPt.uppercased())
                        .layoutPriority(1)
                    Spacer()
                }

                EGOCaptureTopPill(title: formatDurationLong(orchestrator.recordingDurationSec))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()

            VStack(spacing: 12) {
                egoStatsGrid
                    .environment(\.colorScheme, .dark)

                if let error = orchestrator.lastError {
                    egoErrorViewRecording(error)
                }

                recordingBottomBar
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .background {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .overlay {
            ZStack {
                EGOViewfinderGrid(lineOpacity: 0.14)
                EGOFramingCorners(size: 132)
            }
            .allowsHitTesting(false)
        }
    }

    private var recordingBottomBar: some View {
        HStack(spacing: 20) {
            Button {
                flashIconOn.toggle()
            } label: {
                Image(systemName: flashIconOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 52, height: 52)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.12))
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                            }
                    }
            }
            .buttonStyle(.plain)

            Spacer()

            egoRecordButtonCore

            Spacer()

            Button {
                // Fixed egocentric rear camera — visual parity with reference only
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 52, height: 52)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.08))
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
                            }
                    }
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Shared components

    private var statusIndicator: some View {
        Circle()
            .fill(orchestrator.isRecording ? EGOTheme.recordInner : KE.ink3.opacity(0.4))
            .frame(width: 10, height: 10)
            .overlay {
                if orchestrator.isRecording {
                    Circle()
                        .fill(EGOTheme.recordInner.opacity(0.35))
                        .frame(width: 22, height: 22)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: orchestrator.isRecording)
                }
            }
    }

    private var previewContent: some View {
        Group {
            if let session = orchestrator.captureSession {
                CameraPreviewView(session: session)
            } else if idlePreview.isReady {
                CameraPreviewView(session: idlePreview.session)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.92, green: 0.93, blue: 0.95),
                            Color(red: 0.88, green: 0.90, blue: 0.94)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundStyle(KE.ink3.opacity(0.5))
                        Text(idlePreview.statusMessage)
                            .font(.caption)
                            .foregroundStyle(KE.ink3.opacity(0.55))
                    }
                }
            }
        }
    }

    private var egoStatsGrid: some View {
        HStack(spacing: 8) {
            EGOStatCard(title: "Duration", value: formatDuration(orchestrator.recordingDurationSec), icon: "clock")
            EGOStatCard(title: "Frames", value: "\(orchestrator.frameCount)", icon: "film")
            EGOStatCard(title: "IMU", value: "\(orchestrator.imuSampleCount)", icon: "gyroscope")
            EGOStatCard(title: "Session", value: orchestrator.currentSessionId ?? "—", icon: "number")
        }
    }

    private func egoErrorView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.85, green: 0.35, blue: 0.35))
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundStyle(Color(red: 0.75, green: 0.28, blue: 0.28))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.98, green: 0.88, blue: 0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.15), lineWidth: 0.5)
                )
        }
    }

    private func egoErrorViewRecording(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange.opacity(0.95))
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.orange.opacity(0.2))
        }
    }

    // MARK: - FOV diagnostic (disabled)
    //
    // Temporarily disabled after the FOV ceiling was empirically confirmed
    // (max diagonal FOV = 117.19° on the iPhone ultra-wide, below the 120°
    // target). Re-enable by uncommenting the `@State` vars above, the
    // `fovDiagnosticCard` reference in the sidebar, and the block below.
    // The `FOVEnumerationDiagnostic` enum is kept compiled for quick reuse.
    //
    // private var fovDiagnosticCard: some View {
    //     EGOSidebarCard {
    //         VStack(alignment: .leading, spacing: 8) {
    //             HStack(alignment: .firstTextBaseline, spacing: 8) {
    //                 VStack(alignment: .leading, spacing: 2) {
    //                     Text("Diagnóstico de FOV")
    //                         .font(.subheadline.weight(.semibold))
    //                         .foregroundStyle(KE.ink1)
    //                     Text("Enumera câmeras e formatos ≥30fps")
    //                         .font(.caption2)
    //                         .foregroundStyle(KE.ink2)
    //                 }
    //                 Spacer(minLength: 6)
    //             }
    //             HStack(spacing: 8) {
    //                 Button {
    //                     runFOVDiagnostic()
    //                 } label: {
    //                     Text("Rodar")
    //                         .font(.footnote.weight(.semibold))
    //                         .padding(.horizontal, 12)
    //                         .padding(.vertical, 6)
    //                         .background(
    //                             RoundedRectangle(cornerRadius: 8, style: .continuous)
    //                                 .fill(KE.ink1.opacity(0.08))
    //                         )
    //                 }
    //                 .buttonStyle(.plain)
    //                 .disabled(orchestrator.isRecording)
    //
    //                 if fovDiagnosticShareURL != nil {
    //                     Text("pronto para exportar")
    //                         .font(.caption2)
    //                         .foregroundStyle(KE.ink2)
    //                 } else if let err = fovDiagnosticError {
    //                     Text(err)
    //                         .font(.caption2)
    //                         .foregroundStyle(.red)
    //                         .lineLimit(2)
    //                 }
    //             }
    //         }
    //     }
    //     .opacity(orchestrator.isRecording ? 0.5 : 1.0)
    //     .sheet(isPresented: Binding(
    //         get: { fovDiagnosticShareURL != nil },
    //         set: { newValue in if !newValue { fovDiagnosticShareURL = nil } }
    //     )) {
    //         if let url = fovDiagnosticShareURL {
    //             ShareSheet(activityItems: [url])
    //         }
    //     }
    // }
    //
    // private func runFOVDiagnostic() {
    //     fovDiagnosticError = nil
    //     DispatchQueue.global(qos: .userInitiated).async {
    //         do {
    //             let url = try FOVEnumerationDiagnostic.runAndSave()
    //             DispatchQueue.main.async {
    //                 self.fovDiagnosticShareURL = url
    //             }
    //         } catch {
    //             DispatchQueue.main.async {
    //                 self.fovDiagnosticError = error.localizedDescription
    //             }
    //         }
    //     }
    // }

    private var wideFovToggleCard: some View {
        EGOSidebarCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extended vertical FOV")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KE.ink1)
                    Text(verbatim: wideFovEnabled.wrappedValue
                         ? "4:3 · 1280×960 · 4 Mbps"
                         : "16:9 · 1920×1080 · 6 Mbps")
                        .font(.caption2)
                        .foregroundStyle(KE.ink2)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Toggle("", isOn: wideFovEnabled)
                    .labelsHidden()
                    .tint(EGOTheme.recordInner)
                    .disabled(orchestrator.isRecording)
            }
        }
        .opacity(orchestrator.isRecording ? 0.5 : 1.0)
    }

    private var egoRecordButton: some View {
        Button {
            if orchestrator.isRecording {
                orchestrator.stopRecording()
            } else {
                // Hand off the camera: stop the idle-preview AVCaptureSession
                // before the orchestrator's VideoCaptureService tries to grab
                // the same device inside `video.setup()`.
                idlePreview.stop()
                orchestrator.startRecording()
            }
        } label: {
            KERecordPill(
                isRecording: orchestrator.isRecording,
                label: orchestrator.isRecording ? "Stop Recording" : "Start Recording"
            )
        }
        .buttonStyle(.plain)
    }

    private var egoRecordButtonCore: some View {
        Button {
            orchestrator.stopRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 76, height: 76)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.35), lineWidth: 1)
                    }
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [EGOTheme.recordPink.opacity(0.98), EGOTheme.blush.opacity(0.88)],
                            center: .center,
                            startRadius: 4,
                            endRadius: 36
                        )
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: EGOTheme.recordPink.opacity(0.5), radius: 10, y: 3)
                egoRecordButtonCoreLabel
            }
        }
        .buttonStyle(.plain)
    }

    private var egoRecordButtonCoreLabel: some View {
        ZStack {
            if orchestrator.isRecording {
                RoundedRectangle(cornerRadius: 5)
                    .fill(EGOTheme.recordInner)
                    .frame(width: 22, height: 22)
            } else {
                Circle()
                    .fill(EGOTheme.recordInner)
                    .frame(width: 24, height: 24)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func formatDurationLong(_ seconds: Double) -> String {
        let t = Int(seconds)
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Light sidebar glass

struct EGOSidebarCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassCard(cornerRadius: 18) {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
    }
}

struct EGOStatCard: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(KE.ink2.opacity(0.8))

            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(KE.ink1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(KE.ink3)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            Color(red: 240/255, green: 246/255, blue: 254/255).opacity(0.30)
        )
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Start / Stop record pill (Ambient Glass)
//
// Visual rhythm matches `KEPillButton` on the Home screen: r:22 continuous,
// thick glass dimmed to ~65%, tint wash, bevelled rim highlights. Variant is
// always red (action is "commit to recording / stop") — matching the live
// recording dot colour in `recordingChromeOverlay`.

struct KERecordPill: View {
    let isRecording: Bool
    let label: LocalizedStringKey

    private let tint = KE.accentRed

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 14) {
            indicator
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(KE.ink1)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 64)
        .modifier(KERecordPillSurface(tint: tint, shape: shape))
        .modifier(KERecordPillShadows(tint: tint))
        .contentShape(shape)
    }

    // 14×14 dot per SPECS.md §2 — circle idle, rounded square while recording.
    @ViewBuilder
    private var indicator: some View {
        ZStack {
            if isRecording {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.white)
                    .frame(width: 14, height: 14)
            } else {
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .animation(.easeInOut(duration: 0.25), value: isRecording)
    }
}

/// Glass surface for `KERecordPill`.
///
/// Because this pill lives inside a `GlassPane`, stacking a second Liquid
/// Glass layer on top of it would cause the outer pane to composite the
/// pill as part of its blur source — producing a milky, featureless
/// result. On iOS 26 the pill is therefore a translucent tint tile that
/// rides on top of the pane's native glass; older OSes keep the
/// sheen + rim recipe.
private struct KERecordPillSurface<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.22), location: 0.0),
                            .init(color: .white.opacity(0.0),  location: 0.55)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .background(tint.opacity(0.72))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
        } else {
            content
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.30), location: 0.0),
                            .init(color: .white.opacity(0.0),  location: 0.6)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .background(tint.opacity(0.55))
                .clipShape(shape)
                .overlay(shape.strokeBorder(tint.opacity(0.55), lineWidth: 1))
                .overlay(
                    shape.inset(by: 1)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                        .blendMode(.overlay)
                        .mask(
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .top, endPoint: .center
                            )
                        )
                )
                .overlay(
                    shape.inset(by: 1)
                        .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                        .blendMode(.overlay)
                        .mask(
                            LinearGradient(
                                colors: [.clear, .white],
                                startPoint: .center, endPoint: .bottom
                            )
                        )
                )
        }
    }
}

/// Drop shadows cause SwiftUI to snapshot a view as an opaque layer for
/// shadow rendering, which on iOS 26 breaks Liquid Glass refraction. Keep
/// them for the legacy look and skip them when native glass is active.
private struct KERecordPillShadows: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .shadow(color: tint.opacity(0.45), radius: 16, y: 4)
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        }
    }
}

// MARK: - Idle camera preview
//
// Owns a lightweight AVCaptureSession that feeds the idle layout's preview
// tile, so users see what the camera is pointed at before tapping
// "Start Recording". The session is torn down the moment recording actually
// begins — otherwise `VideoCaptureService.setup()` can't grab the same
// hardware device and configuration fails.

final class IdlePreviewSession: ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()

    @Published var isReady = false
    @Published var statusMessage: String = String(localized: "Preparing preview…")

    // Only read/written from `queue`, which serialises access.
    private var configured = false
    private let queue = DispatchQueue(label: "idle.preview.session", qos: .userInitiated)

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            bringUpSession()
        case .notDetermined:
            publish { $0.statusMessage = String(localized: "Requesting camera access…") }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.bringUpSession()
                } else {
                    self.publish { $0.statusMessage = String(localized: "Camera access denied") }
                }
            }
        case .denied, .restricted:
            publish { $0.statusMessage = String(localized: "Camera access denied") }
        @unknown default:
            publish { $0.statusMessage = String(localized: "Camera unavailable") }
        }
    }

    func stop() {
        let sess = session
        queue.async {
            if sess.isRunning { sess.stopRunning() }
        }
        publish { $0.isReady = false }
    }

    private func bringUpSession() {
        let sess = session
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                sess.beginConfiguration()
                sess.sessionPreset = .hd1280x720
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video)
                if let cam = device,
                   let input = try? AVCaptureDeviceInput(device: cam),
                   sess.canAddInput(input) {
                    sess.addInput(input)
                }
                sess.commitConfiguration()
                self.configured = true
            }
            if !sess.isRunning {
                sess.startRunning()
            }
            let running = sess.isRunning
            self.publish {
                $0.isReady = running
                if !running { $0.statusMessage = String(localized: "Preview unavailable") }
            }
        }
    }

    /// Hops back to MainActor to mutate `@Published` state safely from the
    /// capture-session serial queue.
    private func publish(_ mutate: @escaping @Sendable (IdlePreviewSession) -> Void) {
        if Thread.isMainThread {
            mutate(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                mutate(self)
            }
        }
    }
}

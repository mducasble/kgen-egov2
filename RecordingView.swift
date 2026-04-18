import SwiftUI

struct RecordingView: View {
    @StateObject private var orchestrator = RecordingOrchestrator()
    @Environment(\.dismiss) private var dismiss

    @State private var handsGuideSelected = true
    @State private var gazeGuideSelected = false
    @State private var flashIconOn = false

    var body: some View {
        ZStack {
            if orchestrator.isRecording {
                Color.black.ignoresSafeArea()
                previewContent
                    .ignoresSafeArea()

                recordingChromeOverlay
            } else {
                EGOBlobBackground()
                idleLayout
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(orchestrator.isRecording)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(EGOTheme.textPrimary)
        .onAppear {
            OrientationLock.shared.lock(.landscapeRight)
        }
        .onDisappear {
            OrientationLock.shared.lock(.all)
        }
    }

    // MARK: - Idle (pre-recording)

    private var idleLayout: some View {
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
                EGOSidebarCard {
                    VStack(spacing: 6) {
                        statusIndicator
                        Text(orchestrator.statusMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(EGOTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }

                egoStatsGrid

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

    // MARK: - Recording (reference-style chrome)

    private var recordingChromeOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                EGOCaptureTopPill(title: "REC", showDot: true, dotColor: EGOTheme.recordInner)

                Spacer()

                EGOCaptureTopPill(title: formatDurationLong(orchestrator.recordingDurationSec))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()

            modeTogglePills
                .padding(.bottom, 10)

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

    private var modeTogglePills: some View {
        HStack(spacing: 10) {
            modePill(title: "hands", selected: handsGuideSelected, activeColor: EGOTheme.mint) {
                handsGuideSelected = true
                gazeGuideSelected = false
            }
            modePill(title: "gaze", selected: gazeGuideSelected, activeColor: EGOTheme.sky) {
                gazeGuideSelected = true
                handsGuideSelected = false
            }
        }
    }

    private func modePill(title: String, selected: Bool, activeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? EGOTheme.textPrimary : .white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(selected ? activeColor.opacity(0.85) : .white.opacity(0.14))
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.25), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
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
            .fill(orchestrator.isRecording ? EGOTheme.recordInner : EGOTheme.textMuted.opacity(0.4))
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
                            .foregroundStyle(EGOTheme.textMuted.opacity(0.5))
                        Text("Preview starts with recording")
                            .font(.caption)
                            .foregroundStyle(EGOTheme.textMuted.opacity(0.55))
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

    private var egoRecordButton: some View {
        Button {
            if orchestrator.isRecording {
                orchestrator.stopRecording()
            } else {
                orchestrator.startRecording()
            }
        } label: {
            HStack(spacing: 14) {
                egoRecordButtonCoreLabel
                Text(orchestrator.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
            .frame(maxWidth: 300)
            .frame(height: 56)
            .padding(.horizontal, 8)
            .background {
                EGOGlassCapsuleBackground(
                    tint: .custom(EGOTheme.recordInner),
                    tintStrength: 1.0
                )
            }
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
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                EGOGlassBackground(cornerRadius: 18, tint: .neutral, tintStrength: 0.1)
            }
    }
}

struct EGOStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(EGOTheme.textSecondary.opacity(0.8))

            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(EGOTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(EGOTheme.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background {
            EGOGlassBackground(cornerRadius: 14, tint: .neutral, tintStrength: 0.05)
        }
    }
}

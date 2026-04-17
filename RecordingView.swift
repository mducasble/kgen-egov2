import SwiftUI

struct RecordingView: View {
    @StateObject private var orchestrator = RecordingOrchestrator()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if orchestrator.isRecording {
                previewContent
                    .ignoresSafeArea()
            }

            if orchestrator.isRecording {
                recordingOverlay
            } else {
                idleLayout
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(orchestrator.isRecording)
        .toolbarBackground(.hidden, for: .navigationBar)
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
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 14) {
                GlassCard {
                    VStack(spacing: 6) {
                        statusIndicator
                        Text(orchestrator.statusMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.vertical, 4)
                }

                glassStatsGrid

                Spacer()

                if let error = orchestrator.lastError {
                    glassErrorView(error)
                }

                glassRecordButton
            }
            .frame(width: 320)
        }
        .padding(16)
    }

    // MARK: - Recording Overlay

    private var recordingOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                GlassCard {
                    HStack(spacing: 10) {
                        statusIndicator
                        Text(orchestrator.statusMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                    }
                }
                .frame(width: 200)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()

            VStack(spacing: 10) {
                glassStatsGrid

                if let error = orchestrator.lastError {
                    glassErrorView(error)
                }

                glassRecordButton
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Components

    private var statusIndicator: some View {
        Circle()
            .fill(orchestrator.isRecording ? .red : .gray.opacity(0.5))
            .frame(width: 10, height: 10)
            .overlay {
                if orchestrator.isRecording {
                    Circle()
                        .fill(.red.opacity(0.3))
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
                            Color(red: 0.06, green: 0.06, blue: 0.12),
                            Color(red: 0.03, green: 0.03, blue: 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.25))
                        Text("Preview starts with recording")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
            }
        }
    }

    private var glassStatsGrid: some View {
        HStack(spacing: 8) {
            GlassStatCard(title: "Duration", value: formatDuration(orchestrator.recordingDurationSec), icon: "clock")
            GlassStatCard(title: "Frames", value: "\(orchestrator.frameCount)", icon: "film")
            GlassStatCard(title: "IMU", value: "\(orchestrator.imuSampleCount)", icon: "gyroscope")
            GlassStatCard(title: "Session", value: String(orchestrator.currentSessionId?.prefix(6) ?? "—"), icon: "number")
        }
    }

    private func glassErrorView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red.opacity(0.8))
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red.opacity(0.8))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.red.opacity(0.2), lineWidth: 0.5)
                )
        }
    }

    private var glassRecordButton: some View {
        Button {
            if orchestrator.isRecording {
                orchestrator.stopRecording()
            } else {
                orchestrator.startRecording()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if orchestrator.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 16, height: 16)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                    }
                }
                .frame(width: 20)

                Text(orchestrator.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: 300)
            .frame(height: 50)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: orchestrator.isRecording
                                ? [.red.opacity(0.9), .red.opacity(0.6)]
                                : [.red.opacity(0.85), .orange.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Glass Components

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    )
            }
    }
}

struct GlassStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))

            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}

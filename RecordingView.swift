import SwiftUI

struct RecordingView: View {
    @StateObject private var orchestrator = RecordingOrchestrator()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
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
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(orchestrator.isRecording)
        .onAppear {
            OrientationLock.shared.lock(.landscapeRight)
        }
        .onDisappear {
            OrientationLock.shared.lock(.all)
        }
    }

    private var idleLayout: some View {
        HStack(spacing: 12) {
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.gray.opacity(0.2), lineWidth: 1)
                )

            VStack(spacing: 10) {
                statusHeader

                statsGrid

                Spacer()

                if let error = orchestrator.lastError {
                    errorView(error)
                }

                recordButton
            }
            .frame(width: 340)
        }
        .padding(12)
    }

    private var recordingOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                statusHeader
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 8) {
                statsGrid
                if let error = orchestrator.lastError {
                    errorView(error)
                }
                recordButton
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(orchestrator.isRecording ? .red : .gray)
                .frame(width: 12, height: 12)
                .overlay {
                    if orchestrator.isRecording {
                        Circle()
                            .fill(.red.opacity(0.4))
                            .frame(width: 20, height: 20)
                            .scaleEffect(orchestrator.isRecording ? 1.5 : 1.0)
                            .animation(.easeInOut(duration: 1).repeatForever(), value: orchestrator.isRecording)
                    }
                }
            Text(orchestrator.statusMessage)
                .font(.headline)
                .lineLimit(1)
            Spacer()
        }
    }

    private var previewContent: some View {
        Group {
            if let preview = orchestrator.previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.black.opacity(0.15))
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("Camera preview will appear after recording starts")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 8) {
            StatCard(title: "Duration", value: formatDuration(orchestrator.recordingDurationSec))
            StatCard(title: "Frames", value: "\(orchestrator.frameCount)")
            StatCard(title: "IMU", value: "\(orchestrator.imuSampleCount)")
            StatCard(title: "Session", value: String(orchestrator.currentSessionId?.prefix(8) ?? "—"))
        }
    }

    private func errorView(_ error: String) -> some View {
        Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recordButton: some View {
        Button {
            if orchestrator.isRecording {
                orchestrator.stopRecording()
            } else {
                orchestrator.startRecording()
            }
        } label: {
            HStack(spacing: 10) {
                if orchestrator.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 18, height: 18)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                }
                Text(orchestrator.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: 320)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.red)
            )
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

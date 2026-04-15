import SwiftUI

struct RecordingView: View {
    @StateObject private var orchestrator = RecordingOrchestrator()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Status header
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
                Spacer()
            }
            .padding(.horizontal)
            
            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(title: "Duration", value: formatDuration(orchestrator.recordingDurationSec))
                StatCard(title: "Frames", value: "\(orchestrator.frameCount)")
                StatCard(title: "IMU Samples", value: "\(orchestrator.imuSampleCount)")
                StatCard(title: "Session", value: String(orchestrator.currentSessionId?.prefix(8) ?? "—"))
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Error display
            if let error = orchestrator.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
            }
            
            // Record button
            Button {
                if orchestrator.isRecording {
                    orchestrator.stopRecording()
                } else {
                    orchestrator.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.red)
                    
                    if orchestrator.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 64, height: 64)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(orchestrator.isRecording)
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
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

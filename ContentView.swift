import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "video.badge.waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text("EgoCapture")
                        .font(.largeTitle.bold())
                    Text("Egocentric Data Collection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 14) {
                    NavigationLink {
                        RecordingView()
                    } label: {
                        Label("Start Recording", systemImage: "record.circle")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.red, in: RoundedRectangle(cornerRadius: 16))
                    }
                    
                    NavigationLink {
                        SessionListView()
                    } label: {
                        Label("View Sessions", systemImage: "folder")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                    }
                    
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text("Mount camera at forehead/eye level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Angle downward to maximize hand visibility")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

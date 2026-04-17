import SwiftUI

struct ContentView: View {
    @State private var animateGradient = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    Spacer()

                    heroSection
                        .padding(.bottom, 48)

                    VStack(spacing: 14) {
                        NavigationLink {
                            RecordingView()
                        } label: {
                            GlassButton(
                                icon: "record.circle",
                                title: "Start Recording",
                                accent: .red,
                                isPrimary: true
                            )
                        }

                        NavigationLink {
                            SessionListView()
                        } label: {
                            GlassButton(
                                icon: "folder.fill",
                                title: "View Sessions",
                                accent: .blue
                            )
                        }

                        NavigationLink {
                            SettingsView()
                        } label: {
                            GlassButton(
                                icon: "gearshape.fill",
                                title: "Settings",
                                accent: .gray
                            )
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Text("Mount camera at forehead level · Angle downward for hand visibility")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.08, green: 0.06, blue: 0.18),
                Color(red: 0.04, green: 0.04, blue: 0.10)
            ],
            startPoint: animateGradient ? .topLeading : .top,
            endPoint: animateGradient ? .bottomTrailing : .bottom
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 100, height: 100)
                    .blur(radius: 10)

                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red.opacity(0.9), .orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("EgoCapture")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Egocentric Data Collection")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

struct GlassButton: View {
    let icon: String
    let title: String
    let accent: Color
    var isPrimary: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isPrimary ? .white : accent)
                .frame(width: 28)

            Text(title)
                .font(.headline)
                .foregroundStyle(isPrimary ? .white : .white.opacity(0.85))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.8), accent.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            }
        }
    }
}

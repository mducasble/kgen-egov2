import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                EGOBlobBackground()

                VStack(spacing: 0) {
                    Spacer()

                    egoHeroSection
                        .padding(.bottom, 40)

                    VStack(spacing: 16) {
                        NavigationLink {
                            RecordingView()
                        } label: {
                            GlassCTAButton(
                                icon: "record.circle",
                                title: "Start Recording",
                                tint: .green
                            )
                        }

                        NavigationLink {
                            SessionListView()
                        } label: {
                            GlassCTAButton(
                                icon: "folder.fill",
                                title: "View Sessions",
                                tint: .blue
                            )
                        }

                        NavigationLink {
                            SettingsView()
                        } label: {
                            GlassCTAButton(
                                icon: "gearshape.fill",
                                title: "Settings",
                                tint: .neutral
                            )
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Text("EGOCENTRIC VIDEOS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EGOTheme.textMuted)
                        .tracking(3.2)

                    Text("Mount camera at forehead level · Angle downward for hand visibility")
                        .font(.caption)
                        .foregroundStyle(EGOTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(EGOTheme.textPrimary)
        .preferredColorScheme(.dark)
    }

    private var egoHeroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Back panels (layered glass chips, like the reference)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    }
                    .frame(width: 120, height: 82)
                    .offset(x: 28, y: -6)
                    .rotationEffect(.degrees(4))
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 10)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
                    .frame(width: 118, height: 80)
                    .offset(x: -12, y: 8)
                    .rotationEffect(.degrees(-6))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)

                // Front brand chip
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(EGOTheme.brandGreen.opacity(0.95))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.9), EGOTheme.brandGreen.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .trim(from: 0, to: 0.5)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                            .blendMode(.plusLighter)
                    }
                    .frame(width: 104, height: 76)
                    .shadow(color: EGOTheme.brandGreen.opacity(0.45), radius: 18, y: 10)
                    .overlay {
                        HStack(spacing: 4) {
                            Text("EGO")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.85))
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.8))
                        }
                    }
            }
            .frame(height: 120)

            Text("EgoCapture")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(EGOTheme.textPrimary)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

            Text("Egocentric Data Collection")
                .font(.subheadline)
                .foregroundStyle(EGOTheme.textSecondary)
        }
    }
}

struct GlassCTAButton: View {
    let icon: String
    let title: String
    let tint: EGOGlassTint

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 28)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.98))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(height: 58)
        .padding(.horizontal, 18)
        .background {
            EGOGlassCapsuleBackground(tint: tint, tintStrength: tint.isNeutral ? 0.25 : 0.95)
        }
    }
}

/// Kept for older call sites; re-routes to the new glass CTA look.
struct GlassButton: View {
    let icon: String
    let title: String
    let accent: Color
    var isPrimary: Bool = false

    var body: some View {
        GlassCTAButton(
            icon: icon,
            title: title,
            tint: .custom(accent)
        )
    }
}

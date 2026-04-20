import SwiftUI

// MARK: - Activities list

/// Shown between the Home screen and the Briefing screen.
///
/// Layout follows the handoff (`ACTIVITIES.md`):
/// - Ambient backdrop + inset `GlassPane` (same pattern as Home).
/// - Header with custom back pill on the left and "Activities" title centered.
/// - Scrollable list of glass activity pills.
struct ActivitiesView: View {
    private let activities: [Activity] = Activity.catalog

    var body: some View {
        ZStack {
            AmbientImageBackdrop()

            AmbientImageBackdrop()
                .blur(radius: 12)
                .mask(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .padding(EdgeInsets(top: 24, leading: 22, bottom: 28, trailing: 22))
                )
                .allowsHitTesting(false)

            GlassPane {
                VStack(spacing: 0) {
                    ActivitiesHeader()
                        .padding(.top, 4)

                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(activities) { activity in
                                if activity.available {
                                    NavigationLink {
                                        ActivityBriefingView(activity: activity)
                                    } label: {
                                        ActivityPill(activity: activity)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    ActivityPill(activity: activity)
                                }
                            }
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
    }
}

// MARK: - Header

private struct ActivitiesHeader: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text("Activities")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KE.ink1)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KE.ink1)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2)
                        )
                        .shadow(color: Color(red: 30/255, green: 40/255, blue: 55/255).opacity(0.12),
                                radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.top, 20)
    }
}

// MARK: - Activity pill

private struct ActivityPill: View {
    let activity: Activity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KE.ink1)
                    .multilineTextAlignment(.leading)

                Text(activity.desc)
                    .font(.system(size: 13))
                    .foregroundStyle(KE.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                StatusBadge(available: activity.available)
                Text(activity.available ? String(format: "%.1fh recorded", activity.hours) : "—")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(KE.ink1.opacity(0.82))
            }
            .frame(minWidth: 96)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(white: 0.98).opacity(0.42),
                    Color(white: 0.90).opacity(0.24)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
        )
        .shadow(
            color: Color(red: 30/255, green: 40/255, blue: 55/255).opacity(0.14),
            radius: 10, x: 0, y: 4
        )
        .opacity(activity.available ? 1 : 0.78)
        .allowsHitTesting(activity.available)
    }
}

// MARK: - Status badge

private struct StatusBadge: View {
    let available: Bool

    private var tint: Color { available ? KE.accentGreen : KE.accentRed }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.6), radius: 3)

            Text(available ? "Available" : "Unavailable")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(KE.ink1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.40), tint.opacity(0.22)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.55), lineWidth: 1))
        .shadow(color: tint.opacity(0.6), radius: 6)
    }
}

#Preview {
    NavigationStack {
        ActivitiesView()
    }
}

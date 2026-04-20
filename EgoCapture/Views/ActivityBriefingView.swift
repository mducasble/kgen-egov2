import SwiftUI

/// Intermediate screen between the Activities list and the Recording screen.
///
/// Intentionally kept minimal for now — shows the selected activity title and
/// a single "Gravar" button that opens `RecordingView` with the activity
/// pre-bound (its title flows into `environment.taskDescription` of the
/// session metadata). Descriptions/sample frames will land here later.
struct ActivityBriefingView: View {
    let activity: Activity

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
                    BriefingHeader(title: activity.title)
                        .padding(.top, 4)

                    Spacer()

                    NavigationLink {
                        RecordingView(activity: activity)
                    } label: {
                        KEPillButton(
                            label: "Gravar",
                            systemImage: "record.circle.fill",
                            variant: .red
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
    }
}

// MARK: - Header

private struct BriefingHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KE.ink1)
                .lineLimit(1)
                .padding(.horizontal, 56)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KE.ink1)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2)
                        )
                        .shadow(
                            color: Color(red: 30/255, green: 40/255, blue: 55/255).opacity(0.12),
                            radius: 8, x: 0, y: 4
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.top, 20)
    }
}

#Preview {
    NavigationStack {
        ActivityBriefingView(activity: Activity.catalog.first!)
    }
}

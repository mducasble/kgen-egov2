import SwiftUI

/// Intermediate screen between the taxonomy wizard and the Recording
/// screen.
///
/// Shows a quick recap of the wizard selection (cenário, location, task,
/// dia/noite auto-detectado) and a single "Gravar" button that hands the
/// `SessionTaxonomy` off to `RecordingView`. The orchestrator persists
/// the same struct as `taxonomy.json` next to `metadata.json` at the end
/// of the recording.
struct ActivityBriefingView: View {
    let selection: SessionTaxonomy

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
                    BriefingHeader(title: selection.taskCategoryLabelPt)
                        .padding(.top, 4)

                    Spacer(minLength: 12)

                    BriefingSummary(selection: selection)
                        .padding(.horizontal, 16)

                    Spacer()

                    NavigationLink {
                        RecordingView(taxonomy: selection)
                    } label: {
                        KEPillButton(
                            label: "Record",
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

// MARK: - Summary

private struct BriefingSummary: View {
    let selection: SessionTaxonomy

    var body: some View {
        let hr = selection.recordingHour
        let periodValue: String = selection.timeOfDay == "day"
            ? String(localized: "Day (\(hr) h)")
            : String(localized: "Night (\(hr) h)")
        let scenarioValue: String = selection.scenarioBucket == "indoor"
            ? String(localized: "Indoor")
            : String(localized: "Outdoor")
        return VStack(spacing: 10) {
            row(icon: selection.scenarioBucket == "indoor" ? "house.fill" : "tree.fill",
                title: "Scenario",
                value: scenarioValue)
            row(icon: "mappin.and.ellipse",
                title: "Location",
                value: selection.locationLabelPt)
            row(icon: "tag.fill",
                title: "Activity",
                value: selection.taskCategoryLabelPt)
            row(icon: selection.timeOfDay == "day" ? "sun.max.fill" : "moon.stars.fill",
                title: "Period",
                value: periodValue)
        }
    }

    private func row(icon: String, title: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KE.ink2)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KE.ink3)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KE.ink1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        ActivityBriefingView(selection: SessionTaxonomy(
            schemaVersion: "1.0.0",
            viewpointCode: "egocentric",
            scenarioCode: "indoor",
            scenarioBucket: "indoor",
            domainCode: "residential",
            locationCode: "kitchen",
            locationLabelPt: "Cozinha",
            locationLabelEn: "Kitchen",
            taskCategoryCode: "dishwashing",
            taskCategoryGroup: "housekeeping",
            taskCategoryLabelPt: "Lavagem de Louça",
            taskCategoryLabelEn: "Dishwashing",
            timeOfDay: "day",
            recordingHour: 14
        ))
    }
}

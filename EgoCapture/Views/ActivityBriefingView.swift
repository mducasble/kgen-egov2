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

    /// Contributor name (same `@AppStorage` key the Settings screen writes
    /// to). We gate the Record button on this being non-empty so every
    /// session we upload is properly attributed.
    @AppStorage(CampaignConfig.userNameStorageKey) private var userName = ""

    /// Drives the modal alert that collects the missing full name when the
    /// contributor tries to record without having filled Settings yet.
    @State private var showingNamePrompt = false

    /// Scratch buffer for the alert's `TextField`. Copied into ``userName``
    /// only once the contributor taps Continue with a non-empty value.
    @State private var pendingName = ""

    /// Programmatic navigation flag: flipped to `true` after we've
    /// confirmed a name is present (either already in storage or just
    /// captured via the alert). Using a flag keeps the "collect name →
    /// push" sequence in one place instead of duplicating NavigationLinks.
    @State private var navigateToRecording = false

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
                    BriefingHeader(title: selection.taskCategoryLabelLocalized)
                        .padding(.top, 4)

                    Spacer(minLength: 12)

                    BriefingSummary(selection: selection)
                        .padding(.horizontal, 16)

                    Spacer()

                    Button {
                        handleRecordTap()
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
        .alert("Your name", isPresented: $showingNamePrompt) {
            TextField("e.g. Marcos D", text: $pendingName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
            Button("Cancel", role: .cancel) {
                pendingName = ""
            }
            Button("Continue") {
                let trimmed = pendingName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                userName = trimmed
                pendingName = ""
                navigateToRecording = true
            }
        } message: {
            Text("Please enter your full name before recording. We use it to label the sessions you contribute.")
        }
        .navigationDestination(isPresented: $navigateToRecording) {
            RecordingView(taxonomy: selection)
        }
    }

    /// Checks whether we already have a contributor name stored. If yes,
    /// pushes straight to the recorder; otherwise opens the alert with an
    /// empty scratch buffer so the user is forced to fill it in.
    private func handleRecordTap() {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            pendingName = ""
            showingNamePrompt = true
        } else {
            navigateToRecording = true
        }
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
                value: selection.locationLabelLocalized)
            row(icon: "tag.fill",
                title: "Activity",
                value: selection.taskCategoryLabelLocalized)
            if !selection.selectedVerbsPt.isEmpty {
                row(icon: "hand.point.up.left.and.text.fill",
                    title: "Actions",
                    value: selection.selectedVerbsLocalizedLine)
            }
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
            selectedVerbsPt: ["enxaguar", "secar"],
            selectedVerbsEn: ["rinse", "dry"],
            selectedVerbsEs: ["enjuagar", "secar"],
            timeOfDay: "day",
            recordingHour: 14
        ))
    }
}

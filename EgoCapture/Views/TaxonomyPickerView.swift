import SwiftUI

// MARK: - Step 1: Indoor / Outdoor
//
// First wizard step exposed to the user. The "viewpoint" level (always
// egocentric) is intentionally hidden because the app can't produce any
// other vantage. The next step (location) is filtered by this choice.

struct ScenarioPickerView: View {
    private let taxonomy = TaxonomyLoader.shared

    var body: some View {
        WizardScaffold(title: String(localized: "Scenario"), step: 1, totalSteps: 4) {
            VStack(spacing: 12) {
                ForEach(Taxonomy.BinaryScenario.allCases) { bucket in
                    NavigationLink {
                        LocationPickerView(scenarioBucket: bucket)
                    } label: {
                        ScenarioCard(bucket: bucket)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 16)
        }
        .onAppear {
            // Warm up the taxonomy load.
            _ = taxonomy.scenarios.count
        }
    }
}

private struct ScenarioCard: View {
    let bucket: Taxonomy.BinaryScenario

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: bucket.iconName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(KE.ink1)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(Color.white.opacity(0.45))
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(bucket.localizedLabel)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KE.ink1)
                Text(bucket == .indoor
                     ? "Kitchen, living room, bedroom, bathroom, office, enclosed areas"
                     : "Backyard, garden, balcony, street, park, open transport")
                    .font(.system(size: 13))
                    .foregroundStyle(KE.ink2)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KE.ink3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(WizardCardSurface())
    }
}

// MARK: - Step 2: Location

struct LocationPickerView: View {
    let scenarioBucket: Taxonomy.BinaryScenario

    private var locations: [Taxonomy.Location] {
        TaxonomyLoader.shared.locations(matching: scenarioBucket)
    }

    var body: some View {
        WizardScaffold(title: scenarioBucket.localizedLabel, step: 2, totalSteps: 4) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(locations) { location in
                        NavigationLink {
                            TaskCategoryPickerView(
                                scenarioBucket: scenarioBucket,
                                location: location
                            )
                        } label: {
                            WizardRow(
                                title: location.localizedLabel,
                                subtitle: subtitle(for: location)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if locations.isEmpty {
                        EmptyStateLabel("No locations available for this scenario")
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func subtitle(for loc: Taxonomy.Location) -> String {
        let scenarioPt = TaxonomyLoader.shared.scenarioLabelPt(for: loc.scenario) ?? loc.scenario
        return "\(loc.domain.replacingOccurrences(of: "_", with: " ").capitalized) · \(scenarioPt)"
    }
}

// MARK: - Step 3: Task category

struct TaskCategoryPickerView: View {
    let scenarioBucket: Taxonomy.BinaryScenario
    let location: Taxonomy.Location

    /// Temporary product filter (all locales): whole groups hidden from step 3
    /// until we re-enable Alimentação, cuidado pessoal, cuidado com outros,
    /// deslocamento, social, produtivo e recreação.
    private static let hiddenTaskGroupCodes: Set<String> = [
        "food",
        "self_care",
        "caregiving",
        "mobility",
        "social",
        "productive",
        "recreation",
    ]

    private var grouped: [(group: String, items: [Taxonomy.TaskCategory])] {
        let all = TaxonomyLoader.shared.taskCategories
            .filter { !Self.hiddenTaskGroupCodes.contains($0.group) }
        let groups = Dictionary(grouping: all, by: { $0.group })
        let order = uniqueGroupOrder(all)
        return order.compactMap { key in
            guard let items = groups[key] else { return nil }
            return (group: key, items: items.sorted { $0.localizedLabel.localizedCaseInsensitiveCompare($1.localizedLabel) == .orderedAscending })
        }
    }

    var body: some View {
        WizardScaffold(title: String(localized: "Activity"), step: 3, totalSteps: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ContextHeader(
                        scenarioBucket: scenarioBucket,
                        location: location
                    )

                    ForEach(grouped, id: \.group) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(prettyGroup(entry.group))
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(KE.ink3)

                            VStack(spacing: 8) {
                                ForEach(entry.items) { task in
                                    NavigationLink {
                                        VerbPickerView(
                                            scenarioBucket: scenarioBucket,
                                            location: location,
                                            task: task,
                                            baseSelection: makeBaseSelection(for: task)
                                        )
                                    } label: {
                                        WizardRow(
                                            title: task.localizedLabel,
                                            subtitle: task.localizedDescription
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func makeBaseSelection(for task: Taxonomy.TaskCategory) -> SessionTaxonomy {
        let dayInfo = SessionTaxonomy.dayOrNight()
        return SessionTaxonomy(
            schemaVersion: TaxonomyLoader.shared.schemaVersion,
            viewpointCode: "egocentric",
            scenarioCode: location.scenario,
            scenarioBucket: scenarioBucket.rawValue,
            domainCode: location.domain,
            locationCode: location.code,
            locationLabelPt: location.labelPt,
            locationLabelEn: location.labelEn,
            taskCategoryCode: task.code,
            taskCategoryGroup: task.group,
            taskCategoryLabelPt: task.labelPt,
            taskCategoryLabelEn: task.labelEn,
            selectedVerbsPt: [],
            selectedVerbsEn: [],
            selectedVerbsEs: [],
            timeOfDay: dayInfo.label,
            recordingHour: dayInfo.hour
        )
    }

    private func uniqueGroupOrder(_ tasks: [Taxonomy.TaskCategory]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for t in tasks where !seen.contains(t.group) {
            seen.insert(t.group)
            order.append(t.group)
        }
        return order
    }

    private func prettyGroup(_ raw: String) -> String {
        // Map taxonomy group codes to catalog keys. Falls back to an
        // uppercased version of the raw code if the group isn't in the
        // catalog yet — keeps the UI readable when a new group lands in
        // taxonomy.json before the translators catch up.
        let key: String.LocalizationValue
        switch raw {
        case "housekeeping":  key = "group.housekeeping"
        case "food":          key = "group.food"
        case "self_care":     key = "group.self_care"
        case "caregiving":    key = "group.caregiving"
        case "outdoor_work":  key = "group.outdoor_work"
        case "handiwork":     key = "group.handiwork"
        case "errands":       key = "group.errands"
        case "mobility":      key = "group.mobility"
        case "social":        key = "group.social"
        case "productive":    key = "group.productive"
        case "recreation":    key = "group.recreation"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").uppercased()
        }
        return String(localized: key)
    }
}

// MARK: - Step 4: Verbs (multi-select)

private struct VerbPickerView: View {
    let scenarioBucket: Taxonomy.BinaryScenario
    let location: Taxonomy.Location
    let task: Taxonomy.TaskCategory
    let baseSelection: SessionTaxonomy

    @State private var selectedIndices: Set<Int> = []

    private var verbEntry: TaskVerbsBundle.Entry? {
        TaskVerbsLoader.verbs(for: task.code)
    }

    private var verbCount: Int {
        verbEntry.map { $0.verbsPt.count } ?? 0
    }

    var body: some View {
        WizardScaffold(title: String(localized: "Actions"), step: 4, totalSteps: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ContextHeaderWithTask(
                        scenarioBucket: scenarioBucket,
                        location: location,
                        taskTitle: task.localizedLabel
                    )

                    Text("Select the actions you will perform in this recording.")
                        .font(.system(size: 13))
                        .foregroundStyle(KE.ink2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let entry = verbEntry, !entry.verbsPt.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 148), spacing: 8, alignment: .leading)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(0 ..< entry.verbsPt.count, id: \.self) { i in
                                verbChip(index: i, entry: entry)
                            }
                        }
                    } else {
                        EmptyStateLabel("No verb list for this activity yet.")
                    }

                    NavigationLink {
                        ActivityBriefingView(selection: finalizedSelection())
                    } label: {
                        KEPillButton(
                            label: "Continue",
                            systemImage: "arrow.right.circle.fill",
                            variant: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.45)
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var canContinue: Bool {
        if verbEntry == nil || verbCount == 0 { return true }
        return !selectedIndices.isEmpty
    }

    private func verbChip(index: Int, entry: TaskVerbsBundle.Entry) -> some View {
        let on = selectedIndices.contains(index)
        let label = verbLabel(index: index, entry: entry)
        return Button {
            if on {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(KE.ink1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(on ? Color(red: 0.75, green: 0.9, blue: 0.35).opacity(0.45) : Color.white.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? Color(red: 0.45, green: 0.65, blue: 0.2) : Color.white.opacity(0.5), lineWidth: on ? 1.8 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func verbLabel(index: Int, entry: TaskVerbsBundle.Entry) -> String {
        let lang = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        let raw: String
        if lang.hasPrefix("pt") { raw = entry.verbsPt[index] }
        else if lang.hasPrefix("es") { raw = entry.verbsEs[index] }
        else { raw = entry.verbsEn[index] }
        return raw.verbDisplayCased
    }

    private func finalizedSelection() -> SessionTaxonomy {
        guard let entry = verbEntry, !selectedIndices.isEmpty else {
            return SessionTaxonomy(
                schemaVersion: baseSelection.schemaVersion,
                viewpointCode: baseSelection.viewpointCode,
                scenarioCode: baseSelection.scenarioCode,
                scenarioBucket: baseSelection.scenarioBucket,
                domainCode: baseSelection.domainCode,
                locationCode: baseSelection.locationCode,
                locationLabelPt: baseSelection.locationLabelPt,
                locationLabelEn: baseSelection.locationLabelEn,
                taskCategoryCode: baseSelection.taskCategoryCode,
                taskCategoryGroup: baseSelection.taskCategoryGroup,
                taskCategoryLabelPt: baseSelection.taskCategoryLabelPt,
                taskCategoryLabelEn: baseSelection.taskCategoryLabelEn,
                selectedVerbsPt: [],
                selectedVerbsEn: [],
                selectedVerbsEs: [],
                timeOfDay: baseSelection.timeOfDay,
                recordingHour: baseSelection.recordingHour
            )
        }
        let order = selectedIndices.sorted()
        let pt = order.map { entry.verbsPt[$0] }
        let en = order.map { entry.verbsEn[$0] }
        let es = order.map { entry.verbsEs[$0] }
        return SessionTaxonomy(
            schemaVersion: baseSelection.schemaVersion,
            viewpointCode: baseSelection.viewpointCode,
            scenarioCode: baseSelection.scenarioCode,
            scenarioBucket: baseSelection.scenarioBucket,
            domainCode: baseSelection.domainCode,
            locationCode: baseSelection.locationCode,
            locationLabelPt: baseSelection.locationLabelPt,
            locationLabelEn: baseSelection.locationLabelEn,
            taskCategoryCode: baseSelection.taskCategoryCode,
            taskCategoryGroup: baseSelection.taskCategoryGroup,
            taskCategoryLabelPt: baseSelection.taskCategoryLabelPt,
            taskCategoryLabelEn: baseSelection.taskCategoryLabelEn,
            selectedVerbsPt: pt,
            selectedVerbsEn: en,
            selectedVerbsEs: es,
            timeOfDay: baseSelection.timeOfDay,
            recordingHour: baseSelection.recordingHour
        )
    }
}

private struct ContextHeaderWithTask: View {
    let scenarioBucket: Taxonomy.BinaryScenario
    let location: Taxonomy.Location
    let taskTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: scenarioBucket.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KE.ink2)
                Text(verbatim: "\(scenarioBucket.localizedLabel) · \(location.localizedLabel)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KE.ink2)
                Spacer()
            }
            Text(taskTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KE.ink3)
                .padding(.leading, 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Shared wizard chrome

struct WizardScaffold<Content: View>: View {
    let title: String
    let step: Int
    let totalSteps: Int
    @ViewBuilder let content: Content

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
                    WizardHeader(title: title, step: step, totalSteps: totalSteps)
                        .padding(.top, 4)
                    content
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
    }
}

private struct WizardHeader: View {
    let title: String
    let step: Int
    let totalSteps: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KE.ink1)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                Text("Step \(step) of \(totalSteps)")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(KE.ink3)
            }

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

private struct WizardRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KE.ink1)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(KE.ink2)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KE.ink3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(WizardCardSurface())
    }
}

private struct WizardCardSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(white: 0.98).opacity(0.42),
                    Color(white: 0.90).opacity(0.24)
                ],
                startPoint: .top, endPoint: .bottom
            )
            Rectangle().fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2)
        )
        .shadow(
            color: Color(red: 30/255, green: 40/255, blue: 55/255).opacity(0.12),
            radius: 8, x: 0, y: 4
        )
    }
}

private struct ContextHeader: View {
    let scenarioBucket: Taxonomy.BinaryScenario
    let location: Taxonomy.Location

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: scenarioBucket.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KE.ink2)
            Text(verbatim: "\(scenarioBucket.localizedLabel) · \(location.localizedLabel)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KE.ink2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.white.opacity(0.32))
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
    }
}

private struct EmptyStateLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(KE.ink3)
            .padding(.vertical, 24)
    }
}

#Preview("Scenario") {
    NavigationStack { ScenarioPickerView() }
}

import SwiftUI

struct SettingsView: View {
    @AppStorage("mount_type") private var mountType = "forehead"
    @AppStorage("mount_tx") private var translationX = 0.0
    @AppStorage("mount_ty") private var translationY = 0.03
    @AppStorage("mount_tz") private var translationZ = 0.08
    @AppStorage("mount_tilt") private var downwardTiltDeg = 30.0

    @AppStorage("environment_type") private var environmentType = "residential"
    @AppStorage("environment_sub") private var environmentSubCategory = "room_tidy_up"
    /// Defaults to the device's current region (e.g. `"BR"`, `"US"`, `"ES"`)
    /// so new installs arrive pre-filled. Once the user edits the field the
    /// stored value wins and the default is ignored by ``AppStorage``.
    @AppStorage("country") private var country: String = Locale.current.region?.identifier ?? "US"
    @AppStorage("task_description") private var taskDescription = ""
    @AppStorage("selected_hand_tracking_backend") private var handTrackingBackend = HandTrackingBackendType.appleVision.rawValue
    @AppStorage("mediapipe_model_path") private var mediaPipeModelPath = "hand_landmarker.task"

    @AppStorage(CampaignConfig.userNameStorageKey) private var userName = ""

    @State private var taxonomyBackfillMessage: String?
    @State private var showTaxonomyBackfillAlert = false

    var body: some View {
        ZStack {
            AmbientImageBackdrop()

            ScrollView {
                VStack(spacing: 16) {
                    contributorSection
                    awsSection
                    mountSection
                    environmentSection
                    taskSection
                    trackingSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Settings")
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .alert("Taxonomy upload", isPresented: $showTaxonomyBackfillAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(taxonomyBackfillMessage ?? "")
        })
    }

    // MARK: - Sections

    private var contributorSection: some View {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = CampaignConfig.slugify(trimmed)
        let effectiveSlug = slug.isEmpty ? CampaignConfig.userSlug : slug
        let previewPrefix = "\(CampaignConfig.countryCode)/\(effectiveSlug)"

        return GlassSection(title: "CONTRIBUTOR", icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your name")
                        .font(.caption)
                        .foregroundStyle(KE.ink3)

                    TextField("e.g. Marcos D", text: $userName)
                        .font(.subheadline)
                        .foregroundStyle(KE.ink1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.40))
                        }
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("S3 PATH PREFIX")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(KE.ink3)
                        .tracking(0.8)
                    Text("\(CampaignConfig.campaign)/\(previewPrefix)/<session-id>/…")
                        .font(.caption.monospaced())
                        .foregroundStyle(KE.ink1)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.30))
                }

                Text("Your name groups every session you record under the same S3 folder. Leaving it blank uses an anonymous per-device token.")
                    .font(.caption2)
                    .foregroundStyle(KE.ink3.opacity(0.9))
            }
        }
    }

    private var awsSection: some View {
        let cfg = S3Config.embedded()
        return GlassSection(title: "S3 UPLOAD", icon: "icloud.and.arrow.up") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bucket")
                        .font(.subheadline)
                        .foregroundStyle(KE.ink2)
                    Spacer()
                    Text(cfg.bucket)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(KE.ink3)
                }
                HStack {
                    Text("Region")
                        .font(.subheadline)
                        .foregroundStyle(KE.ink2)
                    Spacer()
                    Text(cfg.region)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(KE.ink3)
                }

                HStack(spacing: 6) {
                    Image(systemName: cfg.isValid ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(cfg.isValid ? KE.accentGreen : Color.orange)
                        .font(.caption)
                    Text(cfg.isValid ? "Credentials embedded in app build" : "Set keys in EmbeddedAWSCredentials.swift before build")
                        .font(.caption2)
                        .foregroundStyle(KE.ink3)
                }

                Text("Sessions upload automatically after recording (≤2 min video chunks). Keys are not shown to contributors.")
                    .font(.caption2)
                    .foregroundStyle(KE.ink3.opacity(0.85))

                if cfg.isValid {
                    Button {
                        let n = UploadManager.shared.backfillTaxonomyArtifacts()
                        if n == 0 {
                            taxonomyBackfillMessage = "No sessions needed a taxonomy upload (file missing locally, already queued, or already uploaded)."
                        } else {
                            taxonomyBackfillMessage = "Started taxonomy upload for \(n) session(s). Sessions that already uploaded taxonomy are skipped."
                        }
                        showTaxonomyBackfillAlert = true
                    } label: {
                        Label("Upload saved taxonomy JSON now", systemImage: "arrow.triangle.branch")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)

                    Text("Use this if older builds did not upload taxonomy JSON. Sessions that already uploaded that file are skipped.")
                        .font(.caption2)
                        .foregroundStyle(KE.ink3.opacity(0.85))
                }
            }
        }
    }

    private var mountSection: some View {
        GlassSection(title: "CAMERA MOUNT", icon: "camera.on.rectangle") {
            VStack(spacing: 14) {
                glassPickerRow(title: "Mount Type", selection: $mountType, options: [
                    ("Forehead", "forehead"),
                    ("Temple", "temple"),
                    ("Hat Brim", "hat_brim"),
                    ("Headband", "headband")
                ])

                VStack(alignment: .leading, spacing: 8) {
                    Text("Translation from head center (m)")
                        .font(.caption)
                        .foregroundStyle(KE.ink3)

                    HStack(spacing: 10) {
                        GlassTextField(label: "X (right)", value: $translationX)
                        GlassTextField(label: "Y (up)", value: $translationY)
                        GlassTextField(label: "Z (fwd)", value: $translationZ)
                    }
                }

                HStack {
                    Text("Downward tilt")
                        .font(.subheadline)
                        .foregroundStyle(KE.ink2)
                    Spacer()
                    GlassTextField(label: "°", value: $downwardTiltDeg)
                        .frame(width: 90)
                }

                Text("Adjust values to match your physical camera mount position.")
                    .font(.caption2)
                    .foregroundStyle(KE.ink3.opacity(0.9))
            }
        }
    }

    private var environmentSection: some View {
        GlassSection(title: "ENVIRONMENT", icon: "building.2") {
            VStack(spacing: 14) {
                glassPickerRow(title: "Type", selection: $environmentType, options: [
                    ("Residential", "residential"),
                    ("Commercial", "commercial")
                ])

                if environmentType == "residential" {
                    glassPickerRow(title: "Category", selection: $environmentSubCategory, options: [
                        ("Room Tidy-Up", "room_tidy_up"),
                        ("Dishes Cleanup", "dishes_cleanup"),
                        ("Laundry", "laundry"),
                        ("Other Home Tasks", "other_home")
                    ])
                } else {
                    glassPickerRow(title: "Category", selection: $environmentSubCategory, options: [
                        ("Warehouse / Logistics", "warehouse_logistics"),
                        ("Retail Operations", "retail"),
                        ("Food Service", "food_service"),
                        ("Cleaning / Janitorial", "cleaning"),
                        ("Manufacturing", "manufacturing"),
                        ("Construction / Trades", "construction"),
                        ("Hospitality", "hospitality"),
                        ("Automotive / Equipment", "automotive"),
                        ("Agriculture", "agriculture"),
                        ("Field Services", "field_services"),
                        ("Food Retail", "food_retail")
                    ])
                }

                HStack {
                    Text("Country")
                        .font(.subheadline)
                        .foregroundStyle(KE.ink2)
                    Spacer()
                    TextField("", text: $country)
                        .font(.subheadline)
                        .foregroundStyle(KE.ink1)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
        }
    }

    private var taskSection: some View {
        GlassSection(title: "TASK", icon: "list.clipboard") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Task description (optional)", text: $taskDescription)
                    .font(.subheadline)
                    .foregroundStyle(KE.ink1)
                    .lineLimit(3)

                Text("e.g., \"dishes cleanup\" or \"warehouse stocking\"")
                    .font(.caption2)
                    .foregroundStyle(KE.ink3.opacity(0.9))
            }
        }
    }

    private var trackingSection: some View {
        GlassSection(title: "HAND TRACKING", icon: "hand.raised") {
            VStack(spacing: 14) {
                glassPickerRow(title: "Backend", selection: $handTrackingBackend, options: [
                    ("Apple Vision", HandTrackingBackendType.appleVision.rawValue),
                    ("MediaPipe", HandTrackingBackendType.mediaPipe.rawValue),
                    ("Both (parallel)", HandTrackingBackendType.both.rawValue)
                ])

                Text("MediaPipe outputs are saved as *_mediapipe.jsonl when enabled.")
                    .font(.caption2)
                    .foregroundStyle(KE.ink3.opacity(0.9))

                if handTrackingBackend != HandTrackingBackendType.appleVision.rawValue {
                    HStack {
                        Text("Model path")
                            .font(.subheadline)
                            .foregroundStyle(KE.ink2)
                        Spacer()
                        TextField("", text: $mediaPipeModelPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(KE.ink3)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func glassPickerRow(title: LocalizedStringKey, selection: Binding<String>, options: [(LocalizedStringKey, String)]) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(KE.ink2)

            Spacer()

            Menu {
                ForEach(options, id: \.1) { option in
                    Button {
                        selection.wrappedValue = option.1
                    } label: {
                        if selection.wrappedValue == option.1 {
                            Label(option.0, systemImage: "checkmark")
                        } else {
                            Text(option.0)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Group {
                        if let match = options.first(where: { $0.1 == selection.wrappedValue }) {
                            Text(match.0)
                        } else {
                            Text(verbatim: selection.wrappedValue)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(KE.ink1.opacity(0.75))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(KE.ink3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.40))
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                        )
                }
            }
        }
    }

    func buildMountService() -> MountCalibrationService {
        let service = MountCalibrationService()
        service.updateConfig(
            mountType: mountType,
            translationX: translationX,
            translationY: translationY,
            translationZ: translationZ,
            downwardTiltDeg: downwardTiltDeg,
            notes: "Configured via Settings UI"
        )
        return service
    }
}

// MARK: - Glass Components

struct GlassSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(KE.ink3)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KE.ink3)
                    .tracking(0.8)
            }
            .padding(.leading, 4)

            GlassCard(cornerRadius: 18) {
                content
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct GlassTextField: View {
    let label: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(KE.ink3)
                .textCase(.uppercase)

            TextField("", value: $value, format: .number)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(KE.ink1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.40))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        )
                }
        }
    }
}

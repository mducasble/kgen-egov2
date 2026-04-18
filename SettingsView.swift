import SwiftUI

struct SettingsView: View {
    @AppStorage("mount_type") private var mountType = "forehead"
    @AppStorage("mount_tx") private var translationX = 0.0
    @AppStorage("mount_ty") private var translationY = 0.03
    @AppStorage("mount_tz") private var translationZ = 0.08
    @AppStorage("mount_tilt") private var downwardTiltDeg = 30.0

    @AppStorage("environment_type") private var environmentType = "residential"
    @AppStorage("environment_sub") private var environmentSubCategory = "room_tidy_up"
    @AppStorage("country") private var country = "US"
    @AppStorage("task_description") private var taskDescription = ""
    @AppStorage("selected_hand_tracking_backend") private var handTrackingBackend = HandTrackingBackendType.appleVision.rawValue
    @AppStorage("mediapipe_model_path") private var mediaPipeModelPath = "hand_landmarker.task"

    @AppStorage(CampaignConfig.userNameStorageKey) private var userName = ""

    var body: some View {
        ZStack {
            EGOBlobBackground()

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
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var contributorSection: some View {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = CampaignConfig.slugify(trimmed)
        let effectiveSlug = slug.isEmpty ? CampaignConfig.userSlug : slug
        let previewPrefix = "\(CampaignConfig.campaign)/\(effectiveSlug)"

        return GlassSection(title: "CONTRIBUTOR", icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your name")
                        .font(.caption)
                        .foregroundStyle(EGOTheme.textMuted)

                    TextField("e.g. Marcos D", text: $userName)
                        .font(.subheadline)
                        .foregroundStyle(EGOTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(EGOTheme.textMuted.opacity(0.08))
                        }
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                }

                HStack {
                    Text("Campaign")
                        .font(.subheadline)
                        .foregroundStyle(EGOTheme.textSecondary)
                    Spacer()
                    Text(CampaignConfig.campaign)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(EGOTheme.textMuted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("S3 PATH PREFIX")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EGOTheme.textMuted)
                        .tracking(0.8)
                    Text("\(previewPrefix)/<session-id>/…")
                        .font(.caption.monospaced())
                        .foregroundStyle(EGOTheme.textPrimary.opacity(0.85))
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(EGOTheme.textMuted.opacity(0.06))
                }

                Text("Your name groups every session you record under the same S3 folder. Leaving it blank uses an anonymous per-device token.")
                    .font(.caption2)
                    .foregroundStyle(EGOTheme.textMuted.opacity(0.9))
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
                        .foregroundStyle(EGOTheme.textSecondary)
                    Spacer()
                    Text(cfg.bucket)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(EGOTheme.textMuted)
                }
                HStack {
                    Text("Region")
                        .font(.subheadline)
                        .foregroundStyle(EGOTheme.textSecondary)
                    Spacer()
                    Text(cfg.region)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(EGOTheme.textMuted)
                }

                HStack(spacing: 6) {
                    Image(systemName: cfg.isValid ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(cfg.isValid ? EGOTheme.mint : Color.orange.opacity(0.85))
                        .font(.caption)
                    Text(cfg.isValid ? "Credentials embedded in app build" : "Set keys in EmbeddedAWSCredentials.swift before build")
                        .font(.caption2)
                        .foregroundStyle(EGOTheme.textMuted)
                }

                Text("Sessions upload automatically after recording (≤2 min video chunks). Keys are not shown to contributors.")
                    .font(.caption2)
                    .foregroundStyle(EGOTheme.textMuted.opacity(0.85))
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
                        .foregroundStyle(EGOTheme.textMuted)

                    HStack(spacing: 10) {
                        GlassTextField(label: "X (right)", value: $translationX)
                        GlassTextField(label: "Y (up)", value: $translationY)
                        GlassTextField(label: "Z (fwd)", value: $translationZ)
                    }
                }

                HStack {
                    Text("Downward tilt")
                        .font(.subheadline)
                        .foregroundStyle(EGOTheme.textSecondary)
                    Spacer()
                    GlassTextField(label: "°", value: $downwardTiltDeg)
                        .frame(width: 90)
                }

                Text("Adjust values to match your physical camera mount position.")
                    .font(.caption2)
                    .foregroundStyle(EGOTheme.textMuted.opacity(0.9))
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
                        .foregroundStyle(EGOTheme.textSecondary)
                    Spacer()
                    TextField("", text: $country)
                        .font(.subheadline)
                        .foregroundStyle(EGOTheme.textPrimary)
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
                    .foregroundStyle(EGOTheme.textPrimary)
                    .lineLimit(3)

                Text("e.g., \"dishes cleanup\" or \"warehouse stocking\"")
                    .font(.caption2)
                    .foregroundStyle(EGOTheme.textMuted.opacity(0.9))
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
                    .foregroundStyle(EGOTheme.textMuted.opacity(0.9))

                if handTrackingBackend != HandTrackingBackendType.appleVision.rawValue {
                    HStack {
                        Text("Model path")
                            .font(.subheadline)
                            .foregroundStyle(EGOTheme.textSecondary)
                        Spacer()
                        TextField("", text: $mediaPipeModelPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(EGOTheme.textMuted)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func glassPickerRow(title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(EGOTheme.textSecondary)

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
                    Text(options.first(where: { $0.1 == selection.wrappedValue })?.0 ?? selection.wrappedValue)
                        .font(.subheadline)
                        .foregroundStyle(EGOTheme.textPrimary.opacity(0.75))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(EGOTheme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    EGOGlassCapsuleBackground(tint: .neutral, tintStrength: 0.15)
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
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(EGOTheme.textMuted)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EGOTheme.textMuted)
                    .tracking(0.8)
            }
            .padding(.leading, 4)

            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    EGOGlassBackground(cornerRadius: 18, tint: .neutral, tintStrength: 0.08)
                }
        }
    }
}

struct GlassTextField: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(EGOTheme.textMuted)
                .textCase(.uppercase)

            TextField("", value: $value, format: .number)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(EGOTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    EGOGlassBackground(cornerRadius: 10, tint: .neutral, tintStrength: 0.05)
                }
        }
    }
}

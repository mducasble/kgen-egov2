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

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.10),
                    Color(red: 0.04, green: 0.04, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
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
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    // MARK: - Sections

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
                        .foregroundStyle(.white.opacity(0.4))

                    HStack(spacing: 10) {
                        GlassTextField(label: "X (right)", value: $translationX)
                        GlassTextField(label: "Y (up)", value: $translationY)
                        GlassTextField(label: "Z (fwd)", value: $translationZ)
                    }
                }

                HStack {
                    Text("Downward tilt")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    GlassTextField(label: "°", value: $downwardTiltDeg)
                        .frame(width: 90)
                }

                Text("Adjust values to match your physical camera mount position.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
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
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    TextField("", text: $country)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
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
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(3)

                Text("e.g., \"dishes cleanup\" or \"warehouse stocking\"")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
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
                    .foregroundStyle(.white.opacity(0.25))

                if handTrackingBackend != HandTrackingBackendType.appleVision.rawValue {
                    HStack {
                        Text("Model path")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        TextField("", text: $mediaPipeModelPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.6))
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
                .foregroundStyle(.white.opacity(0.7))

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
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(.white.opacity(0.06))
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
                    .foregroundStyle(.white.opacity(0.3))

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.8)
            }
            .padding(.leading, 4)

            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.white.opacity(0.06), lineWidth: 0.5)
                        )
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
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            TextField("", value: $value, format: .number)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.06), lineWidth: 0.5)
                        )
                }
        }
    }
}

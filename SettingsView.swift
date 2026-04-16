import SwiftUI

/// Settings for mount calibration and session configuration.
struct SettingsView: View {
    // Mount calibration
    @AppStorage("mount_type") private var mountType = "forehead"
    @AppStorage("mount_tx") private var translationX = 0.0
    @AppStorage("mount_ty") private var translationY = 0.03
    @AppStorage("mount_tz") private var translationZ = 0.08
    @AppStorage("mount_tilt") private var downwardTiltDeg = 30.0
    
    // Session metadata
    @AppStorage("environment_type") private var environmentType = "residential"
    @AppStorage("environment_sub") private var environmentSubCategory = "room_tidy_up"
    @AppStorage("country") private var country = "US"
    @AppStorage("task_description") private var taskDescription = ""
    @AppStorage("selected_hand_tracking_backend") private var handTrackingBackend = HandTrackingBackendType.appleVision.rawValue
    @AppStorage("mediapipe_model_path") private var mediaPipeModelPath = "hand_landmarker.task"
    
    var body: some View {
        Form {
            Section("Camera Mount") {
                Picker("Mount Type", selection: $mountType) {
                    Text("Forehead").tag("forehead")
                    Text("Temple").tag("temple")
                    Text("Hat Brim").tag("hat_brim")
                    Text("Headband").tag("headband")
                }
                
                VStack(alignment: .leading) {
                    Text("Translation from head center (meters)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        VStack {
                            Text("X (right)")
                                .font(.caption2)
                            TextField("X", value: $translationX, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        VStack {
                            Text("Y (up)")
                                .font(.caption2)
                            TextField("Y", value: $translationY, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        VStack {
                            Text("Z (fwd)")
                                .font(.caption2)
                            TextField("Z", value: $translationZ, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                }
                
                HStack {
                    Text("Downward tilt (°)")
                    Spacer()
                    TextField("Tilt", value: $downwardTiltDeg, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                
                Text("Adjust these values to match your physical camera mount position relative to head center.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Section("Environment") {
                Picker("Type", selection: $environmentType) {
                    Text("Residential").tag("residential")
                    Text("Commercial").tag("commercial")
                }
                
                if environmentType == "residential" {
                    Picker("Category", selection: $environmentSubCategory) {
                        Text("Room Tidy-Up").tag("room_tidy_up")
                        Text("Dishes Cleanup").tag("dishes_cleanup")
                        Text("Laundry").tag("laundry")
                        Text("Other Home Tasks").tag("other_home")
                    }
                } else {
                    Picker("Category", selection: $environmentSubCategory) {
                        Text("Warehouse / Logistics").tag("warehouse_logistics")
                        Text("Retail Operations").tag("retail")
                        Text("Food Service").tag("food_service")
                        Text("Cleaning / Janitorial").tag("cleaning")
                        Text("Manufacturing / Assembly").tag("manufacturing")
                        Text("Construction / Trades").tag("construction")
                        Text("Hospitality / Housekeeping").tag("hospitality")
                        Text("Automotive / Equipment").tag("automotive")
                        Text("Agriculture / Landscaping").tag("agriculture")
                        Text("Field Services").tag("field_services")
                        Text("Food Retail Production").tag("food_retail")
                    }
                }
                
                TextField("Country", text: $country)
            }
            
            Section("Task") {
                TextField("Task description (optional)", text: $taskDescription)
                    .lineLimit(3)
                Text("e.g., \"dishes cleanup\" or \"warehouse stocking\"")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Hand Tracking Backend") {
                Picker("Backend", selection: $handTrackingBackend) {
                    Text("Apple Vision").tag(HandTrackingBackendType.appleVision.rawValue)
                    Text("MediaPipe").tag(HandTrackingBackendType.mediaPipe.rawValue)
                    Text("Both (parallel)").tag(HandTrackingBackendType.both.rawValue)
                }
                Text("MediaPipe outputs are saved separately as *_mediapipe.jsonl when enabled.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if handTrackingBackend != HandTrackingBackendType.appleVision.rawValue {
                    TextField("MediaPipe model path", text: $mediaPipeModelPath)
                    Text("Default: hand_landmarker.task (bundle path)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
    
    /// Build a MountCalibrationService from current settings.
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

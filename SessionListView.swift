import AVKit
import SwiftUI
import UIKit

// MARK: - Session list

struct SessionListView: View {
    @State private var sessions: [(id: String, directory: URL, date: Date)] = []
    @ObservedObject private var uploadManager = UploadManager.shared

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
                    SessionsHeader()
                        .padding(.top, 4)

                    if sessions.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(sessions, id: \.id) { session in
                                    NavigationLink {
                                        SessionDetailView(
                                            sessionId: session.id,
                                            directory: session.directory
                                        )
                                    } label: {
                                        SessionRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if let state = uploadManager.activeUploads[session.id], state.hasFailures {
                                            Button {
                                                uploadManager.retryUpload(sessionId: session.id)
                                            } label: {
                                                Label("Retry Upload", systemImage: "arrow.clockwise")
                                            }
                                        }

                                        let isUploading = uploadManager.activeUploads[session.id]?.status == .uploading
                                            || uploadManager.activeUploads[session.id]?.status == .chunking
                                        Button(role: .destructive) {
                                            withAnimation {
                                                try? SessionManager.shared.deleteSession(id: session.id)
                                                sessions = SessionManager.shared.listSessions()
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .disabled(isUploading)
                                    }
                                }
                            }
                            .padding(.top, 24)
                            .padding(.bottom, 20)
                        }
                        .scrollIndicators(.hidden)
                        .refreshable {
                            sessions = SessionManager.shared.listSessions()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            sessions = SessionManager.shared.listSessions()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(KE.ink3)
            Text("No recordings yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KE.ink1)
                .padding(.top, 10)
            Text("Tap Start on Home to capture your first session.")
                .font(.system(size: 13))
                .foregroundStyle(KE.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
    }
}

// MARK: - Header

private struct SessionsHeader: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text("Sessions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KE.ink1)

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

// MARK: - Row

private struct SessionRow: View {
    let session: (id: String, directory: URL, date: Date)
    @ObservedObject private var uploadManager = UploadManager.shared
    @State private var enrichment: SessionEnrichment = .placeholder

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SessionThumbnail(
                image: enrichment.thumbnail,
                paletteIndex: SessionPalette.index(for: session.id),
                durationSec: enrichment.durationSec
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(enrichment.activityLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KE.ink1)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(SessionRow.dateFormatter.string(from: session.date)) · \(formatSize(enrichment.sizeBytes))")
                    .font(.system(size: 12))
                    .foregroundStyle(KE.ink2)

                HStack(spacing: 8) {
                    Text("\(formatDuration(enrichment.durationSec)) · \(shortId(session.id))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(KE.ink1.opacity(0.75))

                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(KE.ink3.opacity(0.6))

                    SessionUploadBadge(state: currentUploadState)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KE.ink1.opacity(0.5))
        }
        .padding(12)
        .background(
            Color(red: 240/255, green: 246/255, blue: 254/255).opacity(0.30)
        )
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    Color(red: 210/255, green: 222/255, blue: 238/255).opacity(0.55),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color(red: 40/255, green: 55/255, blue: 80/255).opacity(0.14),
            radius: 16, x: 0, y: 8
        )
        .task(id: session.id) {
            await loadEnrichment()
        }
    }

    // MARK: Helpers

    private var currentUploadState: UploadState? {
        uploadManager.activeUploads[session.id] ?? uploadManager.loadState(sessionId: session.id)
    }

    private func loadEnrichment() async {
        // Read the quick-win pieces synchronously off the main actor.
        let sync = await Task.detached(priority: .userInitiated) {
            SessionEnrichment.loadFromDisk(
                id: session.id,
                directory: session.directory
            )
        }.value
        enrichment = sync

        // Then backfill a real thumbnail if the cache was empty. The JPEG is
        // tiny, so decoding + writing happens fast; we re-apply to state so
        // the gradient placeholder animates into the real frame.
        if sync.thumbnail == nil {
            if let img = await ThumbnailGenerator.generateIfNeeded(in: session.directory) {
                await MainActor.run { enrichment.thumbnail = img }
            }
        }
    }

    private func shortId(_ id: String) -> String {
        id.count > 12 ? String(id.prefix(12)) : id
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy 'at' HH:mm"
        return f
    }()
}

// MARK: - Thumbnail

private struct SessionThumbnail: View {
    let image: UIImage?
    let paletteIndex: Int
    let durationSec: Double

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: SessionPalette.gradient(for: paletteIndex),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: [
                        .white.opacity(0.18),
                        .clear,
                        .black.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(KE.ink1)
                            .offset(x: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color(red: 30/255, green: 45/255, blue: 65/255).opacity(0.22),
                    radius: 10, x: 0, y: 3)

            if durationSec.isFinite, durationSec > 0 {
                Text(durationLabel)
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Color(red: 20/255, green: 30/255, blue: 45/255).opacity(0.72)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(4)
            }
        }
    }

    private var durationLabel: String {
        let total = Int(durationSec.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Upload badge

private struct SessionUploadBadge: View {
    let state: UploadState?

    var body: some View {
        HStack(spacing: 4) {
            switch state?.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SessionTone.green)
                Text("Uploaded")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SessionTone.green)

            case .uploading:
                UploadProgressRing(progress: uploadProgress)
                Text("Uploading \(Int((uploadProgress * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(KE.accentBlue)

            case .chunking:
                UploadProgressRing(progress: nil)
                Text("Preparing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KE.accentBlue)

            case .failed, .partiallyFailed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SessionTone.red)
                Text("Failed · hold to retry")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SessionTone.red)

            case nil:
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundStyle(KE.ink2)
                Text("Pending")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KE.ink2)
            }
        }
    }

    private var uploadProgress: Double {
        guard let state = state, state.totalFiles > 0 else { return 0 }
        return min(1, max(0, Double(state.completedFiles) / Double(state.totalFiles)))
    }
}

private struct UploadProgressRing: View {
    /// `nil` → indeterminate (chunking).
    let progress: Double?

    var body: some View {
        ZStack {
            Circle()
                .stroke(KE.accentBlue.opacity(0.25), lineWidth: 2)
                .frame(width: 14, height: 14)

            if let progress = progress {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        KE.accentBlue,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 14, height: 14)
                    .animation(.easeOut(duration: 0.2), value: progress)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.55)
                    .tint(KE.accentBlue)
            }
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Enrichment

/// Cheap per-row data loaded off the main actor.
/// Activity label falls back to the environment sub-category (formatted) when
/// no `taskDescription` is present (sessions recorded before the Activities
/// feature landed), so the row always shows something human-readable.
private struct SessionEnrichment {
    var activityLabel: String
    var sizeBytes: Int64
    var durationSec: Double
    var thumbnail: UIImage?

    static let placeholder = SessionEnrichment(
        activityLabel: String(localized: "Session"),
        sizeBytes: 0,
        durationSec: 0,
        thumbnail: nil
    )

    static func loadFromDisk(id: String, directory: URL) -> SessionEnrichment {
        let size = SessionManager.shared.sessionSize(id: id)
        let thumb = ThumbnailGenerator.cachedImage(in: directory)

        var label = String(localized: "Session")
        var duration: Double = 0

        if let url = SessionFiles.resolveExisting("metadata", "json", in: directory),
           let data = try? Data(contentsOf: url),
           let metadata = try? JSONDecoder().decode(SessionMetadata.self, from: data) {
            duration = metadata.durationSec
            if let task = metadata.environment.taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
               !task.isEmpty {
                label = task
            } else {
                label = humanizeSubCategory(metadata.environment.subCategory)
            }
        }

        return SessionEnrichment(
            activityLabel: label,
            sizeBytes: size,
            durationSec: duration,
            thumbnail: thumb
        )
    }

    /// `"room_tidy_up"` → `"Room Tidy Up"`. Keeps underscores-as-spaces logic
    /// local so we don't import a localization dependency just for display.
    private static func humanizeSubCategory(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// MARK: - Palette

/// 5-palette cycle used as the fallback thumbnail background while the JPEG
/// is being generated (or when the source video is missing). The hash maps
/// each session to a stable slot so the list doesn't shimmer on refresh.
private enum SessionPalette {
    static func index(for id: String) -> Int {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return abs(hash) % palettes.count
    }

    static func gradient(for index: Int) -> [Color] {
        palettes[index % palettes.count]
    }

    private static let palettes: [[Color]] = [
        [
            Color(red: 107/255, green: 166/255, blue: 142/255),
            Color(red: 140/255, green: 175/255, blue: 210/255),
            Color(red: 199/255, green: 214/255, blue: 229/255)
        ],
        [
            Color(red: 227/255, green: 201/255, blue: 154/255),
            Color(red: 168/255, green: 181/255, blue: 194/255),
            Color(red: 111/255, green: 133/255, blue: 160/255)
        ],
        [
            Color(red: 181/255, green: 168/255, blue: 201/255),
            Color(red: 125/255, green: 143/255, blue: 179/255),
            Color(red:  76/255, green:  95/255, blue: 130/255)
        ],
        [
            Color(red: 212/255, green: 160/255, blue: 122/255),
            Color(red: 138/255, green: 155/255, blue: 176/255),
            Color(red:  68/255, green:  90/255, blue: 120/255)
        ],
        [
            Color(red: 122/255, green: 168/255, blue: 154/255),
            Color(red: 140/255, green: 175/255, blue: 210/255),
            Color(red:  74/255, green:  99/255, blue: 128/255)
        ]
    ]
}

// MARK: - Session Detail

private enum SessionTone {
    static let green = Color(red: 22/255, green: 105/255, blue: 72/255)
    static let greenFill = Color(red: 12/255, green: 84/255, blue: 58/255).opacity(0.18)
    static let amber = Color(red: 150/255, green: 94/255, blue: 8/255)
    static let amberFill = Color(red: 150/255, green: 94/255, blue: 8/255).opacity(0.16)
    static let red = Color(red: 145/255, green: 44/255, blue: 44/255)
    static let redFill = Color(red: 145/255, green: 44/255, blue: 44/255).opacity(0.14)
    static let blue = Color(red: 52/255, green: 88/255, blue: 130/255)
}

struct SessionDetailView: View {
    let sessionId: String
    let directory: URL
    @State private var summary: SessionDetailSummary = .empty
    @State private var isExportingZip = false
    @State private var shareURL: URL?
    @State private var exportError: String?

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
                ScrollView {
                    VStack(spacing: 16) {
                        SessionVideoHeader(summary: summary)
                        SessionScoreCard(summary: summary)
                        QualityChecksCard(checks: summary.qualityChecks)
                        RecordingStatsCard(stats: summary.recordingStats)
                        RecordingStatusCard(summary: summary, sessionId: sessionId)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, 10)
            }
        }
        .navigationTitle("Session")
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear { loadSummary() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportSessionZip()
                } label: {
                    if isExportingZip {
                        ProgressView()
                            .tint(KE.ink2)
                    } else {
                        Image(systemName: "arrow.down.doc")
                            .foregroundStyle(KE.ink1)
                    }
                }
                .disabled(isExportingZip)
            }
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert(
            "Export Failed",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }),
            actions: { Button("OK") { exportError = nil } },
            message: { Text(exportError ?? "") }
        )
    }

    private func artifactRow(file: (name: String, size: Int64, url: URL), tappable: Bool) -> some View {
        GlassCard(cornerRadius: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorForFile(file.name).opacity(0.20))
                        .frame(width: 36, height: 36)

                    Image(systemName: iconForFile(file.name))
                        .font(.subheadline)
                        .foregroundStyle(KE.ink1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline.monospaced().weight(.medium))
                        .foregroundStyle(KE.ink1)

                    Text(formatSize(file.size))
                        .font(.caption2)
                        .foregroundStyle(KE.ink3)
                }

                Spacer()

                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KE.ink3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func loadSummary() {
        summary = SessionDetailSummary.load(sessionId: sessionId, directory: directory)
    }

    private func iconForFile(_ name: String) -> String {
        if name.hasSuffix(".mp4") { return "film" }
        if name.hasSuffix(".jsonl") { return "list.bullet.rectangle" }
        if name.hasSuffix(".json") { return "doc.text" }
        return "doc"
    }

    private func colorForFile(_ name: String) -> Color {
        if name.hasSuffix(".mp4") { return .red }
        if name.hasSuffix(".jsonl") { return .green }
        if name.hasSuffix(".json") { return .blue }
        return .gray
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func isReadableJSONFile(_ name: String) -> Bool {
        name.hasSuffix(".json") || name.hasSuffix(".jsonl")
    }

    private func exportSessionZip() {
        isExportingZip = true
        exportError = nil
        Task.detached {
            do {
                let fm = FileManager.default
                let zipURL = fm.temporaryDirectory.appendingPathComponent("\(sessionId).zip")
                if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }
                if #available(iOS 16.0, *) {
                    try SimpleZip.createZip(from: directory, to: zipURL, keepParentDirectory: true)
                } else {
                    throw NSError(domain: "SessionExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export requires iOS 16+."])
                }
                await MainActor.run { isExportingZip = false; shareURL = zipURL }
            } catch {
                await MainActor.run { isExportingZip = false; exportError = error.localizedDescription }
            }
        }
    }
}

// MARK: - Session Test Summary

private struct SessionDetailSummary {
    let title: String
    let timestampText: String
    let durationText: String
    let fileSizeText: String
    let score: Int
    let scoreLabel: String
    let scoreDetail: String
    let videoURL: URL?
    let s3Prefix: String?
    let qualityChecks: [SessionCheck]
    let recordingStats: [RecordingStat]

    static let empty = SessionDetailSummary(
        title: "Session",
        timestampText: "n/a",
        durationText: "n/a",
        fileSizeText: "n/a",
        score: 0,
        scoreLabel: "Pending",
        scoreDetail: "Session analysis has not been loaded yet.",
        videoURL: nil,
        s3Prefix: nil,
        qualityChecks: [],
        recordingStats: []
    )

    static func load(sessionId: String, directory: URL) -> SessionDetailSummary {
        let metadata = readJSON(base: "metadata", ext: "json", in: directory)
        let technical = readJSON(base: "technical_validation", ext: "json", in: directory)
        let cameraDiagnostics = readJSON(base: "camera_format_diagnostics", ext: "json", in: directory)
        let imuIntrinsics = readJSON(base: "imu_intrinsics", ext: "json", in: directory)
        let qcReport = readJSON(base: "qc_report", ext: "json", in: directory)
        let frameQCMetrics = readJSONLines(base: "frame_qc_metrics", ext: "jsonl", in: directory)
        let manifest = readJSON(base: "session_manifest", ext: "json", in: directory)
        let upload = UploadStateManager.load(sessionDir: directory)

        let videoURL = SessionFiles.resolveExisting("video", "mp4", in: directory)
        let fileSizeBytes = videoURL.flatMap { fileSize(at: $0) } ?? 0
        let fileSizeText = ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
        let startMs = metadata?.double("startTimeEpochMs")
        let timestampDate = startMs.map { Date(timeIntervalSince1970: $0 / 1000.0) }
            ?? (try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()
        let timestampText = Self.dateFormatter.string(from: timestampDate)
        let title = metadata?.dict("environment")?.string("taskDescription")?.nilIfEmpty
            ?? metadata?.dict("environment")?.string("subCategory")?.nilIfEmpty
            ?? "Session \(sessionId)"

        let video = metadata?.dict("videoMetrics") ?? technical?.dict("video")
        let imu = metadata?.dict("imuMetrics") ?? technical?.dict("imu")
        let sync = metadata?.dict("syncMetrics") ?? technical?.dict("timing")
        let capture = metadata?.dict("capture")
        let durationSec = metadata?.double("durationSec") ?? 0
        let durationText = formatDuration(durationSec)
        let fps = video?.double("actualAvgFPS") ?? video?.double("fps")
        let dropped = video?.int("droppedFrames") ?? 0
        let imuSamples = imu?.int("totalSamples") ?? 0
        let imuRate = imu?.double("actualSampleRateHz") ?? imu?.double("sampleRateHz")
        let maxDelta = sync?.double("observedMaxDeltaMs")

        var qualityChecks: [SessionCheck] = []
        var recordingStats: [RecordingStat] = []

        var handRate = 0.0
        var faceRate = 0.0
        var brightness: Double?
        var blur: Double?
        let framesAnalyzed = frameQCMetrics.count
        if !frameQCMetrics.isEmpty {
            let total = Double(frameQCMetrics.count)
            let handCount = frameQCMetrics.filter { $0.bool("handDetected") == true }.count
            let faceCount = frameQCMetrics.filter { $0.bool("faceDetected") == true }.count
            brightness = normalizeBrightness(average(frameQCMetrics.compactMap { $0.double("brightnessScore") }))
            blur = normalizeSharpness(average(frameQCMetrics.compactMap { $0.double("blurScore") }))
            handRate = Double(handCount) / total * 100.0
            faceRate = Double(faceCount) / total * 100.0
        }

        let landscape = capture?.string("orientation")?.lowercased().contains("landscape") ?? true
        let durationOk = durationSec >= 3
        let lightingOk = (brightness ?? 70) >= 35
        let stabilityOk = (fps ?? 0) >= 25 && dropped <= 5 && (maxDelta ?? 0) < 15
        let sharpnessOk = (blur ?? 60) >= 40

        qualityChecks.append(SessionCheck(icon: "hand.raised", title: "Hands Visible", value: handRate > 0 ? "\(Int(handRate.rounded()))% of frames" : "No hand detected", passed: handRate > 0))
        qualityChecks.append(SessionCheck(icon: "shield.checkerboard", title: "Face Privacy", value: faceRate == 0 ? "No face detected" : "\(Int(faceRate.rounded()))% with face", passed: faceRate == 0))
        qualityChecks.append(SessionCheck(icon: "iphone.landscape", title: "Orientation", value: landscape ? "Landscape" : "Not landscape", passed: landscape))
        qualityChecks.append(SessionCheck(icon: "clock", title: "Duration", value: "\(durationText) recorded", passed: durationOk))
        qualityChecks.append(SessionCheck(icon: "sun.max", title: "Lighting", value: brightness.map { "\($0.format0())/100" } ?? "Not analyzed", passed: lightingOk))
        qualityChecks.append(SessionCheck(icon: "rectangle.dashed", title: "Stability", value: stabilityOk ? "Steady" : "Review motion/timing", passed: stabilityOk))
        qualityChecks.append(SessionCheck(icon: "eye", title: "Sharpness", value: blur.map { "\($0.format0())/100" } ?? "Not analyzed", passed: sharpnessOk))

        recordingStats.append(RecordingStat(icon: "clock", label: "Duration", value: durationText))
        recordingStats.append(RecordingStat(icon: "hand.raised", label: "Hand Visibility", value: "\(Int(handRate.rounded()))%"))
        recordingStats.append(RecordingStat(icon: "rectangle.grid.1x2", label: "Frames Analyzed", value: "\(framesAnalyzed)"))
        recordingStats.append(RecordingStat(icon: "gauge.with.dots.needle.67percent", label: "Stability", value: stabilityOk ? "Good" : "Review"))
        recordingStats.append(RecordingStat(icon: "waveform.path.ecg", label: "IMU Samples", value: "\(imuSamples)"))
        recordingStats.append(RecordingStat(icon: "sensor.tag.radiowaves.forward", label: "IMU Rate", value: "\(imuRate.format0())Hz"))

        if let passCriteria = technical?.dict("passCriteria") {
            let technicalVideo = technical?.dict("video")
            let technicalImu = technical?.dict("imu")
            let technicalTiming = technical?.dict("timing")
            let technicalCalibration = technical?.dict("calibration")
            let technicalEncoding = technical?.dict("videoEncoding")

            _ = technicalVideo
            _ = technicalImu
            _ = technicalTiming
            _ = technicalCalibration
            _ = technicalEncoding
            _ = passCriteria
        }

        _ = cameraDiagnostics
        _ = imuIntrinsics
        _ = manifest

        let passedChecks = qualityChecks.filter { $0.passed }.count
        let computedScore = Int((Double(passedChecks) / Double(Swift.max(qualityChecks.count, 1)) * 100.0).rounded())
        let reportScore = qcReport?.double("readinessScore").map { Int($0.rounded()).clamped(to: 0...100) }
        let score = reportScore ?? computedScore
        let scoreLabel = score >= 85 ? "Upload Ready" : (score >= 65 ? "Needs Review" : "Blocked")
        let scoreDetail = score >= 85 ? "Recording passed all quality checks." : "Review failed checks before upload."

        return SessionDetailSummary(
            title: title,
            timestampText: timestampText,
            durationText: durationText,
            fileSizeText: fileSizeText,
            score: score,
            scoreLabel: scoreLabel,
            scoreDetail: scoreDetail,
            videoURL: videoURL,
            s3Prefix: upload.map { "s3://kaivideo/\($0.collectorId)/\($0.sessionId)" },
            qualityChecks: qualityChecks,
            recordingStats: recordingStats
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static func readJSON(base: String, ext: String, in directory: URL) -> [String: Any]? {
        guard let url = SessionFiles.resolveExisting(base, ext, in: directory),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func readJSONLines(base: String, ext: String, in directory: URL) -> [[String: Any]] {
        guard let url = SessionFiles.resolveExisting(base, ext, in: directory),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                return object
            }
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func normalizeBrightness(_ value: Double?) -> Double? {
        guard let value else { return nil }
        let normalized = value <= 1.0 ? value * 100.0 : value
        return normalized.clamped(to: 0...100)
    }

    private static func normalizeSharpness(_ value: Double?) -> Double? {
        guard let value else { return nil }
        // Older iOS frame_qc_metrics stored raw Laplacian variance; QC expects 0...100.
        let normalized = value > 100.0 ? min(100.0, max(10.0, (value / 2500.0) * 100.0)) : value
        return normalized.clamped(to: 0...100)
    }

    private static func fileSize(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "n/a" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

private struct SessionCheck: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let passed: Bool
}

private struct RecordingStat: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
}

private struct SessionVideoHeader: View {
    let summary: SessionDetailSummary
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassCard(cornerRadius: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.86))

                    if let player {
                        VideoPlayer(player: player)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "play.rectangle")
                                .font(.system(size: 34, weight: .light))
                            Text("Video unavailable")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
                .frame(height: 220)
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(KE.ink1)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label(summary.timestampText, systemImage: "calendar")
                    Label(summary.durationText, systemImage: "clock")
                    Text(summary.fileSizeText)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KE.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .onAppear {
            if player == nil, let url = summary.videoURL {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}

private struct SessionScoreCard: View {
    let summary: SessionDetailSummary

    var body: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(scoreColor.opacity(0.22))
                            .frame(width: 42, height: 42)
                        Image(systemName: scoreIcon)
                            .foregroundStyle(scoreColor)
                            .font(.system(size: 20, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.scoreLabel)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(scoreColor)
                        Text(summary.scoreDetail)
                            .font(.system(size: 13))
                            .foregroundStyle(KE.ink2)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Session Score")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(KE.ink2)
                        Spacer()
                        Text("\(summary.score)")
                            .font(.system(size: 28, weight: .bold).monospacedDigit())
                            .foregroundStyle(scoreColor)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(KE.ink1.opacity(0.10))
                            Capsule()
                                .fill(scoreColor)
                                .frame(width: proxy.size.width * CGFloat(summary.score) / 100.0)
                        }
                    }
                    .frame(height: 10)
                }
            }
            .padding(18)
        }
    }

    private var scoreColor: Color {
        summary.score >= 85 ? SessionTone.green : (summary.score >= 65 ? SessionTone.amber : SessionTone.red)
    }

    private var scoreIcon: String {
        summary.score >= 85 ? "checkmark.circle.fill" : (summary.score >= 65 ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
    }
}

private struct QualityChecksCard: View {
    let checks: [SessionCheck]

    var body: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "clipboard", title: "Quality Checks")
                ForEach(checks) { check in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(check.passed ? SessionTone.greenFill : SessionTone.redFill)
                                .frame(width: 40, height: 40)
                            Image(systemName: check.icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(check.passed ? SessionTone.green : SessionTone.red)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(KE.ink1)
                            Text(check.value)
                                .font(.system(size: 12))
                                .foregroundStyle(KE.ink2)
                        }
                        Spacer()
                        Text(check.passed ? "Good" : "Review")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(check.passed ? SessionTone.green : SessionTone.red)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(check.passed ? SessionTone.greenFill : SessionTone.redFill, in: Capsule())
                    }
                    if check.id != checks.last?.id {
                        Divider().overlay(KE.edgeShadow.opacity(0.35))
                    }
                }
            }
            .padding(18)
        }
    }
}

private struct RecordingStatsCard: View {
    let stats: [RecordingStat]
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(icon: "chart.bar", title: "Recording Stats")
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(stats) { stat in
                        HStack(spacing: 8) {
                            Image(systemName: stat.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SessionTone.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(KE.ink3)
                                Text(stat.value)
                                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(KE.ink1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(KE.ghostTint.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(KE.edgeBright.opacity(0.35), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(18)
        }
    }
}

private struct RecordingStatusCard: View {
    let summary: SessionDetailSummary
    let sessionId: String

    var body: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(icon: "tray.and.arrow.up", title: "Recording Status")
                Text(summary.s3Prefix == nil ? "Local session" : "Upload path ready")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KE.ink1)
                Text(summary.s3Prefix ?? "Session \(sessionId) is saved locally and ready for analysis/upload.")
                    .font(.system(size: 12))
                    .foregroundStyle(KE.ink2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }
}

private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(KE.ink1)
    }
}

private struct TestSummaryItem: Identifiable {
    let id = UUID()
    let title: String
    let status: String
    let detail: String
    let passed: Bool?
}

private struct TestSummaryRow: View {
    let item: TestSummaryItem

    var body: some View {
        GlassCard(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KE.ink1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.status)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(statusColor)
                }
                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(KE.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var statusColor: Color {
        switch item.passed {
        case true: return SessionTone.green
        case false: return SessionTone.red
        case nil: return KE.ink2
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func dict(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func bool(_ key: String) -> Bool? {
        self[key] as? Bool
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? Double { return Int(value) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? Int { return Double(value) }
        return nil
    }

    func arrayCount(_ key: String) -> Int {
        (self[key] as? [Any])?.count ?? 0
    }
}

private extension Optional where Wrapped == Double {
    func format1() -> String {
        guard let self else { return "n/a" }
        return String(format: "%.1f", self)
    }

    func format0() -> String {
        guard let self else { return "n/a" }
        return String(format: "%.0f", self)
    }
}

private extension Double {
    func format0() -> String {
        String(format: "%.0f", self)
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - JSON Viewer

struct JSONArtifactView: View {
    let fileURL: URL
    @State private var textContent: String = ""
    @State private var isTruncated = false
    @State private var loadError: String?

    private let maxChars = 200_000

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
                Group {
                    if let loadError {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(KE.ink2)
                            Text("Unable to open file")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(KE.ink1)
                            Text(loadError)
                                .font(.system(size: 13))
                                .foregroundStyle(KE.ink3)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(textContent)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(KE.ink1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.vertical, 14)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .safeAreaInset(edge: .bottom) {
            if isTruncated {
                Text("Showing first \(maxChars) characters")
                    .font(.caption)
                    .foregroundStyle(KE.ink3)
                    .padding(.vertical, 8)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        do {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            if raw.count > maxChars {
                textContent = String(raw[..<raw.index(raw.startIndex, offsetBy: maxChars)])
                isTruncated = true
            } else {
                textContent = raw
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Zip Utilities

private enum SimpleZip {
    private struct Entry {
        let relativePath: String
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    static func createZip(from directory: URL, to zipURL: URL, keepParentDirectory: Bool) throws {
        let fm = FileManager.default
        let basePrefix = keepParentDirectory ? directory.lastPathComponent + "/" : ""

        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "SimpleZip", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cannot enumerate session files"])
        }

        var regularFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true { regularFiles.append(fileURL) }
        }
        regularFiles.sort { $0.path < $1.path }

        var archive = Data()
        var entries: [Entry] = []

        for fileURL in regularFiles {
            let fileData = try Data(contentsOf: fileURL)
            let relative = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")
            let zipPath = basePrefix + relative
            guard let pathData = zipPath.data(using: .utf8) else { continue }

            let localOffset = UInt32(archive.count)
            let crc = CRC32.checksum(fileData)
            let dataSize = UInt32(fileData.count)

            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(crc)
            archive.appendLE(dataSize)
            archive.appendLE(dataSize)
            archive.appendLE(UInt16(pathData.count))
            archive.appendLE(UInt16(0))
            archive.append(pathData)
            archive.append(fileData)

            entries.append(Entry(relativePath: zipPath, crc32: crc, compressedSize: dataSize, uncompressedSize: dataSize, localHeaderOffset: localOffset))
        }

        let centralDirectoryStart = UInt32(archive.count)
        for entry in entries {
            guard let pathData = entry.relativePath.data(using: .utf8) else { continue }
            archive.appendLE(UInt32(0x02014b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(entry.crc32)
            archive.appendLE(entry.compressedSize)
            archive.appendLE(entry.uncompressedSize)
            archive.appendLE(UInt16(pathData.count))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt32(0))
            archive.appendLE(entry.localHeaderOffset)
            archive.append(pathData)
        }

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryStart
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(centralDirectorySize)
        archive.appendLE(centralDirectoryStart)
        archive.appendLE(UInt16(0))

        try archive.write(to: zipURL, options: .atomic)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : (c >> 1) }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
    mutating func appendLE(_ value: UInt32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}

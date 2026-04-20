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
                    .foregroundStyle(KE.accentGreen)
                Text("Uploaded")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 70/255, green: 140/255, blue: 100/255))

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
                    .foregroundStyle(KE.accentRed)
                Text("Failed · hold to retry")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KE.accentRed)

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
        activityLabel: "Session",
        sizeBytes: 0,
        durationSec: 0,
        thumbnail: nil
    )

    static func loadFromDisk(id: String, directory: URL) -> SessionEnrichment {
        let size = SessionManager.shared.sessionSize(id: id)
        let thumb = ThumbnailGenerator.cachedImage(in: directory)

        var label = "Session"
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

struct SessionDetailView: View {
    let sessionId: String
    let directory: URL
    @State private var files: [(name: String, size: Int64, url: URL)] = []
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
                    VStack(spacing: 14) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SESSION ID")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(KE.ink3)
                                    .tracking(0.8)

                                Text(sessionId)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(KE.ink1)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                        }

                        VStack(spacing: 8) {
                            ForEach(files, id: \.name) { file in
                                if isReadableJSONFile(file.name) {
                                    NavigationLink {
                                        JSONArtifactView(fileURL: file.url)
                                    } label: {
                                        artifactRow(file: file, tappable: true)
                                    }
                                } else {
                                    artifactRow(file: file, tappable: false)
                                }
                            }
                        }
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
        .onAppear { loadFiles() }
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

    private func loadFiles() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        files = contents.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return (url.lastPathComponent, Int64(size), url)
        }.sorted { $0.name < $1.name }
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

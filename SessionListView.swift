import SwiftUI
import UIKit

struct SessionListView: View {
    @State private var sessions: [(id: String, directory: URL, date: Date)] = []
    @ObservedObject private var uploadManager = UploadManager.shared

    var body: some View {
        ZStack {
            darkBackground

            if sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sessions, id: \.id) { session in
                            NavigationLink {
                                SessionDetailView(sessionId: session.id, directory: session.directory)
                            } label: {
                                sessionRow(session)
                            }
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
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    sessions = SessionManager.shared.listSessions()
                }
            }
        }
        .navigationTitle("Sessions")
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            sessions = SessionManager.shared.listSessions()
        }
    }

    private var darkBackground: some View {
        EGOBlobBackground()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(EGOTheme.textMuted.opacity(0.6))

            Text("No Sessions")
                .font(.title3.weight(.semibold))
                .foregroundStyle(EGOTheme.textPrimary)

            Text("Recorded sessions will appear here")
                .font(.subheadline)
                .foregroundStyle(EGOTheme.textSecondary)
        }
    }

    private func sessionRow(_ session: (id: String, directory: URL, date: Date)) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [EGOTheme.sky.opacity(0.45), EGOTheme.mint.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.title3)
                    .foregroundStyle(EGOTheme.sky.opacity(0.95))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.id)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(EGOTheme.textPrimary)

                HStack(spacing: 8) {
                    Text(formatDate(session.date))
                        .font(.caption)
                        .foregroundStyle(EGOTheme.textSecondary)

                    Text("·")
                        .foregroundStyle(EGOTheme.textMuted.opacity(0.5))

                    Text(formatSize(SessionManager.shared.sessionSize(id: session.id)))
                        .font(.caption)
                        .foregroundStyle(EGOTheme.textSecondary)
                }

                uploadBadge(for: session.id)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(EGOTheme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            EGOGlassBackground(cornerRadius: 18, tint: .neutral, tintStrength: 0.05)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    @ViewBuilder
    private func uploadBadge(for sessionId: String) -> some View {
        let state = uploadManager.activeUploads[sessionId] ?? uploadManager.loadState(sessionId: sessionId)

        if let state {
            HStack(spacing: 5) {
                switch state.status {
                case .chunking:
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.orange)
                    Text("Preparing...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.8))

                case .uploading:
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.blue)
                    Text("\(state.completedFiles)/\(state.totalFiles)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.blue.opacity(0.8))
                    Text("uploading")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue.opacity(0.5))

                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.7))
                    Text("Uploaded")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green.opacity(0.7))

                case .failed, .partiallyFailed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))
                    Text("\(state.failedFiles) failed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red.opacity(0.7))
                    Text("· hold to retry")
                        .font(.system(size: 9))
                        .foregroundStyle(EGOTheme.textMuted)
                }
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
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
            EGOBlobBackground()

            ScrollView {
                VStack(spacing: 14) {
                    EGOSidebarCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SESSION ID")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(EGOTheme.textMuted)
                                .tracking(0.8)

                            Text(sessionId)
                                .font(.caption.monospaced())
                                .foregroundStyle(EGOTheme.textPrimary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Session")
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear { loadFiles() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportSessionZip()
                } label: {
                    if isExportingZip {
                        ProgressView()
                            .tint(EGOTheme.textMuted)
                    } else {
                        Image(systemName: "arrow.down.doc")
                            .foregroundStyle(EGOTheme.textPrimary.opacity(0.8))
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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorForFile(file.name).opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: iconForFile(file.name))
                    .font(.subheadline)
                    .foregroundStyle(colorForFile(file.name).opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline.monospaced().weight(.medium))
                    .foregroundStyle(EGOTheme.textPrimary)

                Text(formatSize(file.size))
                    .font(.caption2)
                    .foregroundStyle(EGOTheme.textMuted)
            }

            Spacer()

            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EGOTheme.textMuted.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            EGOGlassBackground(cornerRadius: 14, tint: .neutral, tintStrength: 0.04)
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
            EGOBlobBackground()

            Group {
                if let loadError {
                    ContentUnavailableView("Unable to open file", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    ScrollView {
                        Text(textContent)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(EGOTheme.textPrimary.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding()
                    }
                }
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom) {
            if isTruncated {
                Text("Showing first \(maxChars) characters")
                    .font(.caption)
                    .foregroundStyle(EGOTheme.textMuted)
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

import SwiftUI
import UIKit

struct SessionListView: View {
    @State private var sessions: [(id: String, directory: URL, date: Date)] = []
    
    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Recorded sessions will appear here")
                )
            }
            
            ForEach(sessions, id: \.id) { session in
                NavigationLink {
                    SessionDetailView(sessionId: session.id, directory: session.directory)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.id.prefix(8) + "...")
                            .font(.headline.monospaced())
                        Text(formatDate(session.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatSize(SessionManager.shared.sessionSize(id: session.id)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let session = sessions[index]
                    try? SessionManager.shared.deleteSession(id: session.id)
                }
                sessions.remove(atOffsets: indexSet)
            }
        }
        .navigationTitle("Sessions")
        .onAppear {
            sessions = SessionManager.shared.listSessions()
        }
        .refreshable {
            sessions = SessionManager.shared.listSessions()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SessionDetailView: View {
    let sessionId: String
    let directory: URL
    @State private var files: [(name: String, size: Int64, url: URL)] = []
    @State private var isExportingZip = false
    @State private var shareURL: URL?
    @State private var exportError: String?
    
    var body: some View {
        List {
            Section("Session ID") {
                Text(sessionId)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            
            Section("Artifacts") {
                ForEach(files, id: \.name) { file in
                    if isReadableJSONFile(file.name) {
                        NavigationLink {
                            JSONArtifactView(fileURL: file.url)
                        } label: {
                            HStack {
                                Image(systemName: iconForFile(file.name))
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading) {
                                    Text(file.name)
                                        .font(.body.monospaced())
                                    Text(formatSize(file.size))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: iconForFile(file.name))
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(file.name)
                                    .font(.body.monospaced())
                                Text(formatSize(file.size))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Session")
        .onAppear { loadFiles() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportSessionZip()
                } label: {
                    if isExportingZip {
                        ProgressView()
                    } else {
                        Label("Baixar ZIP", systemImage: "arrow.down.doc")
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
            "Falha ao exportar ZIP",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }),
            actions: { Button("OK") { exportError = nil } },
            message: { Text(exportError ?? "") }
        )
    }
    
    private func loadFiles() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }
        
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
                if fm.fileExists(atPath: zipURL.path) {
                    try fm.removeItem(at: zipURL)
                }

                if #available(iOS 16.0, *) {
                    try SimpleZip.createZip(from: directory, to: zipURL, keepParentDirectory: true)
                } else {
                    throw NSError(
                        domain: "SessionExport",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Export ZIP requires iOS 16 or newer."]
                    )
                }

                await MainActor.run {
                    isExportingZip = false
                    shareURL = zipURL
                }
            } catch {
                await MainActor.run {
                    isExportingZip = false
                    exportError = error.localizedDescription
                }
            }
        }
    }
}

struct JSONArtifactView: View {
    let fileURL: URL
    @State private var textContent: String = ""
    @State private var isTruncated = false
    @State private var loadError: String?

    private let maxChars = 200_000

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("Unable to open file", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                ScrollView {
                    Text(textContent)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isTruncated {
                Text("Displaying first \(maxChars) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .onAppear {
            load()
        }
    }

    private func load() {
        do {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            if raw.count > maxChars {
                let end = raw.index(raw.startIndex, offsetBy: maxChars)
                textContent = String(raw[..<end])
                isTruncated = true
            } else {
                textContent = raw
                isTruncated = false
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

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
            if values.isRegularFile == true {
                regularFiles.append(fileURL)
            }
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

            // Local file header
            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20)) // version needed to extract
            archive.appendLE(UInt16(0))  // general purpose bit flag
            archive.appendLE(UInt16(0))  // compression method: store
            archive.appendLE(UInt16(0))  // mod time
            archive.appendLE(UInt16(0))  // mod date
            archive.appendLE(crc)
            archive.appendLE(dataSize)
            archive.appendLE(dataSize)
            archive.appendLE(UInt16(pathData.count))
            archive.appendLE(UInt16(0))  // extra field length
            archive.append(pathData)
            archive.append(fileData)

            entries.append(
                Entry(
                    relativePath: zipPath,
                    crc32: crc,
                    compressedSize: dataSize,
                    uncompressedSize: dataSize,
                    localHeaderOffset: localOffset
                )
            )
        }

        let centralDirectoryStart = UInt32(archive.count)
        for entry in entries {
            guard let pathData = entry.relativePath.data(using: .utf8) else { continue }
            archive.appendLE(UInt32(0x02014b50))
            archive.appendLE(UInt16(20)) // version made by
            archive.appendLE(UInt16(20)) // version needed to extract
            archive.appendLE(UInt16(0))  // general purpose bit flag
            archive.appendLE(UInt16(0))  // compression method
            archive.appendLE(UInt16(0))  // mod time
            archive.appendLE(UInt16(0))  // mod date
            archive.appendLE(entry.crc32)
            archive.appendLE(entry.compressedSize)
            archive.appendLE(entry.uncompressedSize)
            archive.appendLE(UInt16(pathData.count))
            archive.appendLE(UInt16(0))  // extra field length
            archive.appendLE(UInt16(0))  // file comment length
            archive.appendLE(UInt16(0))  // disk number start
            archive.appendLE(UInt16(0))  // internal file attrs
            archive.appendLE(UInt32(0))  // external file attrs
            archive.appendLE(entry.localHeaderOffset)
            archive.append(pathData)
        }

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryStart

        // End of central directory record
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0)) // disk number
        archive.appendLE(UInt16(0)) // disk with central directory start
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(centralDirectorySize)
        archive.appendLE(centralDirectoryStart)
        archive.appendLE(UInt16(0)) // comment length

        try archive.write(to: zipURL, options: .atomic)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
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

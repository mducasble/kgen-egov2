import SwiftUI

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
    @State private var files: [(name: String, size: Int64)] = []
    
    var body: some View {
        List {
            Section("Session ID") {
                Text(sessionId)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            
            Section("Artifacts") {
                ForEach(files, id: \.name) { file in
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
        .navigationTitle("Session")
        .onAppear { loadFiles() }
    }
    
    private func loadFiles() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }
        
        files = contents.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return (url.lastPathComponent, Int64(size))
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
}

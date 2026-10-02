import Foundation

enum LibraryCachePreferences {
    static let enabledKey = "FileViewer.library.cacheEnabled"
    static let changed = Notification.Name("FileViewer.library.cacheChanged")
}

/// Serializes cache reads, writes and clearing across document windows.
/// A revision prevents an in-flight refresh from recreating a cleared cache.
actor LibraryIndexCache {
    static let shared = LibraryIndexCache()
    private let url: URL
    private var revision: UInt = 0

    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FileViewer/LibraryIndex-v1.json")) {
        self.url = url
    }

    private struct Snapshot: Codable {
        let version: Int
        let entries: [LibraryIndexEntry]
    }

    func load(enabled: Bool) -> (entries: [LibraryIndexEntry], revision: UInt) {
        guard enabled,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 100_000_000,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1,
              snapshot.entries.count <= LocalLibraryIndexer.maximumFiles else { return ([], revision) }
        var seen = Set<String>()
        var total = 0
        for entry in snapshot.entries {
            total += entry.searchableText.count
            guard entry.url.isFileURL,
                  entry.id == entry.url.standardizedFileURL.resolvingSymlinksInPath().path,
                  seen.insert(entry.id).inserted,
                  entry.searchableText.count <= LocalLibraryIndexer.maximumSearchableCharactersPerFile,
                  total <= LocalLibraryIndexer.maximumTotalSearchableCharacters else { return ([], revision) }
        }
        return (snapshot.entries, revision)
    }

    func save(_ entries: [LibraryIndexEntry], revision expectedRevision: UInt, enabled: Bool) throws {
        guard enabled, revision == expectedRevision else { return }
        let data = try JSONEncoder().encode(Snapshot(version: 1, entries: entries))
        guard data.count <= 100_000_000 else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path
        )
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func clear() throws {
        revision &+= 1
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

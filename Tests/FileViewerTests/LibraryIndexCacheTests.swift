import Foundation
import XCTest
@testable import FileViewer

final class LibraryIndexCacheTests: XCTestCase {
    func testRestartCacheRevalidatesChangedAndDeletedFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("note.md")
        let cacheURL = folder.appendingPathComponent("index.json")
        try "# Original".write(to: source, atomically: true, encoding: .utf8)
        let entries = await LocalLibraryIndexer.build(roots: [], recentURLs: [], libraryFiles: [source])
        let cache = LibraryIndexCache(url: cacheURL)
        let initial = await cache.load(enabled: true)
        try await cache.save(entries, revision: initial.revision, enabled: true)

        let restarted = LibraryIndexCache(url: cacheURL)
        let disabled = await restarted.load(enabled: false)
        XCTAssertTrue(disabled.entries.isEmpty)
        let loaded = await restarted.load(enabled: true)
        XCTAssertEqual(loaded.entries, entries)
        let permissions = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try "# Changed content".write(to: source, atomically: true, encoding: .utf8)
        let updated = await LocalLibraryIndexer.build(
            roots: [], recentURLs: [], libraryFiles: [source], existingEntries: loaded.entries
        )
        XCTAssertEqual(updated.first?.titleText, "Changed content")
        try FileManager.default.removeItem(at: source)
        let removed = await LocalLibraryIndexer.build(
            roots: [], recentURLs: [], libraryFiles: [source], existingEntries: loaded.entries
        )
        XCTAssertTrue(removed.isEmpty)
    }

    func testClearPreventsInFlightWriteAndCorruptCacheFallsBack() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cacheURL = folder.appendingPathComponent("index.json")
        let cache = LibraryIndexCache(url: cacheURL)
        let loaded = await cache.load(enabled: true)
        try await cache.clear()
        try await cache.save([], revision: loaded.revision, enabled: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))

        try Data("invalid json".utf8).write(to: cacheURL)
        let corrupt = await cache.load(enabled: true)
        XCTAssertTrue(corrupt.entries.isEmpty)
        try await cache.save([], revision: corrupt.revision, enabled: true)
        let recovered = await cache.load(enabled: true)
        XCTAssertTrue(recovered.entries.isEmpty)
        try await cache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }
}

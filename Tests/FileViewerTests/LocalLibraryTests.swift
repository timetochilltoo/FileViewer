import Foundation
import XCTest
@testable import FileViewer

final class LocalLibraryTests: XCTestCase {
    func testIndexerReadsSupportedMarkdownFromSelectedFolder() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileViewerLibraryTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let markdownURL = folder.appendingPathComponent("security-notes.md")
        let unsupportedURL = folder.appendingPathComponent("ignore.txt")
        try "# Security\nKeep this note local.".write(to: markdownURL, atomically: true, encoding: .utf8)
        try "Do not index this file.".write(to: unsupportedURL, atomically: true, encoding: .utf8)

        let entries = await LocalLibraryIndexer.build(roots: [folder], recentURLs: [])

        XCTAssertEqual(entries.map(\.name), ["security-notes.md"])
        XCTAssertTrue(entries[0].searchableText.contains("Keep this note local."))
        XCTAssertEqual(entries[0].titleText, "Security")
    }

    func testIndexerMarksExplicitAndRecentFiles() async throws {
        let explicitURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileViewerExplicit-" + UUID().uuidString + ".md")
        let recentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileViewerRecent-" + UUID().uuidString + ".md")
        defer {
            try? FileManager.default.removeItem(at: explicitURL)
            try? FileManager.default.removeItem(at: recentURL)
        }
        try "# Explicit".write(to: explicitURL, atomically: true, encoding: .utf8)
        try "# Recent".write(to: recentURL, atomically: true, encoding: .utf8)

        let explicitEntries = await LocalLibraryIndexer.build(
            roots: [],
            recentURLs: [],
            libraryFiles: [explicitURL]
        )
        XCTAssertEqual(explicitEntries.map(\.name), [explicitURL.lastPathComponent])
        XCTAssertTrue(explicitEntries[0].isExplicit)
        XCTAssertFalse(explicitEntries[0].isRecent)

        let recentEntries = await LocalLibraryIndexer.build(
            roots: [],
            recentURLs: [recentURL]
        )
        XCTAssertTrue(recentEntries[0].isRecent)
        XCTAssertFalse(recentEntries[0].isExplicit)
        XCTAssertEqual(
            LocalLibraryIndexer.search(query: "", entries: explicitEntries)[0].reason,
            "Added to Library"
        )
    }

    func testLibrarySearchRanksFilenameBeforeBodyMatches() {
        let entries = [
            entry(path: "/tmp/meeting-notes.md", kind: .markdown, title: "Weekly meeting", text: "Discuss the security review."),
            entry(path: "/tmp/project.md", kind: .markdown, title: "Security", text: "The security review is scheduled."),
            entry(path: "/tmp/other.pdf", kind: .pdf, title: "Other", text: "Unrelated material.")
        ]

        let results = LocalLibraryIndexer.search(query: "security", entries: entries)

        XCTAssertEqual(results.map(\.name), ["project.md", "meeting-notes.md"])
        XCTAssertEqual(results.first?.reason, "Match in heading or title")
    }

    func testLibrarySearchRequiresAllTermsAndReturnsRecentFilesForEmptyQuery() {
        let older = entry(path: "/tmp/older.md", kind: .markdown, title: "Older", text: "alpha", modifiedAt: Date(timeIntervalSince1970: 10))
        let newer = entry(path: "/tmp/newer.pdf", kind: .pdf, title: "Newer", text: "alpha beta", modifiedAt: Date(timeIntervalSince1970: 20))
        let unrelated = entry(path: "/tmp/unrelated.md", kind: .markdown, title: "Unrelated", text: "alpha", modifiedAt: Date(timeIntervalSince1970: 30))

        let matches = LocalLibraryIndexer.search(query: "alpha beta", entries: [older, newer, unrelated])
        XCTAssertEqual(matches.map(\.name), ["newer.pdf"])

        let recent = LocalLibraryIndexer.search(query: "", entries: [older, newer, unrelated])
        XCTAssertEqual(recent.map(\.name), ["unrelated.md", "newer.pdf", "older.md"])
    }

    func testLibrarySearchIncludesFolderPathAndReadableSnippet() {
        let entry = LibraryIndexEntry(
            url: URL(fileURLWithPath: "/Users/patrick/Documents/Study/notes.md"),
            name: "notes.md",
            kind: .markdown,
            folderPath: "/Users/patrick/Documents/Study",
            titleText: "",
            searchableText: "First line\nA useful security checklist for review.",
            modifiedAt: Date()
        )

        let results = LocalLibraryIndexer.search(query: "Study checklist", entries: [entry])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].location, "/Users/patrick/Documents/Study")
        XCTAssertEqual(results[0].snippet, "A useful security checklist for review.")
        XCTAssertEqual(results[0].reason, "Match in document text")
    }

    func testAtomicLibraryCopyPreservesSourceAndReplacesDestination() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileViewerCopySource-" + UUID().uuidString + ".md")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileViewerCopyDestination-" + UUID().uuidString + ".md")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        try "original".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertTrue(LocalLibraryFileOperations.copyFileAtomically(from: source, to: destination))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")

        try "updated".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertTrue(LocalLibraryFileOperations.copyFileAtomically(from: source, to: destination))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "updated")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "updated")
    }

    func testAtomicMarkdownWriteKeepsMarkdownUTF8Content() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileViewerMarkdownCopy-" + UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: destination) }

        let content = "# 中文\n\nA local Library copy."
        XCTAssertTrue(LocalLibraryFileOperations.writeMarkdownAtomically(content, to: destination))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), content)
    }

    private func entry(
        path: String,
        kind: DocumentKind,
        title: String,
        text: String,
        modifiedAt: Date = Date()
    ) -> LibraryIndexEntry {
        let url = URL(fileURLWithPath: path)
        return LibraryIndexEntry(
            url: url,
            name: url.lastPathComponent,
            kind: kind,
            folderPath: url.deletingLastPathComponent().path,
            titleText: title,
            searchableText: text,
            modifiedAt: modifiedAt
        )
    }
}

import Foundation
import XCTest
@testable import FileViewer

final class DocumentSafetyTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileViewerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testMarkdownDocumentReportsUnsavedChanges() {
        var document = MarkdownDocument(url: nil, untitledName: "Untitled.md", text: "Saved", savedText: "Saved")
        XCTAssertFalse(document.hasUnsavedChanges)

        document.text = "Changed"
        XCTAssertTrue(document.hasUnsavedChanges)
    }

    func testFileVersionChangesWhenFileContentsChange() throws {
        let url = temporaryDirectory.appendingPathComponent("version.md")
        try "first".write(to: url, atomically: true, encoding: .utf8)
        let original = try XCTUnwrap(FileVersion.current(for: url))

        try "a longer replacement".write(to: url, atomically: true, encoding: .utf8)
        let changed = try XCTUnwrap(FileVersion.current(for: url))

        XCTAssertNotEqual(original, changed)
    }

    @MainActor
    func testOpeningSameMarkdownFileTwiceSelectsExistingTab() throws {
        let url = temporaryDirectory.appendingPathComponent("duplicate.md")
        try "# A document".write(to: url, atomically: true, encoding: .utf8)

        let model = AppModel()
        model.open(url: url)
        let firstTabID = try XCTUnwrap(model.selectedTabID)
        model.open(url: url)

        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.selectedTabID, firstTabID)
        XCTAssertEqual(model.statusMessage, "This file is already open in this window.")
    }

    @MainActor
    func testNewMarkdownDocumentIsImmediatelySaveable() {
        let model = AppModel()

        model.newMarkdownDocument()

        XCTAssertTrue(model.isMarkdownDocument)
        XCTAssertTrue(model.canSaveMarkdown)
    }

    @MainActor
    func testMarkdownExtensionRecognitionIsCaseInsensitive() {
        XCTAssertTrue(AppModel.isMarkdown(URL(fileURLWithPath: "/tmp/notes.MD")))
        XCTAssertTrue(AppModel.isMarkdown(URL(fileURLWithPath: "/tmp/notes.markdown")))
        XCTAssertFalse(AppModel.isMarkdown(URL(fileURLWithPath: "/tmp/notes.txt")))
    }
}

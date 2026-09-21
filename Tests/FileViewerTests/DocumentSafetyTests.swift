import Foundation
import AppKit
import PDFKit
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
    func testRelativeTabSelectionWrapsAcrossOpenDocuments() throws {
        let firstURL = temporaryDirectory.appendingPathComponent("first.md")
        let secondURL = temporaryDirectory.appendingPathComponent("second.md")
        let thirdURL = temporaryDirectory.appendingPathComponent("third.md")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let model = AppModel()
        model.open(url: firstURL)
        model.open(url: secondURL)
        model.open(url: thirdURL)
        let firstTabID = try XCTUnwrap(model.tabs.first?.id)

        model.selectTab(firstTabID)
        model.selectPreviousTab()
        XCTAssertEqual(model.selectedTab?.document.name, "third.md")
        model.selectNextTab()
        XCTAssertEqual(model.selectedTab?.document.name, "first.md")
    }

    @MainActor
    func testOpeningNonFileURLDoesNotReadExternalContent() {
        let model = AppModel()
        let url = URL(string: "https://example.com/notes.md")!

        model.open(url: url)

        XCTAssertTrue(model.tabs.isEmpty)
        XCTAssertEqual(model.statusMessage, "This file type is not supported yet.")
    }

    @MainActor
    func testNewMarkdownDocumentIsImmediatelySaveable() {
        let model = AppModel()

        model.newMarkdownDocument()

        XCTAssertTrue(model.isMarkdownDocument)
        XCTAssertTrue(model.canSaveMarkdown)
    }

    @MainActor
    func testTemporaryMarkdownResponseOpensCleanPreviewTabWithUniqueName() throws {
        let model = AppModel()
        let response = "# AI Response\n\nReadable at full document width."

        model.openTemporaryMarkdownDocument(name: "Notes AI Response.md", text: response)
        model.openTemporaryMarkdownDocument(name: "Notes AI Response.md", text: response)

        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.markdownMode, .preview)
        XCTAssertEqual(model.statusMessage, "Opened AI response in Markdown.")
        XCTAssertEqual(model.tabs.compactMap { tab -> String? in
            guard case .markdown(let document) = tab.document else { return nil }
            return document.name
        }, ["Notes AI Response.md", "Notes AI Response 2.md"])
        guard case .markdown(let document) = model.document else {
            return XCTFail("Expected the temporary response tab to be Markdown.")
        }
        XCTAssertEqual(document.text, response)
        XCTAssertFalse(document.hasUnsavedChanges)
    }

    @MainActor
    func testAskAIAboutSelectionPreparesSelectedTextSession() throws {
        let model = AppModel()
        let pdfURL = temporaryDirectory.appendingPathComponent("selection.pdf")
        let pdf = PDFDocument()
        let tab = DocumentTab(document: .pdf(PDFViewerDocument(url: pdfURL, document: pdf)))
        model.tabs = [tab]
        model.selectedTabID = tab.id
        model.pdfSelectedText = "Selected source text"
        model.pdfSelectedPage = 2
        model.aiAssistant.connectionStatus = .unavailable("test")

        model.askAIAboutSelection()

        XCTAssertTrue(model.aiPanelVisible)
        XCTAssertEqual(model.aiAssistant.session(for: tab.id).scope, .selectedText)
        XCTAssertEqual(model.aiAssistant.session(for: tab.id).contextDescription, "Selected text")
        XCTAssertEqual(model.statusMessage, "Selected text is ready for an AI question.")
    }

    @MainActor
    func testAskAIAboutMarkdownSelectionRetainsContextAfterPanelOpens() {
        let model = AppModel()
        model.newMarkdownDocument()
        guard let tabID = model.selectedTabID else {
            return XCTFail("Expected a new Markdown tab")
        }
        model.aiAssistant.connectionStatus = .unavailable("test")

        model.askAIAboutSelection(markdownSelection: "Selected note context")

        XCTAssertEqual(model.currentMarkdownSelectedText(), "Selected note context")
        XCTAssertTrue(model.aiPanelVisible)
        XCTAssertEqual(model.aiAssistant.session(for: tabID).scope, .selectedText)
    }

    @MainActor
    func testMarkdownExtensionRecognitionIsCaseInsensitive() {
        XCTAssertTrue(AppModel.isMarkdown(URL(fileURLWithPath: "/tmp/notes.MD")))
        XCTAssertTrue(AppModel.isMarkdown(URL(fileURLWithPath: "/tmp/notes.markdown")))
        XCTAssertFalse(AppModel.isMarkdown(URL(fileURLWithPath: "/tmp/notes.txt")))
    }

    func testPersistedPDFCopyRemovesOnlyTemporaryViewRotation() throws {
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 200)).fill()
        image.unlockFocus()
        let page = try XCTUnwrap(PDFPage(image: image))
        page.rotation = 90 // Simulate a deliberately saved page rotation.
        document.insert(page, at: 0)

        // The reading view applies a further 90° rotation in memory.
        page.rotation = 180
        let persisted = try XCTUnwrap(document.fileViewerPersistedCopy(removingViewRotation: 90))

        XCTAssertEqual(persisted.page(at: 0)?.rotation, 90)
        XCTAssertEqual(document.page(at: 0)?.rotation, 180)
    }
}

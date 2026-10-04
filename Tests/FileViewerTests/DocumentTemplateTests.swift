import AppKit
import PDFKit
import XCTest
@testable import FileViewer

final class DocumentTemplateTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor
    func testIndependentLocalCopiesPersistAndAvoidNameCollisions() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentTemplateStore(root: root.appendingPathComponent("Templates"))
        let original = root.appendingPathComponent("Source.md")
        try Data("# Original 👋".utf8).write(to: original)
        let first = try store.save(data: DocumentTemplateStore.read(original, kind: .markdown), kind: .markdown, name: "Notes")
        let second = try store.save(data: Data("Second".utf8), kind: .markdown, name: "Notes")
        XCTAssertEqual(second.name, "Notes (2)")
        try Data("Changed source".utf8).write(to: original)
        XCTAssertEqual(try store.data(for: first), Data("# Original 👋".utf8))
        let reopened = DocumentTemplateStore(root: store.root)
        try reopened.refresh()
        XCTAssertEqual(reopened.templates.count, 2)
        XCTAssertEqual(try reopened.data(for: first), Data("# Original 👋".utf8))
        let mode = try FileManager.default.attributesOfItem(atPath: first.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        XCTAssertThrowsError(try store.save(data: Data(), kind: .markdown, name: "../escape"))
        XCTAssertThrowsError(try store.save(data: Data(), kind: .markdown, name: ".hidden"))
        XCTAssertThrowsError(try store.data(for: DocumentTemplate(url: original, kind: .markdown)))
    }

    @MainActor
    func testInvalidInputsAndSymlinkFilesAreRejected() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("source.md")
        let link = root.appendingPathComponent("link.md")
        try Data("text".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertThrowsError(try DocumentTemplateStore.read(link, kind: .markdown))
        XCTAssertThrowsError(try DocumentTemplateStore.read(URL(string: "https://example.com/a.md")!, kind: .markdown))
        XCTAssertThrowsError(try DocumentTemplateStore.read(root, kind: .markdown))
        XCTAssertThrowsError(try DocumentTemplateStore.validate(Data([0xff]), kind: .markdown))
        XCTAssertThrowsError(try DocumentTemplateStore.validate(Data(repeating: 0, count: 5 * 1024 * 1024 + 1), kind: .markdown))
        XCTAssertThrowsError(try DocumentTemplateStore.validate(Data("not a PDF".utf8), kind: .pdf))
        XCTAssertThrowsError(try DocumentTemplateStore.validate(Data(), kind: .pdf))
    }

    @MainActor
    func testMarkdownCreatesIndependentUnsavedTabsAndSnapshotsCurrentEdits() throws {
        let model = AppModel()
        model.newMarkdownDocument()
        model.updateMarkdown("# Unsaved 👋")
        let original = model.document
        let snapshot = try model.currentTemplateSnapshot()
        XCTAssertEqual(snapshot.data, Data("# Unsaved 👋".utf8))
        try model.createMarkdownFromTemplate(data: snapshot.data, name: "Notes")
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.tabs[0].document, original)
        guard case .markdown(let created) = model.document else { return XCTFail("Markdown expected") }
        XCTAssertNil(created.url)
        XCTAssertTrue(created.hasUnsavedChanges)
        XCTAssertEqual(created.text, "# Unsaved 👋")
        model.updateMarkdown("Changed copy")
        XCTAssertEqual(model.tabs[0].document, original)
        XCTAssertEqual(snapshot.data, Data("# Unsaved 👋".utf8))
    }

    @MainActor
    func testPDFSnapshotsAndCreationPreserveSourceAndRefuseExistingDestinations() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = NSImage(size: NSSize(width: 180, height: 240))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 180, height: 240)).fill()
        image.unlockFocus()
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        let original = root.appendingPathComponent("original.pdf")
        XCTAssertTrue(pdf.write(to: original))
        let originalBytes = try Data(contentsOf: original)
        let model = AppModel(opening: [original])
        guard case .pdf(let opened) = model.document else { return XCTFail("PDF expected") }
        let note = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 20, height: 20), forType: .text, withProperties: nil)
        note.contents = "Unsaved note"
        opened.document.page(at: 0)?.addAnnotation(note)
        model.rotatePDFView(by: 90)
        let snapshot = try model.currentTemplateSnapshot()
        let saved = try XCTUnwrap(PDFDocument(data: snapshot.data))
        XCTAssertEqual(saved.page(at: 0)?.rotation, 0)
        XCTAssertEqual(saved.page(at: 0)?.annotations.first?.contents, "Unsaved note")
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertEqual(opened.document.page(at: 0)?.rotation, 90)
        XCTAssertThrowsError(try model.createPDFFromTemplate(data: snapshot.data, destination: original))
        let destination = root.appendingPathComponent("copy.pdf")
        try model.createPDFFromTemplate(data: snapshot.data, destination: destination)
        XCTAssertEqual(PDFDocument(url: destination)?.pageCount, 1)
        guard case .pdf(let copy) = model.document else { return XCTFail("Copy expected") }
        copy.document.page(at: 0)?.annotations.first?.contents = "Copy edit"
        XCTAssertEqual(saved.page(at: 0)?.annotations.first?.contents, "Unsaved note")
        XCTAssertEqual(opened.document.page(at: 0)?.annotations.first?.contents, "Unsaved note")
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertThrowsError(try model.createPDFFromTemplate(data: snapshot.data, destination: destination))
    }
}

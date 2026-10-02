import AppKit
import PDFKit
import XCTest
@testable import FileViewer

final class PDFPageToolsTests: XCTestCase {
    private func fixture(_ labels: [String]) throws -> PDFDocument {
        let document = PDFDocument()
        for label in labels {
            let image = NSImage(size: NSSize(width: 180, height: 240))
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 180, height: 240)).fill()
            image.unlockFocus()
            let page = try XCTUnwrap(PDFPage(image: image))
            let note = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 20, height: 20), forType: .text, withProperties: nil)
            note.contents = label
            page.addAnnotation(note)
            document.insert(page, at: document.pageCount)
        }
        return document
    }

    private func labels(_ pdf: PDFDocument) -> [String] {
        (0..<pdf.pageCount).map { pdf.page(at: $0)?.annotations.first?.contents ?? "missing" }
    }

    func testMultiPageEditsPreserveOrderAndLeaveSourceUntouched() throws {
        let source = try fixture(["A", "B", "C", "D"])
        let duplicate = try XCTUnwrap(PDFPageTools.applying(.duplicate, to: source, selection: [0, 2], viewRotation: 0))
        XCTAssertEqual(labels(duplicate.document), ["A", "A", "B", "C", "C", "D"])
        XCTAssertEqual(duplicate.selection, [1, 4])
        duplicate.document.page(at: 1)?.annotations.first?.contents = "changed"
        XCTAssertEqual(duplicate.document.page(at: 0)?.annotations.first?.contents, "A")
        let moved = try XCTUnwrap(PDFPageTools.applying(.move(to: 4), to: source, selection: [0, 2], viewRotation: 0))
        XCTAssertEqual(labels(moved.document), ["B", "D", "A", "C"])
        XCTAssertEqual(moved.selection, [2, 3])
        let deleted = try XCTUnwrap(PDFPageTools.applying(.delete, to: source, selection: [1, 3], viewRotation: 0))
        XCTAssertEqual(labels(deleted.document), ["A", "C"])
        XCTAssertEqual(labels(source), ["A", "B", "C", "D"])
        XCTAssertNil(PDFPageTools.applying(.delete, to: source, selection: [0, 1, 2, 3], viewRotation: 0))
        XCTAssertNil(PDFPageTools.applying(.duplicate, to: source, selection: [-1], viewRotation: 0))
        XCTAssertNil(PDFPageTools.applying(.move(to: 5), to: source, selection: [0], viewRotation: 0))
        XCTAssertNil(PDFPageTools.extract(from: source, selection: [4], viewRotation: 0))
    }

    func testInsertAndExtractPreservePermanentRotation() throws {
        let source = try fixture(["A", "B"])
        source.page(at: 0)?.rotation = 180 // Permanent 90 plus temporary 90.
        source.page(at: 1)?.rotation = 90
        let incoming = try fixture(["C", "D"])
        incoming.page(at: 0)?.rotation = 270
        let inserted = try XCTUnwrap(PDFPageTools.applying(.insert(documents: [incoming], at: 1),
            to: source, selection: [0], viewRotation: 90))
        XCTAssertEqual(labels(inserted.document), ["A", "C", "D", "B"])
        XCTAssertEqual(inserted.selection, [1, 2])
        let extracted = try XCTUnwrap(PDFPageTools.extract(from: inserted.document, selection: [0, 1, 2], viewRotation: 90))
        XCTAssertEqual((0..<3).map { extracted.page(at: $0)!.rotation }, [90, 270, 0])
        XCTAssertEqual(incoming.page(at: 0)?.rotation, 270)
        XCTAssertEqual(source.page(at: 0)?.rotation, 180)
    }

    @MainActor
    func testPageAndAnnotationUndoStayChronologicalAndTabScoped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("original.pdf")
        XCTAssertTrue(try fixture(["A", "B", "C"]).write(to: url))
        let original = try Data(contentsOf: url)
        let model = AppModel()
        model.open(url: url)
        let firstID = try XCTUnwrap(model.selectedTabID)
        guard case .pdf(let pdf) = model.document else { return XCTFail("PDF missing") }
        model.preparePDFAnnotationUndoSnapshot(PDFAnnotationUndoSnapshot(url: url, data: try XCTUnwrap(pdf.document.dataRepresentation())))
        pdf.document.page(at: 0)?.annotations.first?.contents = "edited"
        model.markPDFAnnotationsChanged(for: url)
        model.selectedPDFPages = [0, 2]
        XCTAssertTrue(model.editPDFPages(.duplicate))
        XCTAssertEqual(model.pdfPageCount, 5)
        XCTAssertTrue(model.selectedTab?.pdfHasUnsavedAnnotations == true)
        model.undoPDFAnnotation()
        XCTAssertEqual(model.pdfPageCount, 3)
        XCTAssertEqual(model.selectedPDFPages, [0, 2])
        guard case .pdf(let restored) = model.document else { return XCTFail("PDF missing") }
        XCTAssertEqual(labels(restored.document), ["edited", "B", "C"])
        model.undoPDFAnnotation()
        model.redoPDFAnnotation()
        model.redoPDFAnnotation()
        XCTAssertEqual(model.pdfPageCount, 5)
        let other = directory.appendingPathComponent("other.pdf")
        XCTAssertTrue(try fixture(["D"]).write(to: other))
        model.open(url: other)
        XCTAssertEqual(model.selectedPDFPages, [0])
        model.selectTab(firstID)
        XCTAssertEqual(model.selectedPDFPages, [1, 4])
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testAIContextUsesUnsavedPageOrderWithoutCallingProvider() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AI-page-tools-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data)), mediaBox: &box, nil))
        for text in ["First document page", "Second document page"] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSString(string: text).draw(at: CGPoint(x: 10, y: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: url)
        let model = AppModel()
        model.open(url: url)
        let id = try XCTUnwrap(model.selectedTabID)
        let before = await model.aiAssistant.contextIndex(for: try XCTUnwrap(model.document), tabID: id, tab: try XCTUnwrap(model.selectedTab))
        XCTAssertTrue(before.chunks[0].text.contains("First"))
        model.selectedPDFPages = [0]
        XCTAssertTrue(model.editPDFPages(.move(to: 2)))
        let after = await model.aiAssistant.contextIndex(for: try XCTUnwrap(model.document), tabID: id, tab: try XCTUnwrap(model.selectedTab))
        XCTAssertTrue(after.chunks[0].text.contains("Second"))
        XCTAssertEqual(after.chunks[0].label, "Page 1")
        model.undoPDFAnnotation()
        let undone = await model.aiAssistant.contextIndex(for: try XCTUnwrap(model.document), tabID: id, tab: try XCTUnwrap(model.selectedTab))
        XCTAssertTrue(undone.chunks[0].text.contains("First"))
    }

    @MainActor
    func testObjectUndoSurvivesPageReplacementAndSaveRemovesViewRotation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("save.pdf")
        let source = try fixture(["A", "B"])
        source.page(at: 0)?.rotation = 90
        XCTAssertTrue(source.write(to: url))
        let model = AppModel()
        model.open(url: url)
        guard case .pdf(let pdf) = model.document, let page = pdf.document.page(at: 0) else {
            return XCTFail("PDF missing")
        }
        let note = PDFAnnotation(bounds: CGRect(x: 40, y: 40, width: 20, height: 20), forType: .text, withProperties: nil)
        note.contents = "new note"
        let id = note.ensureFileViewerUndoID()
        page.addAnnotation(note)
        model.recordPDFAnnotationObjectChange(PDFAnnotationObjectChange(url: url, document: pdf.document,
            items: [PDFAnnotationObjectItem(page: page, pageIndex: 0, annotation: note, annotationID: id)]))
        XCTAssertTrue(model.editPDFPages(.duplicate))
        model.undoPDFAnnotation()
        model.undoPDFAnnotation()
        guard case .pdf(let undone) = model.document else { return XCTFail("PDF missing") }
        XCTAssertFalse(undone.document.page(at: 0)!.annotations.contains { $0.contents == "new note" })
        model.redoPDFAnnotation()
        model.redoPDFAnnotation()
        model.rotatePDFView(by: 90)
        model.savePDFAnnotations()
        let saved = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(saved.pageCount, 3)
        XCTAssertEqual(saved.page(at: 0)?.rotation, 90)
        XCTAssertEqual(saved.page(at: 1)?.rotation, 90)
        XCTAssertEqual(saved.page(at: 2)?.rotation, 0)
        XCTAssertEqual(saved.page(at: 0)!.annotations.filter { $0.type != "Popup" }.count, 2)
        XCTAssertFalse(model.selectedTab?.pdfHasUnsavedAnnotations == true)
    }

    @MainActor
    func testExportsProtectOpenSourcesAndNeverOverwriteSplitFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("original.pdf")
        XCTAssertTrue(try fixture(["A", "B", "C"]).write(to: url))
        let model = AppModel()
        model.open(url: url)
        model.selectedPDFPages = [0, 2]
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(model.exportSelectedPDFPages(to: url))
        XCTAssertFalse(model.exportSelectedPDFPages(to: URL(string: "https://example.com/a.pdf")!))
        let output = directory.appendingPathComponent("selected.pdf")
        XCTAssertTrue(model.exportSelectedPDFPages(to: output))
        XCTAssertEqual(labels(try XCTUnwrap(PDFDocument(url: output))), ["A", "C"])
        XCTAssertTrue(model.exportPDFPagesIndividually(to: directory, asImages: false))
        let splitURL = directory.appendingPathComponent("original page 1.pdf")
        let splitBytes = try Data(contentsOf: splitURL)
        XCTAssertFalse(model.exportPDFPagesIndividually(to: directory, asImages: false))
        XCTAssertEqual(try Data(contentsOf: splitURL), splitBytes)
        XCTAssertTrue(model.exportPDFPagesIndividually(to: directory, asImages: true))
        XCTAssertNotNil(NSImage(contentsOf: directory.appendingPathComponent("original page 3.png")))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertFalse(model.selectedTab?.pdfHasUnsavedAnnotations == true)
    }
}

import AppKit
import PDFKit
import XCTest
@testable import FileViewer

final class PDFOCRTests: XCTestCase {
    @MainActor
    private func scannedFixture() throws -> Data {
        let image = NSImage(size: NSSize(width: 600, height: 400))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 600, height: 400)).fill()
        ("FILEVIEWER OCR SAMPLE" as NSString).draw(at: NSPoint(x: 30, y: 230), withAttributes: [
            .font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black
        ])
        image.unlockFocus()
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 1)
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    @MainActor
    func testScannedTextAndSelectedPageWithoutChangingSource() async throws {
        let data = try scannedFixture()
        let source = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue((source.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let text = try await Task.detached {
            try await PDFOCR.recognize(data: data, pages: [1], name: "Scan.pdf")
        }.value
        XCTAssertTrue(text.contains("FILEVIEWER OCR SAMPLE"), text)
        XCTAssertTrue(text.contains("## Page 2"))
        XCTAssertFalse(text.contains("## Page 1"))
        XCTAssertEqual(source.pageCount, 2)
        XCTAssertTrue((source.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testRejectsInvalidInputsAndLimitsBeforeRecognition() async {
        for pages in [[], [-1], [0, 0], Array(0...PDFOCR.maximumPages)] {
            do {
                _ = try await PDFOCR.recognize(data: Data(), pages: pages, name: "bad")
                XCTFail("Invalid input accepted")
            } catch { XCTAssertTrue(error is PDFOCRError) }
        }
    }

    @MainActor
    func testCancellationAndBoundedRotatedRaster() async throws {
        let data = try scannedFixture()
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PDFOCR.recognize(data: data, pages: [0], name: "Scan.pdf")
        }
        do { _ = try await worker.value; XCTFail("Cancelled OCR returned text") }
        catch { XCTAssertTrue(error is CancellationError) }
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        func darkPixelCount(_ image: CGImage) throws -> Int {
            let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
            return stride(from: 0, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] < 128 ? 1 : 0) }
        }
        let originalCount = try darkPixelCount(PDFOCR.render(page))
        XCTAssertGreaterThan(originalCount, 1000)
        for rotation in [90, 180, 270] {
            page.rotation = rotation
            let raster = try PDFOCR.render(page)
            XCTAssertLessThanOrEqual(max(raster.width, raster.height), 2400)
            if rotation != 180 { XCTAssertGreaterThan(raster.height, raster.width) }
            XCTAssertEqual(Double(try darkPixelCount(raster)), Double(originalCount), accuracy: Double(originalCount) * 0.05,
                           "Rotation must retain all rasterized text without double-transform clipping")
        }
    }

    @MainActor
    func testSnapshotAndTemporaryResultPreserveTabState() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: scannedFixture()))
        let model = AppModel(opening: [])
        let tab = DocumentTab(document: .pdf(PDFViewerDocument(url: URL(fileURLWithPath: "/tmp/OCR.pdf"), document: pdf)))
        model.tabs = [tab]
        model.selectedTabID = tab.id
        model.pdfPage = 2
        model.recognizePDFText(allPages: false)
        let job = try XCTUnwrap(model.pdfOCRJob)
        XCTAssertEqual(job.pages, [1])
        XCTAssertEqual(job.tabID, tab.id)
        XCTAssertFalse(model.tabs[0].pdfHasUnsavedAnnotations)
        model.openTemporaryMarkdownDocument(name: "OCR.md", text: "Recognized text")
        XCTAssertEqual(model.tabs[0].pdfPage, 2)
        XCTAssertFalse(model.tabs[0].pdfHasUnsavedAnnotations)
        guard case .markdown(let markdown) = model.document else { return XCTFail("Missing result tab") }
        XCTAssertNil(markdown.url)
        XCTAssertFalse(markdown.hasUnsavedChanges)
        XCTAssertEqual(markdown.text, "Recognized text")
        model.pdfOCRJob = nil
    }

    func testLiteralFenceCannotBeClosedByRecognizedMarkdown() {
        let text = "```\n![image](secret.png)\n````\n<script>unsafe</script>"
        let block = PDFOCR.literalBlock(text)
        XCTAssertTrue(block.hasPrefix("`````\n"))
        XCTAssertTrue(block.hasSuffix("\n`````"))
        XCTAssertTrue(block.contains(text))
    }

    @MainActor
    func testCloseAndStructuralEditDismissSourceJob() throws {
        let model = AppModel(opening: [])
        let pdf = try XCTUnwrap(PDFDocument(data: scannedFixture()))
        var tab = DocumentTab(document: .pdf(PDFViewerDocument(url: URL(fileURLWithPath: "/tmp/OCR-close.pdf"), document: pdf)))
        // A saved page rotation plus a temporary reading rotation.
        pdf.page(at: 0)?.rotation = 180
        pdf.page(at: 1)?.rotation = 90
        tab.pdfViewRotation = 90
        model.tabs = [tab]
        model.selectedTabID = tab.id
        model.recognizePDFText(allPages: true)
        let job = try XCTUnwrap(model.pdfOCRJob)
        XCTAssertEqual(job.pages, [0, 1])
        let snapshot = try XCTUnwrap(PDFDocument(data: job.data))
        XCTAssertEqual(snapshot.page(at: 0)?.rotation, 90)
        XCTAssertEqual(snapshot.page(at: 1)?.rotation, 0)
        XCTAssertEqual(pdf.page(at: 0)?.rotation, 180)
        XCTAssertTrue(model.editPDFPages(.duplicate))
        XCTAssertNil(model.pdfOCRJob)
        // Restore a clean source to exercise close without an unsaved dialog.
        model.tabs = [tab]
        model.recognizePDFText(allPages: false)
        XCTAssertNotNil(model.pdfOCRJob)
        model.requestCloseTab(tab.id)
        XCTAssertNil(model.pdfOCRJob)
        XCTAssertTrue(model.tabs.isEmpty)
    }
}

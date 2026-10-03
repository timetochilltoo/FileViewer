import AppKit
import PDFKit
import XCTest
@testable import FileViewer

final class PDFReadingTests: XCTestCase {
    private func fixture() throws -> PDFDocument {
        let pdf = PDFDocument()
        for _ in 0..<3 {
            let image = NSImage(size: NSSize(width: 100, height: 150))
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 100, height: 150)).fill()
            image.unlockFocus()
            pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: pdf.pageCount)
        }
        return pdf
    }

    @MainActor
    func testLayoutMapsToNativeDisplayModesAndOldStateStillDecodes() throws {
        XCTAssertEqual(PDFReadingLayout.continuous.displayMode, .singlePageContinuous)
        XCTAssertEqual(PDFReadingLayout.singlePage.displayMode, .singlePage)
        XCTAssertEqual(PDFReadingLayout.twoPages.displayMode, .twoUp)
        let legacy = Data("{\"path\":\"/tmp/legacy.pdf\",\"pdfPage\":2,\"pdfScale\":1.5}".utf8)
        XCTAssertNil(try JSONDecoder().decode(SavedPDFState.self, from: legacy).pdfReadingLayout)
        XCTAssertEqual(PDFPresentationController.clampedPage(-10, count: 3), 1)
        XCTAssertEqual(PDFPresentationController.clampedPage(10, count: 3), 3)
    }

    @MainActor
    func testLayoutBelongsToEachTabRestoresAndDoesNotDirtyPDF() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        XCTAssertTrue(try fixture().write(to: first))
        XCTAssertTrue(try fixture().write(to: second))
        let bytes = try Data(contentsOf: first)
        let model = AppModel()
        model.open(url: first)
        let firstID = try XCTUnwrap(model.selectedTabID)
        model.pdfReadingLayout = .twoPages
        XCTAssertFalse(model.selectedTab?.pdfHasUnsavedAnnotations == true)
        model.open(url: second)
        XCTAssertEqual(model.pdfReadingLayout, .continuous)
        model.pdfReadingLayout = .singlePage
        model.selectTab(firstID)
        XCTAssertEqual(model.pdfReadingLayout, .twoPages)
        let reopened = AppModel()
        reopened.open(url: first)
        XCTAssertEqual(reopened.pdfReadingLayout, .twoPages)
        let snapshot = try XCTUnwrap(model.sessionSnapshot())
        XCTAssertEqual(snapshot.tabs[0].pdfReadingLayout, .twoPages)
        XCTAssertEqual(try Data(contentsOf: first), bytes)
    }

    @MainActor
    func testPresentationIsDetachedBoundedAndRetiresClosedWindow() throws {
        _ = NSApplication.shared
        let source = try fixture()
        let field = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 60, height: 20), forType: .widget, withProperties: nil)
        field.widgetFieldType = .text
        field.fieldName = "sample"
        field.widgetStringValue = "original"
        source.page(at: 0)!.addAnnotation(field)
        let id = UUID()
        let controller = try XCTUnwrap(PDFPresentationController.present(tabID: id, document: source, name: "Sample", page: 2, fullscreen: false))
        defer { controller.close() }
        XCTAssertFalse(controller.pdfView.document === source)
        XCTAssertEqual(controller.pdfView.displayMode, .singlePage)
        XCTAssertEqual(controller.currentPage, 2)
        controller.go(to: 999)
        XCTAssertEqual(controller.currentPage, 3)
        controller.go(to: -10)
        XCTAssertEqual(controller.currentPage, 1)
        XCTAssertTrue(controller.pdfView.hitTest(NSPoint(x: 30, y: 80)) === controller.pdfView)
        controller.pdfView.document?.page(at: 0)?.annotations.first?.widgetStringValue = "snapshot only"
        XCTAssertEqual(field.widgetStringValue, "original")
        XCTAssertTrue(PDFPresentationController.present(tabID: id, document: source, name: "Sample", page: 1, fullscreen: false) === controller)
        controller.close()
        XCTAssertNil(controller.pdfView.document)
        XCTAssertNil(controller.window?.contentView)
        XCTAssertEqual(controller.window?.sharingType, NSWindow.SharingType.none)
        XCTAssertTrue(controller.window?.isExcludedFromWindowsMenu == true)
        XCTAssertNil(PDFPresentationController.present(tabID: UUID(), document: PDFDocument(), name: "Empty", page: 1, fullscreen: false))
    }
}

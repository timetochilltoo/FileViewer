import AppKit
import PDFKit
import XCTest
@testable import FileViewer

final class MarkdownExportTests: XCTestCase {
    @MainActor
    func testHTMLPreservesBlocksAndEscapesUntrustedContent() throws {
        let markdown = "# <script>alert(1)</script>\n\n**Bold** *Italic* `a < b` <u>Under</u>\n\n[Safe](https://example.com/?a=1&b=2) [Bad](javascript:alert)\n\n- item\n- [x] done\n\n3. third\n4. fourth\n\n| Name | Value |\n| :--- | ---: |\n| a\\|b | 2 |\n\n```<img>\n<script>literal</script>\n```\n![remote](https://example.com/image.png)"
        let html = String(decoding: try MarkdownExport.data(markdown: markdown, title: "</title><script>x</script>", documentURL: nil, format: .html), as: UTF8.self)
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("<strong>Bold</strong>"))
        XCTAssertTrue(html.contains("<em>Italic</em>"))
        XCTAssertTrue(html.contains("<code>a &lt; b</code>"))
        XCTAssertTrue(html.contains("<u>Under</u>"))
        XCTAssertTrue(html.contains("href=\"https://example.com/?a=1&amp;b=2\""))
        XCTAssertFalse(html.contains("href=\"javascript:"))
        XCTAssertFalse(html.contains("src=\"https:"))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("<li value=\"3\">third</li>"))
        XCTAssertTrue(html.contains("☑ done"))
        XCTAssertTrue(html.contains("text-align:right"))
        XCTAssertTrue(html.contains("a|b"))
        XCTAssertTrue(html.contains("&lt;script&gt;literal&lt;/script&gt;"))
        XCTAssertFalse(html.contains("Copy Code"))
    }

    @MainActor
    func testLocalImageIsEmbeddedAndOutsideFolderIsBlocked() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: root.appendingPathComponent("image.png"))
        let html = MarkdownExport.html(markdown: "![Local](image.png)\n![Blocked](../image.png)", title: "Images", documentURL: root.appendingPathComponent("source.md"))
        XCTAssertEqual(html.components(separatedBy: "data:image/png;base64,").count, 2)
        XCTAssertTrue(html.contains("Blocked — Image unavailable or blocked"))
    }

    @MainActor
    func testNativePDFIsPaginatedSearchableAndOmitsAppControls() throws {
        let text = "# First heading\n\n| Name | Amount |\n| --- | ---: |\n| Alpha | 10 |\n\n```swift\nlet x = 1\n```\n" + (1...160).map { "Paragraph \($0) with readable text.\n" }.joined() + "\n# Final heading\nFinal destination"
        let data = try MarkdownExport.data(markdown: text, title: "Sample", documentURL: nil, format: .pdf)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("First heading") == true)
        XCTAssertTrue(pdf.string?.contains("Final destination") == true)
        XCTAssertTrue(pdf.string?.contains("Alpha") == true)
        XCTAssertFalse(pdf.string?.contains("Copy Code") == true)
        let exportedText = pdf.string ?? ""
        for number in 1...160 {
            XCTAssertEqual(exportedText.components(separatedBy: "Paragraph \(number) with readable text.").count - 1, 1, "Paragraph \(number) must occur once across page boundaries")
        }
        for index in 0..<pdf.pageCount {
            let rect = try XCTUnwrap(pdf.page(at: index)).bounds(for: .mediaBox)
            XCTAssertEqual(rect.width, 595, accuracy: 1)
            XCTAssertEqual(rect.height, 842, accuracy: 1)
        }
        // Keep a disposable artifact for native inspection of the actual rendered PDF.
        try data.write(to: URL(fileURLWithPath: "/private/tmp/FileViewer Export Sample.pdf"))
    }

    @MainActor
    func testVerifiedWriterRefusesExistingFilesAndLeavesNoTemporaryFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("export.html")
        let data = try MarkdownExport.data(markdown: "# Current edits", title: "Sample", documentURL: nil, format: .html)
        try MarkdownExport.write(data, format: .html, to: url)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertThrowsError(try MarkdownExport.write(Data("replacement".utf8), format: .html, to: url))
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertThrowsError(try MarkdownExport.write(Data("invalid".utf8), format: .pdf, to: root.appendingPathComponent("bad.pdf")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["export.html"])
        XCTAssertThrowsError(try MarkdownExport.write(data, format: .html, to: URL(string: "https://example.com/export.html")!))
    }
}

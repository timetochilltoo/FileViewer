import AppKit
import XCTest
@testable import FileViewer

final class MarkdownLocalImageTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func png() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<16 { for y in 0..<8 { rep.setColor(NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1), atX: x, y: y) } }
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testImageSyntaxAndDocumentFolderConfinement() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("notes.md")
        XCTAssertEqual(MarkdownLocalImage.parse(#"![Hello \] world](<images/圖 表.png> "Title")"#), .init(alt: "Hello ] world", destination: "images/圖 表.png"))
        XCTAssertEqual(MarkdownLocalImage.parse(#"![Chart](images/chart(2).png 'Title')"#)?.destination, "images/chart(2).png")
        XCTAssertNil(MarkdownLocalImage.parse("before ![inline](image.png) after"))
        XCTAssertNil(MarkdownLocalImage.parse("![broken](image.png extra text)"))
        XCTAssertEqual(MarkdownLocalImage(alt: "", destination: "images/a%20b%23.png").localURL(documentURL: document)?.lastPathComponent, "a b#.png")
        for target in ["https://example.com/image.png", "data:image/png;base64,x", "//server/share.png", "file://server/image.png", "../outside.png", "%2E%2E/outside.png", "/etc/image.png", "image.png?token=x", "image.png#part", "file:///tmp/image.png"] {
            XCTAssertNil(MarkdownLocalImage(alt: "", destination: target).localURL(documentURL: document), target)
        }
        XCTAssertNil(MarkdownLocalImage(alt: "", destination: "image.png").localURL(documentURL: nil))
    }

    @MainActor
    func testLoadsBoundedRasterAndRejectsSymlinksNonImagesAndTinyBudget() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("notes.md")
        let bytes = try png()
        let imageURL = root.appendingPathComponent("image.png")
        try bytes.write(to: imageURL)
        let reference = MarkdownLocalImage(alt: "Blue sample", destination: "image.png")
        var budget = 1_000_000
        let image = try XCTUnwrap(MarkdownImageLoader.load(reference, documentURL: document, remainingBytes: &budget))
        XCTAssertEqual(image.size, NSSize(width: 16, height: 8))
        XCTAssertEqual(budget, 1_000_000 - bytes.count)
        var tiny = bytes.count - 1
        XCTAssertNil(MarkdownImageLoader.load(reference, documentURL: document, remainingBytes: &tiny))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: imageURL)
        XCTAssertNil(MarkdownImageLoader.load(.init(alt: "", destination: "link.png"), documentURL: document, remainingBytes: &budget))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-folder"), withDestinationURL: root)
        XCTAssertNil(MarkdownImageLoader.load(.init(alt: "", destination: "linked-folder/image.png"), documentURL: document, remainingBytes: &budget))
        try Data("<svg><image href='https://example.com'/></svg>".utf8).write(to: root.appendingPathComponent("vector.svg"))
        XCTAssertNil(MarkdownImageLoader.load(.init(alt: "", destination: "vector.svg"), documentURL: document, remainingBytes: &budget))
        XCTAssertNil(MarkdownImageLoader.load(.init(alt: "", destination: "missing.png"), documentURL: document, remainingBytes: &budget))
        XCTAssertNil(MarkdownImageLoader.load(.init(alt: "", destination: "."), documentURL: document, remainingBytes: &budget))
        let oversized = root.appendingPathComponent("oversized.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(MarkdownImageLoader.maximumBytes + 1))
        try handle.close()
        let previousBudget = budget
        XCTAssertNil(MarkdownImageLoader.load(.init(alt: "", destination: "oversized.png"), documentURL: document, remainingBytes: &budget))
        XCTAssertEqual(budget, previousBudget)
    }

    @MainActor
    func testPreviewKeepsCaptionsAndLimitsImagesWithoutChangingSource() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("notes.md")
        try png().write(to: root.appendingPathComponent("image.png"))
        let markdown = Array(repeating: "![Blue sample](image.png)", count: 21).joined(separator: "\n") + "\n![Remote](https://example.com/image.png)\n```md\n![Literal](image.png)\n```"
        let rendered = MarkdownPreviewTextView.attributedPreview(markdown: markdown, searchText: "Blue", searchMatchIndex: 0, documentURL: document)
        var count = 0
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value is NSTextAttachment { count += 1 }
        }
        XCTAssertEqual(count, 20)
        XCTAssertTrue(rendered.string.contains("Blue sample"))
        XCTAssertTrue(rendered.string.contains("Image unavailable or blocked"))
        XCTAssertTrue(rendered.string.contains("![Literal](image.png)"))
        let unsaved = MarkdownPreviewTextView.attributedPreview(markdown: "![Blue](image.png)", searchText: "", searchMatchIndex: 0)
        XCTAssertTrue(unsaved.string.contains("Save this Markdown file"))
        let coordinator = MarkdownPreviewTextView.Coordinator(initialScrollY: 0, initialVisibleLocation: 0, onViewportChanged: { _, _ in }, onTextViewReady: { _ in })
        XCTAssertTrue(coordinator.shouldRender(markdown: markdown, searchText: "", searchMatchIndex: 0))
        XCTAssertTrue(coordinator.shouldRender(markdown: markdown, searchText: "", searchMatchIndex: 0, documentURL: document))
        XCTAssertFalse(coordinator.shouldRender(markdown: markdown, searchText: "", searchMatchIndex: 0, documentURL: document))
    }

    @MainActor
    func testAttachmentFitsNarrowTextContainers() {
        let image = NSImage(size: NSSize(width: 1200, height: 600))
        let cell = MarkdownImageCell(imageCell: image)
        let container = NSTextContainer(size: NSSize(width: 200, height: 1000))
        let frame = cell.cellFrame(for: container, proposedLineFragment: NSRect(x: 0, y: 0, width: 200, height: 1000), glyphPosition: .zero, characterIndex: 0)
        XCTAssertLessThanOrEqual(frame.width, 200)
        XCTAssertEqual(frame.height, frame.width / 2)
        XCTAssertLessThanOrEqual(cell.cellSize().width, 640)
    }
}

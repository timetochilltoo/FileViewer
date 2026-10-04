import AppKit
import XCTest
@testable import FileViewer

final class MarkdownHeadingNavigationTests: XCTestCase {
    @MainActor
    func testDuplicateUnicodeHeadingsMapToTheirOwnRenderedPositions() throws {
        let text = "你好 👋\n# **Same**\n```md\n# Hidden\n```\n# **Same**\n#not-heading\n"
        let headings = AppModel.extractHeadings(from: text)
        XCTAssertEqual(headings.map(\.title), ["**Same**", "**Same**"])
        XCTAssertEqual(Set(headings.map(\.id)).count, 2)
        XCTAssertEqual(headings[0].sourceLocation, ("你好 👋\n" as NSString).length)
        let rendered = MarkdownPreviewTextView.attributedPreview(markdown: text, searchText: "Same", searchMatchIndex: 0)
        let first = try XCTUnwrap(MarkdownHeadingNavigation.previewRange(for: headings[0].sourceLocation, in: rendered))
        let second = try XCTUnwrap(MarkdownHeadingNavigation.previewRange(for: headings[1].sourceLocation, in: rendered))
        XCTAssertLessThan(first.location, second.location)
        XCTAssertEqual((rendered.string as NSString).substring(with: NSRange(location: second.location, length: 4)), "Same")
        XCTAssertNil(MarkdownHeadingNavigation.previewRange(for: 9999, in: rendered))
        XCTAssertTrue(AppModel.extractHeadings(from: "~~~\n# Hidden").isEmpty)
    }

    @MainActor
    func testNavigationRoutesBothPanesWithoutChangingSelectionOrOtherTabs() throws {
        let model = AppModel()
        model.newMarkdownDocument()
        model.updateMarkdown("Intro 👋\n# Target\nText")
        let firstTab = try XCTUnwrap(model.selectedTabID)
        let heading = try XCTUnwrap(model.markdownHeadings.first)
        let source = NavigationTextView()
        let preview = NavigationTextView()
        source.string = "Intro 👋\n# Target\nText"
        preview.textStorage?.setAttributedString(MarkdownPreviewTextView.attributedPreview(markdown: source.string, searchText: "", searchMatchIndex: 0))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(source)
        window.contentView?.addSubview(preview)
        source.setSelectedRange(NSRange(location: 0, length: 2))
        model.rememberMarkdownTextView(source)
        model.rememberMarkdownPreviewTextView(preview)
        let original = model.document
        model.navigateToMarkdownHeading(heading)
        XCTAssertEqual(source.destination?.location, heading.sourceLocation)
        XCTAssertNotNil(preview.destination)
        XCTAssertEqual(source.selectedRange(), NSRange(location: 0, length: 2))
        XCTAssertEqual(model.document, original)
        source.destination = nil
        preview.destination = nil
        model.newMarkdownDocument()
        model.updateMarkdown(source.string)
        model.navigateToMarkdownHeading(heading)
        XCTAssertNil(source.destination)
        XCTAssertNil(preview.destination)
        model.selectedTabID = firstTab
        window.contentView = nil
    }
}

@MainActor
private final class NavigationTextView: NSTextView {
    var destination: NSRange?
    override func scrollRangeToVisible(_ range: NSRange) { destination = range }
}

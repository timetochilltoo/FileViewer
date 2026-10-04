import AppKit
import XCTest
@testable import FileViewer

final class MarkdownPreviewTests: XCTestCase {
    @MainActor
    func testSplitViewSelectionCallbacksSettleAndPreviewRendersOnlyChangedInputs() {
        let model = AppModel()
        let source = NSTextView()
        let preview = NSTextView()
        source.string = "hello"
        preview.string = "hello"
        model.rememberMarkdownTextView(source)
        model.rememberMarkdownPreviewTextView(preview)
        let initial = model.selectionChangeToken
        for _ in 0..<10 {
            model.rememberMarkdownTextView(source)
            model.rememberMarkdownPreviewTextView(preview)
        }
        XCTAssertEqual(model.selectionChangeToken, initial)
        source.setSelectedRange(NSRange(location: 0, length: 2))
        model.rememberMarkdownTextView(source)
        XCTAssertEqual(model.selectionChangeToken, initial + 1)
        model.rememberMarkdownPreviewTextView(preview)
        XCTAssertEqual(model.selectionChangeToken, initial + 1)

        let coordinator = MarkdownPreviewTextView.Coordinator(initialScrollY: 0, initialVisibleLocation: 0, onViewportChanged: { _, _ in }, onTextViewReady: { _ in })
        XCTAssertTrue(coordinator.shouldRender(markdown: "hello", searchText: "", searchMatchIndex: 0))
        XCTAssertFalse(coordinator.shouldRender(markdown: "hello", searchText: "", searchMatchIndex: 0))
        XCTAssertTrue(coordinator.shouldRender(markdown: "hello", searchText: "hello", searchMatchIndex: 0))
        XCTAssertTrue(coordinator.shouldRender(markdown: "hello", searchText: "hello", searchMatchIndex: 1))
        XCTAssertTrue(coordinator.shouldRender(markdown: "changed", searchText: "hello", searchMatchIndex: 1))
    }
    private func codes(_ markdown: String) -> [MarkdownPreviewBlock.Code] {
        MarkdownPreviewBlock.parse(markdown).compactMap {
            if case .code(let code) = $0.kind { return code }
            return nil
        }
    }

    func testLongFencesKeepNestedMarkdownAndFalseClosersLiteral() {
        let markdown = "````markdown\n```swift\nlet x = 1\n```\n```` not a closer\n~~~~\n`````\n# After"
        XCTAssertEqual(codes(markdown), [.init(text: "```swift\nlet x = 1\n```\n```` not a closer\n~~~~", language: "markdown")])
        guard case .heading(_, "After") = MarkdownPreviewBlock.parse(markdown).last?.kind else {
            return XCTFail("Closing fence must resume normal rendering")
        }
    }

    func testTildeUnclosedAndIndentedFencesPreserveWhitespaceAndUnicode() {
        XCTAssertEqual(codes("  ~~~python title\n  print('你好 👋')\n\n  ~~~~"),
                       [.init(text: "  print('你好 👋')\n", language: "python")])
        XCTAssertEqual(codes("```\n\tvalue\n"), [.init(text: "\tvalue\n", language: "")])
        XCTAssertTrue(codes("    ```swift\nno fence\n    ```").isEmpty)
        XCTAssertNil(MarkdownCodeFence(opening: "```bad`info"))
        XCTAssertNil(MarkdownCodeFence(opening: "~~"))
        XCTAssertFalse(MarkdownCodeFence(opening: "~~~")!.closes("    ~~~"))
    }

    @MainActor
    func testCopyLinksContainExactCodeNotLabelsOrOtherBlocks() {
        let first = "  let emoji = \"👋\"\n\tprint(emoji)"
        let second = "**literal** | table |\n<script>plain text</script>"
        let rendered = MarkdownPreviewTextView.attributedPreview(
            markdown: "```swift\n\(first)\n```\n~~~text\n\(second)\n~~~",
            searchText: "print", searchMatchIndex: 0
        )
        var copied: [String] = []
        rendered.enumerateAttribute(.fileViewerCodeContent, in: NSRange(location: 0, length: rendered.length)) { value, range, _ in
            guard let code = value as? String else { return }
            XCTAssertEqual((rendered.string as NSString).substring(with: range), "Copy Code")
            XCTAssertEqual((rendered.attribute(.link, at: range.location, effectiveRange: nil) as? URL)?.scheme, "fileviewer-copy-code")
            copied.append(code)
        }
        XCTAssertEqual(copied, [first, second])
        XCTAssertTrue(rendered.string.contains("swift    Copy Code"))
        XCTAssertTrue(rendered.string.contains(second))
    }

    @MainActor
    func testDocumentSuppliedCopySchemeIsConsumedWithoutClipboardAction() {
        let view = NSTextView()
        view.string = "untrusted link"
        let coordinator = MarkdownPreviewTextView.Coordinator(
            initialScrollY: 0, initialVisibleLocation: 0,
            onViewportChanged: { _, _ in }, onTextViewReady: { _ in }
        )
        let changeCount = NSPasteboard.general.changeCount
        XCTAssertTrue(coordinator.textView(view, clickedOnLink: URL(string: "fileviewer-copy-code://block")!, at: 0))
        XCTAssertTrue(coordinator.textView(view, clickedOnLink: "fileviewer-copy-code://block", at: 999))
        XCTAssertEqual(NSPasteboard.general.changeCount, changeCount)
        XCTAssertFalse(coordinator.textView(view, clickedOnLink: URL(string: "https://example.com")!, at: 0))
    }
}

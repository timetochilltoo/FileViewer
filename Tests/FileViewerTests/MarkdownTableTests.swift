import AppKit
import XCTest
@testable import FileViewer

final class MarkdownTableTests: XCTestCase {
    func testAlignedRaggedAndSingleColumnTables() throws {
        let parsed = try XCTUnwrap(MarkdownTable.parse(startingAt: 0, in: [
            "| Name | Value | Note |", "| :--- | ---: | :---: |",
            "| A | 10 |", "| B | 20 | middle | extra |", "", "After"
        ]))
        XCTAssertEqual(parsed.table.alignments, [.left, .right, .center])
        XCTAssertEqual(parsed.table.rows, [["Name", "Value", "Note"], ["A", "10", ""], ["B", "20", "middle"]])
        XCTAssertEqual(parsed.nextIndex, 4)
        XCTAssertEqual(MarkdownTable.parse(startingAt: 0, in: ["| Name |", "| --- |", "| A |"] )?.table.rows, [["Name"], ["A"]])
    }

    func testEscapedPipesCodeSpansAndEmptyCells() {
        XCTAssertEqual(MarkdownTable.cells(#"| a\|b | `x|y` | |"#), ["a|b", "`x|y`", ""])
        XCTAssertEqual(MarkdownTable.cells(#"a | b\|"#), ["a", "b|"])
        XCTAssertEqual(MarkdownTable.cells(#"a\\|b"#), [#"a\"#, "b"])
        XCTAssertEqual(MarkdownTable.cells("|| a ||"), ["", "a", ""])
        XCTAssertNil(MarkdownTable.cells("ordinary paragraph"))
        XCTAssertNil(MarkdownTable.cells("`x|y`"))
    }

    func testInvalidSeparatorsAndNewBlocksAreNotSwallowed() {
        for separator in ["| | --- |", "| -- | --- |", "| :--: | --- |", "| -:- | --- |", "| --- |", "ordinary prose"] {
            XCTAssertNil(MarkdownTable.parse(startingAt: 0, in: ["| A | B |", separator]), separator)
        }
        for interrupt in ["# Heading | text", "> Quote | text", "```swift | info", "- item | text", "![image](a|b.png)", "After table"] {
            XCTAssertEqual(MarkdownTable.parse(startingAt: 0, in: ["A | B", "--- | ---", "one | two", interrupt])?.nextIndex, 3)
        }
        let blocks = MarkdownPreviewBlock.parse("```md\n| A | B |\n| --- | --- |\n```")
        XCTAssertFalse(blocks.contains { if case .table = $0.kind { return true }; return false })
    }

    @MainActor
    func testNativeCellsPreserveFormattingAlignmentAndSearchableText() throws {
        let markdown = "| Name | Amount | Status |\n| :--- | ---: | :---: |\n| **Alpha** | 10 | *Ready* |\n| Beta | 20 | `code` |"
        let rendered = MarkdownPreviewTextView.attributedPreview(markdown: markdown, searchText: "Alpha", searchMatchIndex: 0)
        XCTAssertTrue(rendered.string.contains("Alpha\n10\nReady"))
        XCTAssertFalse(rendered.string.contains("**Alpha**"))
        var cells: [NSTextTableBlock] = []
        rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle, let block = style.textBlocks.first as? NSTextTableBlock else { return }
            cells.append(block)
            let expected: NSTextAlignment = [.left, .right, .center][block.startingColumn]
            XCTAssertEqual(style.alignment, expected)
            XCTAssertEqual(block.table.numberOfColumns, 3)
            XCTAssertEqual(block.table.layoutAlgorithm, .fixedLayoutAlgorithm)
        }
        XCTAssertEqual(cells.count, 9)
        XCTAssertEqual(Set(cells.map { ObjectIdentifier($0.table) }).count, 1)
        let alpha = (rendered.string as NSString).range(of: "Alpha")
        XCTAssertNotNil(rendered.attribute(.backgroundColor, at: alpha.location, effectiveRange: nil))
        let font = try XCTUnwrap(rendered.attribute(.font, at: alpha.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }
}

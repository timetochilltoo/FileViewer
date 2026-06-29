import AppKit
import SwiftUI

struct MarkdownWorkspace: View {
    @ObservedObject var model: AppModel
    let document: MarkdownDocument

    var body: some View {
        Group {
            switch model.markdownMode {
            case .source:
                editorWithFormatting
            case .preview:
                previewWithFormatting
            case .split:
                HSplitView {
                    editorWithFormatting
                        .frame(minWidth: 240)
                    preview
                        .frame(minWidth: 240)
                }
            }
        }
    }

    private var editorWithFormatting: some View {
        VStack(spacing: 0) {
            formattingBar
            Divider()
            editor
        }
    }

    private var previewWithFormatting: some View {
        VStack(spacing: 0) {
            formattingBar
            Divider()
            preview
        }
    }

    private var formattingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                formatMenu

                Divider()
                    .frame(height: 20)

                ForEach(MarkdownFormatCommand.allCases, id: \.self) { command in
                    Button {
                        model.applyMarkdownFormat(command)
                    } label: {
                        Label(command.title, systemImage: command.systemImage)
                            .labelStyle(.iconOnly)
                    }
                    .help(command.helpText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var formatMenu: some View {
        Menu {
            formatMenuSection([.bold, .italic, .underline])
            Divider()
            formatMenuSection([.heading, .bulletList, .numberedList, .quote])
            Divider()
            formatMenuSection([.link, .code])
            Divider()
            formatMenuSection([.table, .taskList])
        } label: {
            Label("Format", systemImage: "textformat")
        }
        .menuStyle(.button)
        .help("Show Markdown formatting commands with text labels.")
    }

    @ViewBuilder
    private func formatMenuSection(_ commands: [MarkdownFormatCommand]) -> some View {
        ForEach(commands, id: \.self) { command in
            Button {
                model.applyMarkdownFormat(command)
            } label: {
                Label(command.title, systemImage: command.systemImage)
            }
            .help(command.helpText)
        }
    }

    private var editor: some View {
        MarkdownSourceEditor(text: Binding(
            get: { document.text },
            set: { model.updateMarkdown($0) }
        ), initialScrollY: model.markdownSourceScrollY, onFormatCommand: { command in
            model.applyMarkdownFormat(command)
        }, onScrollChanged: { scrollY in
            model.recordMarkdownSourceScrollY(scrollY)
        }) { textView in
            model.rememberMarkdownTextView(textView)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var preview: some View {
        MarkdownPreviewTextView(
            markdown: document.text,
            searchText: model.searchText,
            searchMatchIndex: model.searchMatchIndex,
            initialScrollY: model.markdownPreviewScrollY,
            onScrollChanged: { scrollY in
                model.recordMarkdownPreviewScrollY(scrollY)
            }
        ) { textView in
            model.rememberMarkdownPreviewTextView(textView)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var markdownBlocks: [MarkdownPreviewBlock] {
        MarkdownPreviewBlock.parse(document.text)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownPreviewBlock) -> some View {
        switch block.kind {
        case .blank:
            Spacer()
                .frame(height: 6)
        case .heading(let level, let text):
            Text(inlineAttributed(text))
                .font(headingFont(level))
                .padding(.top, level == 1 ? 10 : 6)
        case .paragraph(let text):
            Text(inlineAttributed(text))
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(inlineAttributed(text))
            }
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .foregroundStyle(.secondary)
                Text(inlineAttributed(text))
            }
        case .task(let checked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(checked ? "☑" : "☐")
                    .foregroundStyle(.secondary)
                Text(inlineAttributed(text))
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                Text(inlineAttributed(text))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case .code(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        case .table(let rows):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 12) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inlineAttributed(cell))
                                .font(rowIndex == 0 ? .body.weight(.semibold) : .body)
                        }
                    }
                    if rowIndex == 0 {
                        Divider()
                    }
                }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .largeTitle.weight(.bold)
        case 2: .title.weight(.bold)
        case 3: .title2.weight(.semibold)
        case 4: .title3.weight(.semibold)
        default: .headline
        }
    }

    private func inlineAttributed(_ markdown: String) -> AttributedString {
        let underlineProcessed = markdownByExtractingUnderlineMarkup(markdown)
        var attributed = (try? AttributedString(markdown: underlineProcessed.markdown)) ?? AttributedString(underlineProcessed.markdown)
        applyUnderlineRanges(underlineProcessed.underlinedTexts, to: &attributed)
        applySearchHighlight(to: &attributed)
        return attributed
    }

    private func markdownByExtractingUnderlineMarkup(_ markdown: String) -> (markdown: String, underlinedTexts: [String]) {
        var remaining = markdown[...]
        var output = ""
        var underlinedTexts: [String] = []

        while let openRange = remaining.range(of: "<u>"),
              let closeRange = remaining[openRange.upperBound...].range(of: "</u>") {
            output += remaining[..<openRange.lowerBound]
            let underlined = String(remaining[openRange.upperBound..<closeRange.lowerBound])
            output += underlined
            underlinedTexts.append(underlined)
            remaining = remaining[closeRange.upperBound...]
        }

        output += remaining
        return (output, underlinedTexts)
    }

    private func applyUnderlineRanges(_ underlinedTexts: [String], to attributed: inout AttributedString) {
        for underlinedText in underlinedTexts where !underlinedText.isEmpty {
            if let range = attributed.range(of: underlinedText) {
                attributed[range].underlineStyle = .single
            }
        }
    }

    private func applySearchHighlight(to attributed: inout AttributedString) {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: query, options: [.caseInsensitive]) {
            attributed[range].backgroundColor = .yellow.opacity(0.45)
            attributed[range].foregroundColor = .primary
            searchRange = range.upperBound..<attributed.endIndex
        }
    }
}

private struct MarkdownPreviewBlock: Identifiable {
    enum Kind {
        case blank
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(number: Int, text: String)
        case task(checked: Bool, text: String)
        case quote(String)
        case code(String)
        case table(rows: [[String]])
    }

    let id = UUID()
    let kind: Kind

    static func parse(_ markdown: String) -> [MarkdownPreviewBlock] {
        var blocks: [MarkdownPreviewBlock] = []
        var inCodeBlock = false
        var codeLines: [String] = []

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lineIndex = 0

        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.init(kind: .code(codeLines.joined(separator: "\n"))))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                lineIndex += 1
                continue
            }

            if inCodeBlock {
                codeLines.append(rawLine)
                lineIndex += 1
                continue
            }

            if let table = tableRows(startingAt: lineIndex, in: lines) {
                blocks.append(.init(kind: .table(rows: table.rows)))
                lineIndex = table.nextIndex
            } else if trimmed.isEmpty {
                blocks.append(.init(kind: .blank))
                lineIndex += 1
            } else if let heading = heading(from: trimmed) {
                blocks.append(.init(kind: .heading(level: heading.level, text: heading.text)))
                lineIndex += 1
            } else if let task = taskListText(from: trimmed) {
                blocks.append(.init(kind: .task(checked: task.checked, text: task.text)))
                lineIndex += 1
            } else if let bullet = unorderedListText(from: trimmed) {
                blocks.append(.init(kind: .bullet(bullet)))
                lineIndex += 1
            } else if let numbered = orderedListText(from: trimmed) {
                blocks.append(.init(kind: .numbered(number: numbered.number, text: numbered.text)))
                lineIndex += 1
            } else if trimmed.hasPrefix(">") {
                let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                blocks.append(.init(kind: .quote(text)))
                lineIndex += 1
            } else {
                blocks.append(.init(kind: .paragraph(rawLine)))
                lineIndex += 1
            }
        }

        if inCodeBlock {
            blocks.append(.init(kind: .code(codeLines.joined(separator: "\n"))))
        }

        return blocks.isEmpty ? [.init(kind: .blank)] : blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level),
              line.dropFirst(level).first?.isWhitespace == true else {
            return nil
        }
        let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func unorderedListText(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func taskListText(from line: String) -> (checked: Bool, text: String)? {
        for marker in ["- [ ] ", "* [ ] ", "+ [ ] "] where line.hasPrefix(marker) {
            return (false, String(line.dropFirst(marker.count)))
        }
        for marker in ["- [x] ", "- [X] ", "* [x] ", "* [X] ", "+ [x] ", "+ [X] "] where line.hasPrefix(marker) {
            return (true, String(line.dropFirst(marker.count)))
        }
        return nil
    }

    private static func orderedListText(from line: String) -> (number: Int, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let numberPart = line[..<dotIndex]
        guard let number = Int(numberPart),
              line.index(after: dotIndex) < line.endIndex,
              line[line.index(after: dotIndex)].isWhitespace else {
            return nil
        }
        return (number, line[line.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces))
    }

    private static func tableRows(startingAt index: Int, in lines: [String]) -> (rows: [[String]], nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = tableCells(from: lines[index])
        let separator = tableCells(from: lines[index + 1])
        guard header.count >= 2,
              separator.count == header.count,
              separator.allSatisfy({ $0.replacingOccurrences(of: ":", with: "").allSatisfy { $0 == "-" } }) else {
            return nil
        }

        var rows = [header]
        var nextIndex = index + 2
        while nextIndex < lines.count {
            let cells = tableCells(from: lines[nextIndex])
            guard cells.count >= 2 else { break }
            rows.append(cells)
            nextIndex += 1
        }
        return (rows, nextIndex)
    }

    private static func tableCells(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return [] }
        let withoutOuterPipes = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return withoutOuterPipes
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct MarkdownPreviewTextView: NSViewRepresentable {
    let markdown: String
    let searchText: String
    let searchMatchIndex: Int
    let initialScrollY: Double
    let onScrollChanged: (Double) -> Void
    let onTextViewReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialScrollY: initialScrollY,
            onScrollChanged: onScrollChanged,
            onTextViewReady: onTextViewReady
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(Self.attributedPreview(
            markdown: markdown,
            searchText: searchText,
            searchMatchIndex: searchMatchIndex
        ))

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollView = scrollView
        context.coordinator.startObservingScroll()
        context.coordinator.textView = textView
        onTextViewReady(textView)
        DispatchQueue.main.async {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                context.coordinator.restoreInitialScrollIfNeeded()
            } else {
                Self.scrollToSearchMatch(in: textView, searchText: searchText, searchMatchIndex: searchMatchIndex)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onTextViewReady = onTextViewReady
        context.coordinator.onScrollChanged = onScrollChanged
        let selectedRange = textView.selectedRange()
        textView.textStorage?.setAttributedString(Self.attributedPreview(
            markdown: markdown,
            searchText: searchText,
            searchMatchIndex: searchMatchIndex
        ))
        let textLength = (textView.string as NSString).length
        let safeLocation = min(selectedRange.location, textLength)
        let safeLength = min(selectedRange.length, max(0, textLength - safeLocation))
        textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
        DispatchQueue.main.async {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                context.coordinator.restoreInitialScrollIfNeeded()
            } else {
                Self.scrollToSearchMatch(in: textView, searchText: searchText, searchMatchIndex: searchMatchIndex)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let initialScrollY: Double
        var onScrollChanged: (Double) -> Void
        var onTextViewReady: (NSTextView) -> Void
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var didRestoreInitialScroll = false
        private var isObservingScroll = false

        init(
            initialScrollY: Double,
            onScrollChanged: @escaping (Double) -> Void,
            onTextViewReady: @escaping (NSTextView) -> Void
        ) {
            self.initialScrollY = initialScrollY
            self.onScrollChanged = onScrollChanged
            self.onTextViewReady = onTextViewReady
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(syncCurrentScroll),
                name: .markdownSyncCurrentState,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func startObservingScroll() {
            guard !isObservingScroll,
                  let clipView = scrollView?.contentView else { return }
            isObservingScroll = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        func restoreInitialScrollIfNeeded() {
            guard !didRestoreInitialScroll,
                  let scrollView else { return }
            didRestoreInitialScroll = true
            Self.scroll(scrollView, toY: initialScrollY)
            publishCurrentScroll()
        }

        private func publishCurrentScroll() {
            guard let scrollView else { return }
            onScrollChanged(Double(scrollView.contentView.bounds.origin.y))
        }

        @objc private func syncCurrentScroll() {
            publishCurrentScroll()
        }

        @objc private func scrollBoundsDidChange() {
            publishCurrentScroll()
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                onTextViewReady(textView)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                onTextViewReady(textView)
            }
        }

        private static func scroll(_ scrollView: NSScrollView, toY scrollY: Double) {
            guard let documentView = scrollView.documentView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let maxY = max(0, documentView.bounds.height - visibleHeight)
            let safeY = min(max(0, CGFloat(scrollY)), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: safeY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private static func attributedPreview(
        markdown: String,
        searchText: String,
        searchMatchIndex: Int
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.lineBreakMode = .byWordWrapping

        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize + 2)
        let secondaryColor = NSColor.secondaryLabelColor

        for block in MarkdownPreviewBlock.parse(markdown) {
            switch block.kind {
            case .blank:
                output.append(NSAttributedString(string: "\n"))
            case .heading(let level, let text):
                appendInline(
                    text,
                    to: output,
                    baseFont: headingFont(level),
                    color: .labelColor,
                    paragraphStyle: paragraphStyle
                )
                output.append(NSAttributedString(string: "\n\n"))
            case .paragraph(let text):
                appendInline(
                    text,
                    to: output,
                    baseFont: bodyFont,
                    color: .labelColor,
                    paragraphStyle: paragraphStyle
                )
                output.append(NSAttributedString(string: "\n\n"))
            case .bullet(let text):
                output.append(NSAttributedString(
                    string: "• ",
                    attributes: baseAttributes(font: bodyFont, color: secondaryColor, paragraphStyle: paragraphStyle)
                ))
                appendInline(
                    text,
                    to: output,
                    baseFont: bodyFont,
                    color: .labelColor,
                    paragraphStyle: paragraphStyle
                )
                output.append(NSAttributedString(string: "\n"))
            case .numbered(let number, let text):
                output.append(NSAttributedString(
                    string: "\(number). ",
                    attributes: baseAttributes(font: bodyFont, color: secondaryColor, paragraphStyle: paragraphStyle)
                ))
                appendInline(
                    text,
                    to: output,
                    baseFont: bodyFont,
                    color: .labelColor,
                    paragraphStyle: paragraphStyle
                )
                output.append(NSAttributedString(string: "\n"))
            case .task(let checked, let text):
                output.append(NSAttributedString(
                    string: checked ? "☑ " : "☐ ",
                    attributes: baseAttributes(font: bodyFont, color: secondaryColor, paragraphStyle: paragraphStyle)
                ))
                appendInline(
                    text,
                    to: output,
                    baseFont: bodyFont,
                    color: .labelColor,
                    paragraphStyle: paragraphStyle
                )
                output.append(NSAttributedString(string: "\n"))
            case .quote(let text):
                output.append(NSAttributedString(
                    string: "❝ ",
                    attributes: baseAttributes(font: bodyFont, color: secondaryColor, paragraphStyle: paragraphStyle)
                ))
                appendInline(
                    text,
                    to: output,
                    baseFont: bodyFont,
                    color: secondaryColor,
                    paragraphStyle: paragraphStyle
                )
                output.append(NSAttributedString(string: "\n\n"))
            case .code(let text):
                output.append(NSAttributedString(
                    string: text + "\n\n",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                        .foregroundColor: NSColor.labelColor,
                        .backgroundColor: NSColor.textBackgroundColor,
                        .paragraphStyle: paragraphStyle
                    ]
                ))
            case .table(let rows):
                appendTable(
                    rows,
                    to: output,
                    bodyFont: bodyFont,
                    paragraphStyle: paragraphStyle
                )
            }
        }

        applySearchHighlight(searchText, currentIndex: searchMatchIndex, to: output)
        return output
    }

    private static func appendTable(
        _ rows: [[String]],
        to output: NSMutableAttributedString,
        bodyFont: NSFont,
        paragraphStyle: NSParagraphStyle
    ) {
        guard !rows.isEmpty else { return }
        let columnCount = rows.map(\.count).max() ?? 0
        let paddedRows = rows.map { row in
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }
        let widths = (0..<columnCount).map { column in
            paddedRows.map { $0[column].count }.max() ?? 0
        }
        let tableFont = NSFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
        let headerFont = NSFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .semibold)

        for (rowIndex, row) in paddedRows.enumerated() {
            let line = row.enumerated()
                .map { column, cell in
                    cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
                }
                .joined(separator: "   ")
            output.append(NSAttributedString(
                string: line + "\n",
                attributes: baseAttributes(
                    font: rowIndex == 0 ? headerFont : tableFont,
                    color: .labelColor,
                    paragraphStyle: paragraphStyle
                )
            ))

            if rowIndex == 0 {
                let divider = widths
                    .map { String(repeating: "─", count: max($0, 3)) }
                    .joined(separator: "   ")
                output.append(NSAttributedString(
                    string: divider + "\n",
                    attributes: baseAttributes(
                        font: tableFont,
                        color: .secondaryLabelColor,
                        paragraphStyle: paragraphStyle
                    )
                ))
            }
        }

        output.append(NSAttributedString(string: "\n"))
    }

    private static func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: .boldSystemFont(ofSize: 30)
        case 2: .boldSystemFont(ofSize: 24)
        case 3: .boldSystemFont(ofSize: 21)
        case 4: .boldSystemFont(ofSize: 18)
        default: .boldSystemFont(ofSize: NSFont.systemFontSize + 2)
        }
    }

    private static func appendInline(
        _ markdown: String,
        to output: NSMutableAttributedString,
        baseFont: NSFont,
        color: NSColor,
        paragraphStyle: NSParagraphStyle
    ) {
        var remaining = markdown[...]
        while !remaining.isEmpty {
            if remaining.hasPrefix("**"),
               let closeRange = remaining.dropFirst(2).range(of: "**") {
                let inner = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<closeRange.lowerBound])
                appendPlain(
                    inner,
                    to: output,
                    font: NSFont.boldSystemFont(ofSize: baseFont.pointSize),
                    color: color,
                    paragraphStyle: paragraphStyle
                )
                remaining = remaining[closeRange.upperBound...]
            } else if remaining.hasPrefix("<u>"),
                      let closeRange = remaining.dropFirst(3).range(of: "</u>") {
                let inner = String(remaining[remaining.index(remaining.startIndex, offsetBy: 3)..<closeRange.lowerBound])
                appendPlain(
                    inner,
                    to: output,
                    font: baseFont,
                    color: color,
                    paragraphStyle: paragraphStyle,
                    underline: true
                )
                remaining = remaining[closeRange.upperBound...]
            } else if remaining.hasPrefix("*"),
                      let closeRange = remaining.dropFirst().range(of: "*") {
                let inner = String(remaining[remaining.index(after: remaining.startIndex)..<closeRange.lowerBound])
                appendPlain(
                    inner,
                    to: output,
                    font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask),
                    color: color,
                    paragraphStyle: paragraphStyle
                )
                remaining = remaining[closeRange.upperBound...]
            } else if remaining.hasPrefix("`"),
                      let closeRange = remaining.dropFirst().range(of: "`") {
                let inner = String(remaining[remaining.index(after: remaining.startIndex)..<closeRange.lowerBound])
                appendPlain(
                    inner,
                    to: output,
                    font: .monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
                    color: color,
                    paragraphStyle: paragraphStyle
                )
                remaining = remaining[closeRange.upperBound...]
            } else {
                appendPlain(
                    String(remaining.removeFirst()),
                    to: output,
                    font: baseFont,
                    color: color,
                    paragraphStyle: paragraphStyle
                )
            }
        }
    }

    private static func appendPlain(
        _ text: String,
        to output: NSMutableAttributedString,
        font: NSFont,
        color: NSColor,
        paragraphStyle: NSParagraphStyle,
        underline: Bool = false
    ) {
        var attributes = baseAttributes(font: font, color: color, paragraphStyle: paragraphStyle)
        if underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        output.append(NSAttributedString(string: text, attributes: attributes))
    }

    private static func baseAttributes(
        font: NSFont,
        color: NSColor,
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func applySearchHighlight(
        _ searchText: String,
        currentIndex: Int,
        to output: NSMutableAttributedString
    ) {
        let ranges = searchRanges(in: output.string, searchText: searchText)
        guard !ranges.isEmpty else { return }

        let selectedIndex = min(max(0, currentIndex), ranges.count - 1)
        for (index, foundRange) in ranges.enumerated() {
            output.addAttributes(
                [
                    .backgroundColor: index == selectedIndex
                        ? NSColor.systemOrange.withAlphaComponent(0.75)
                        : NSColor.systemYellow.withAlphaComponent(0.45),
                    .foregroundColor: NSColor.labelColor
                ],
                range: foundRange
            )
        }
    }

    private static func searchRanges(in text: String, searchText: String) -> [NSRange] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let backingString = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: backingString.length)
        while true {
            let foundRange = backingString.range(of: query, options: [.caseInsensitive], range: searchRange)
            guard foundRange.location != NSNotFound else { break }
            ranges.append(foundRange)
            let nextLocation = foundRange.location + foundRange.length
            searchRange = NSRange(location: nextLocation, length: backingString.length - nextLocation)
        }
        return ranges
    }

    private static func scrollToSearchMatch(in textView: NSTextView, searchText: String, searchMatchIndex: Int) {
        let ranges = searchRanges(in: textView.string, searchText: searchText)
        guard !ranges.isEmpty else { return }
        let selectedIndex = min(max(0, searchMatchIndex), ranges.count - 1)
        textView.scrollRangeToVisible(ranges[selectedIndex])
    }
}

private struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let initialScrollY: Double
    let onFormatCommand: (MarkdownFormatCommand) -> Void
    let onScrollChanged: (Double) -> Void
    let onTextViewReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            initialScrollY: initialScrollY,
            onFormatCommand: onFormatCommand,
            onScrollChanged: onScrollChanged,
            onTextViewReady: onTextViewReady
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.string = text
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.menu = context.coordinator.contextMenu()

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollView = scrollView
        context.coordinator.startObservingScroll()
        context.coordinator.textView = textView
        onTextViewReady(textView)
        DispatchQueue.main.async {
            context.coordinator.restoreInitialScrollIfNeeded()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.onFormatCommand = onFormatCommand
        context.coordinator.onScrollChanged = onScrollChanged
        context.coordinator.onTextViewReady = onTextViewReady
        textView.menu = context.coordinator.contextMenu()
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selectedRange.location, (text as NSString).length),
                length: 0
            ))
        }
        onTextViewReady(textView)
        DispatchQueue.main.async {
            context.coordinator.restoreInitialScrollIfNeeded()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let initialScrollY: Double
        var onFormatCommand: (MarkdownFormatCommand) -> Void
        var onScrollChanged: (Double) -> Void
        var onTextViewReady: (NSTextView) -> Void
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var didRestoreInitialScroll = false
        private var isObservingScroll = false

        init(
            text: Binding<String>,
            initialScrollY: Double,
            onFormatCommand: @escaping (MarkdownFormatCommand) -> Void,
            onScrollChanged: @escaping (Double) -> Void,
            onTextViewReady: @escaping (NSTextView) -> Void
        ) {
            self.text = text
            self.initialScrollY = initialScrollY
            self.onFormatCommand = onFormatCommand
            self.onScrollChanged = onScrollChanged
            self.onTextViewReady = onTextViewReady
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(syncCurrentScroll),
                name: .markdownSyncCurrentState,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func startObservingScroll() {
            guard !isObservingScroll,
                  let clipView = scrollView?.contentView else { return }
            isObservingScroll = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        func restoreInitialScrollIfNeeded() {
            guard !didRestoreInitialScroll,
                  let scrollView else { return }
            didRestoreInitialScroll = true
            Self.scroll(scrollView, toY: initialScrollY)
            publishCurrentScroll()
        }

        private func publishCurrentScroll() {
            guard let scrollView else { return }
            onScrollChanged(Double(scrollView.contentView.bounds.origin.y))
        }

        @objc private func syncCurrentScroll() {
            publishCurrentScroll()
        }

        @objc private func scrollBoundsDidChange() {
            publishCurrentScroll()
        }

        private static func scroll(_ scrollView: NSScrollView, toY scrollY: Double) {
            guard let documentView = scrollView.documentView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let maxY = max(0, documentView.bounds.height - visibleHeight)
            let safeY = min(max(0, CGFloat(scrollY)), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: safeY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func contextMenu() -> NSMenu {
            let menu = NSMenu()
            for command in MarkdownFormatCommand.allCases {
                let item = NSMenuItem(
                    title: command.title,
                    action: #selector(applyMarkdownFormatFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = command.rawValue
                menu.addItem(item)
            }

            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
            return menu
        }

        @objc private func applyMarkdownFormatFromMenu(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let command = MarkdownFormatCommand(rawValue: rawValue) else {
                return
            }
            if let textView {
                onTextViewReady(textView)
            }
            onFormatCommand(command)
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                onTextViewReady(textView)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                onTextViewReady(textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onTextViewReady(textView)
            text.wrappedValue = textView.string
        }
    }
}

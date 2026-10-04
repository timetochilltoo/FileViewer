import AppKit
import SwiftUI

private func markdownSearchRanges(in text: String, query: String) -> [NSRange] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return [] }

    let backingString = text as NSString
    var ranges: [NSRange] = []
    var searchRange = NSRange(location: 0, length: backingString.length)
    while true {
        let foundRange = backingString.range(of: normalizedQuery, options: [.caseInsensitive], range: searchRange)
        guard foundRange.location != NSNotFound else { break }
        ranges.append(foundRange)

        let nextLocation = foundRange.location + foundRange.length
        searchRange = NSRange(location: nextLocation, length: backingString.length - nextLocation)
    }
    return ranges
}

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
        .contextMenu {
            Button("Ask AI About Selection…", systemImage: "sparkles") {
                model.askAIAboutSelection()
            }
            .disabled(!model.canAskAIAboutSelection)

            Divider()

            Button("Add to Library", systemImage: "books.vertical") {
                model.addCurrentDocumentToLibrary()
            }
            .disabled(!model.canAddCurrentDocumentToLibrary)

            if let url = model.document?.url {
                LibraryTagActions(model: model, url: url)
            }

            Button("Copy to Library Folder…", systemImage: "doc.on.doc") {
                model.copyCurrentDocumentToLibraryFolder()
            }
            .disabled(!model.canCopyCurrentDocumentToLibraryFolder)
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
        ), initialScrollY: model.markdownSourceScrollY,
           initialVisibleLocation: model.markdownSourceVisibleLocation,
           focusRequest: model.markdownEditorFocusRequest,
           searchText: model.searchText,
           searchMatchIndex: model.searchMatchIndex,
           searchNavigationRequestID: model.searchNavigationRequestID,
           onFormatCommand: { command in
            model.applyMarkdownFormat(command)
        }, onAskAIAboutSelection: { selection in
            model.askAIAboutSelection(markdownSelection: selection)
        }, onViewportChanged: { scrollY, visibleLocation in
            model.recordMarkdownSourceViewport(scrollY: scrollY, visibleLocation: visibleLocation)
        }) { textView in
            model.rememberMarkdownTextView(textView)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var preview: some View {
        MarkdownPreviewTextView(
            markdown: document.text,
            documentURL: document.url,
            searchText: model.searchText,
            searchMatchIndex: model.searchMatchIndex,
            initialScrollY: model.markdownPreviewScrollY,
            initialVisibleLocation: model.markdownPreviewVisibleLocation,
            onViewportChanged: { scrollY, visibleLocation in
                model.recordMarkdownPreviewViewport(scrollY: scrollY, visibleLocation: visibleLocation)
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
        case .image(let reference):
            Text(reference.alt)
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
        case .code(let code):
            Text(code.text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        case .table(let table):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
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

struct MarkdownPreviewBlock: Identifiable {
    struct Code: Equatable {
        let text: String
        let language: String
    }
    enum Kind {
        case blank
        case heading(level: Int, text: String)
        case paragraph(String)
        case image(MarkdownLocalImage)
        case bullet(String)
        case numbered(number: Int, text: String)
        case task(checked: Bool, text: String)
        case quote(String)
        case code(Code)
        case table(MarkdownTable)
    }

    let id = UUID()
    let kind: Kind
    var sourceLocation = 0

    static func parse(_ markdown: String) -> [MarkdownPreviewBlock] {
        var blocks: [MarkdownPreviewBlock] = []
        var fence: MarkdownCodeFence?
        var codeLines: [String] = []

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lineIndex = 0
        var offsets: [Int] = []
        var offset = 0
        for line in lines { offsets.append(offset); offset += (line as NSString).length + 1 }

        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if let activeFence = fence {
                if activeFence.closes(rawLine) {
                    blocks.append(.init(kind: .code(Code(text: codeLines.joined(separator: "\n"), language: activeFence.language))))
                    codeLines = []
                    fence = nil
                } else {
                    codeLines.append(rawLine)
                }
                lineIndex += 1
                continue
            }

            if let openingFence = MarkdownCodeFence(opening: rawLine) {
                fence = openingFence
                lineIndex += 1
                continue
            }

            if let table = MarkdownTable.parse(startingAt: lineIndex, in: lines) {
                blocks.append(.init(kind: .table(table.table)))
                lineIndex = table.nextIndex
            } else if trimmed.isEmpty {
                blocks.append(.init(kind: .blank))
                lineIndex += 1
            } else if let image = MarkdownLocalImage.parse(rawLine) {
                blocks.append(.init(kind: .image(image)))
                lineIndex += 1
            } else if let heading = heading(from: trimmed) {
                blocks.append(.init(kind: .heading(level: heading.level, text: heading.text), sourceLocation: offsets[lineIndex]))
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

        if let fence {
            blocks.append(.init(kind: .code(Code(text: codeLines.joined(separator: "\n"), language: fence.language))))
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


}

struct MarkdownPreviewTextView: NSViewRepresentable {
    let markdown: String
    let documentURL: URL?
    let searchText: String
    let searchMatchIndex: Int
    let initialScrollY: Double
    let initialVisibleLocation: Int
    let onViewportChanged: (Double, Int) -> Void
    let onTextViewReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialScrollY: initialScrollY,
            initialVisibleLocation: initialVisibleLocation,
            onViewportChanged: onViewportChanged,
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
        _ = context.coordinator.shouldRender(markdown: markdown, searchText: searchText, searchMatchIndex: searchMatchIndex, documentURL: documentURL)
        textView.textStorage?.setAttributedString(Self.attributedPreview(
            markdown: markdown,
            searchText: searchText,
            searchMatchIndex: searchMatchIndex,
            documentURL: documentURL
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
        context.coordinator.onViewportChanged = onViewportChanged
        onTextViewReady(textView)
        let rendered = context.coordinator.shouldRender(markdown: markdown, searchText: searchText, searchMatchIndex: searchMatchIndex, documentURL: documentURL)
        if rendered {
            let selectedRange = textView.selectedRange()
            context.coordinator.isRendering = true
            textView.textStorage?.setAttributedString(Self.attributedPreview(
                markdown: markdown,
                searchText: searchText,
                searchMatchIndex: searchMatchIndex,
                documentURL: documentURL
            ))
            let textLength = (textView.string as NSString).length
            let safeLocation = min(selectedRange.location, textLength)
            let safeLength = min(selectedRange.length, max(0, textLength - safeLocation))
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            context.coordinator.isRendering = false
        }
        DispatchQueue.main.async {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                context.coordinator.restoreInitialScrollIfNeeded()
            } else if rendered {
                Self.scrollToSearchMatch(in: textView, searchText: searchText, searchMatchIndex: searchMatchIndex)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let initialScrollY: Double
        let initialVisibleLocation: Int
        var onViewportChanged: (Double, Int) -> Void
        var onTextViewReady: (NSTextView) -> Void
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var didRestoreInitialScroll = false
        private var restoreAttempts = 0
        private var isObservingScroll = false
        var isRendering = false
        private var renderedMarkdown: String?
        private var renderedSearch = ""
        private var renderedMatch = 0
        private var renderedDocumentURL: URL?

        func shouldRender(markdown: String, searchText: String, searchMatchIndex: Int, documentURL: URL? = nil) -> Bool {
            guard renderedMarkdown != markdown || renderedSearch != searchText || renderedMatch != searchMatchIndex || renderedDocumentURL != documentURL else { return false }
            renderedMarkdown = markdown
            renderedSearch = searchText
            renderedMatch = searchMatchIndex
            renderedDocumentURL = documentURL
            return true
        }

        init(
            initialScrollY: Double,
            initialVisibleLocation: Int,
            onViewportChanged: @escaping (Double, Int) -> Void,
            onTextViewReady: @escaping (NSTextView) -> Void
        ) {
            self.initialScrollY = initialScrollY
            self.initialVisibleLocation = max(0, initialVisibleLocation)
            self.onViewportChanged = onViewportChanged
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

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Only an attributed action generated by this renderer can copy code.
            // A document-supplied URL with the same scheme must not launch externally.
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard url?.scheme == "fileviewer-copy-code" else { return false }
            guard let storage = textView.textStorage, charIndex >= 0, charIndex < storage.length,
                  let code = storage.attribute(.fileViewerCodeContent, at: charIndex, effectiveRange: nil) as? String else { return true }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            return true
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
            let didScroll = Self.restore(
                scrollView,
                textView: textView,
                toY: initialScrollY,
                visibleLocation: initialVisibleLocation
            )
            if didScroll || initialScrollY <= 0 {
                didRestoreInitialScroll = true
            } else if restoreAttempts < 12 {
                restoreAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.restoreInitialScrollIfNeeded()
                }
            } else {
                didRestoreInitialScroll = true
            }
            publishCurrentScroll()
        }

        private func publishCurrentScroll() {
            guard let scrollView else { return }
            onViewportChanged(
                Double(scrollView.contentView.bounds.origin.y),
                Self.visibleCharacterLocation(in: scrollView, textView: textView)
            )
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
            guard !isRendering else { return }
            if let textView = notification.object as? NSTextView {
                onTextViewReady(textView)
            }
        }

        private static func restore(
            _ scrollView: NSScrollView,
            textView: NSTextView?,
            toY scrollY: Double,
            visibleLocation: Int
        ) -> Bool {
            guard let documentView = scrollView.documentView else { return false }
            documentView.layoutSubtreeIfNeeded()
            if let textView, visibleLocation > 0, textView.string.count > 0 {
                return scrollToCharacterLocation(
                    visibleLocation,
                    in: scrollView,
                    textView: textView
                )
            }
            let visibleHeight = scrollView.contentView.bounds.height
            let maxY = max(0, documentView.bounds.height - visibleHeight)
            guard maxY > 0 || scrollY <= 0 else { return false }
            let safeY = min(max(0, CGFloat(scrollY)), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: safeY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return abs(scrollView.contentView.bounds.origin.y - safeY) <= 1 || safeY == 0
        }

        private static func visibleCharacterLocation(in scrollView: NSScrollView, textView: NSTextView?) -> Int {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return 0 }
            let containerOrigin = textView.textContainerOrigin
            let visibleRect = scrollView.contentView.documentVisibleRect.offsetBy(
                dx: -containerOrigin.x,
                dy: -containerOrigin.y
            )
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            return characterRange.location == NSNotFound ? 0 : characterRange.location
        }

        private static func scrollToCharacterLocation(
            _ location: Int,
            in scrollView: NSScrollView,
            textView: NSTextView
        ) -> Bool {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let documentView = scrollView.documentView else { return false }
            layoutManager.ensureLayout(for: textContainer)
            let textLength = (textView.string as NSString).length
            let safeLocation = min(max(0, location), max(0, textLength))
            let glyphIndex = safeLocation < textLength
                ? layoutManager.glyphIndexForCharacter(at: safeLocation)
                : max(0, layoutManager.numberOfGlyphs - 1)
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: min(1, max(0, layoutManager.numberOfGlyphs - glyphIndex))),
                in: textContainer
            )
            guard glyphRect.origin.y.isFinite else { return false }
            let containerOrigin = textView.textContainerOrigin
            let visibleHeight = scrollView.contentView.bounds.height
            let maxY = max(0, documentView.bounds.height - visibleHeight)
            let targetY = min(max(0, glyphRect.origin.y + containerOrigin.y), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return abs(scrollView.contentView.bounds.origin.y - targetY) <= 1 || targetY == 0
        }
    }

    static func attributedPreview(
        markdown: String,
        searchText: String,
        searchMatchIndex: Int,
        documentURL: URL? = nil
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.lineBreakMode = .byWordWrapping

        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize + 2)
        let secondaryColor = NSColor.secondaryLabelColor
        var imageBudget = 40 * 1024 * 1024
        var imageCount = 0

        for block in MarkdownPreviewBlock.parse(markdown) {
            switch block.kind {
            case .blank:
                output.append(NSAttributedString(string: "\n"))
            case .heading(let level, let text):
                let headingStart = output.length
                appendInline(
                    text,
                    to: output,
                    baseFont: headingFont(level),
                    color: .labelColor,
                    paragraphStyle: paragraphStyle
                )
                output.append(NSAttributedString(string: "\n\n"))
                output.addAttribute(.fileViewerHeadingLocation, value: block.sourceLocation, range: NSRange(location: headingStart, length: output.length - headingStart))
            case .paragraph(let text):
                appendInline(
                    text,
                    to: output,
                    baseFont: bodyFont,
                    color: .labelColor,
                    paragraphStyle: paragraphStyle
                )
                output.append(NSAttributedString(string: "\n\n"))
            case .image(let reference):
                imageCount += 1
                if imageCount <= 20, let image = MarkdownImageLoader.load(reference, documentURL: documentURL, remainingBytes: &imageBudget) {
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = MarkdownImageCell(imageCell: image)
                    output.append(NSAttributedString(attachment: attachment))
                    output.append(NSAttributedString(string: "\n"))
                    if !reference.alt.isEmpty {
                        output.append(NSAttributedString(string: reference.alt + "\n", attributes: baseAttributes(font: .systemFont(ofSize: 12), color: secondaryColor, paragraphStyle: paragraphStyle)))
                    }
                } else {
                    let explanation = documentURL == nil ? "Save this Markdown file to load local images" : "Image unavailable or blocked"
                    let label = reference.alt.isEmpty ? "Image" : reference.alt
                    output.append(NSAttributedString(string: "[\(label) — \(explanation)]\n", attributes: baseAttributes(font: bodyFont, color: secondaryColor, paragraphStyle: paragraphStyle)))
                }
                output.append(NSAttributedString(string: "\n"))
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
            case .code(let code):
                let headerStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                headerStyle.paragraphSpacing = 4
                output.append(NSAttributedString(
                    string: (code.language.isEmpty ? "Code" : code.language) + "    ",
                    attributes: baseAttributes(font: .systemFont(ofSize: 12, weight: .semibold), color: secondaryColor, paragraphStyle: headerStyle)
                ))
                output.append(NSAttributedString(string: "Copy Code", attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .link: URL(string: "fileviewer-copy-code://block")!,
                    .fileViewerCodeContent: code.text,
                    .paragraphStyle: headerStyle
                ]))
                output.append(NSAttributedString(string: "\n"))
                let codeStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                codeStyle.lineSpacing = 2
                output.append(NSAttributedString(
                    string: code.text + "\n\n",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                        .foregroundColor: NSColor.labelColor,
                        .backgroundColor: NSColor.textBackgroundColor,
                        .paragraphStyle: codeStyle
                    ]
                ))
            case .table(let table):
                appendTable(
                    table,
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
        _ markdownTable: MarkdownTable,
        to output: NSMutableAttributedString,
        bodyFont: NSFont,
        paragraphStyle: NSParagraphStyle
    ) {
        let columns = markdownTable.alignments.count
        guard columns > 0 else { return }
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true
        table.setValue(100, type: .percentageValueType, for: .width)
        for (rowIndex, row) in markdownTable.rows.enumerated() {
            for (column, text) in row.enumerated() {
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setValue(100 / CGFloat(columns), type: .percentageValueType, for: .width)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                block.backgroundColor = rowIndex == 0 ? NSColor.labelColor.withAlphaComponent(0.06) : .textBackgroundColor
                block.verticalAlignment = .top
                let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                style.textBlocks = [block]
                style.paragraphSpacing = 0
                style.lineSpacing = 2
                switch markdownTable.alignments[column] {
                case .left: style.alignment = .left
                case .center: style.alignment = .center
                case .right: style.alignment = .right
                }
                let start = output.length
                let font = rowIndex == 0 ? NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold) : bodyFont
                appendInline(text, to: output, baseFont: font, color: .labelColor, paragraphStyle: style)
                output.append(NSAttributedString(string: "\n", attributes: baseAttributes(font: font, color: .labelColor, paragraphStyle: style)))
                // Include empty cells and every inline run in the same native table block.
                output.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: output.length - start))
            }
        }
        output.append(NSAttributedString(string: "\n", attributes: baseAttributes(font: bodyFont, color: .labelColor, paragraphStyle: paragraphStyle)))
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
        let ranges = markdownSearchRanges(in: output.string, query: searchText)
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

    private static func scrollToSearchMatch(in textView: NSTextView, searchText: String, searchMatchIndex: Int) {
        let ranges = markdownSearchRanges(in: textView.string, query: searchText)
        guard !ranges.isEmpty else { return }
        let selectedIndex = min(max(0, searchMatchIndex), ranges.count - 1)
        textView.scrollRangeToVisible(ranges[selectedIndex])
    }
}

private struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let initialScrollY: Double
    let initialVisibleLocation: Int
    let focusRequest: UUID
    let searchText: String
    let searchMatchIndex: Int
    let searchNavigationRequestID: UUID
    let onFormatCommand: (MarkdownFormatCommand) -> Void
    let onAskAIAboutSelection: (String?) -> Void
    let onViewportChanged: (Double, Int) -> Void
    let onTextViewReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            initialScrollY: initialScrollY,
            initialVisibleLocation: initialVisibleLocation,
            focusRequest: focusRequest,
            searchText: searchText,
            searchMatchIndex: searchMatchIndex,
            searchNavigationRequestID: searchNavigationRequestID,
            onFormatCommand: onFormatCommand,
            onAskAIAboutSelection: onAskAIAboutSelection,
            onViewportChanged: onViewportChanged,
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
            context.coordinator.applySearch(forceScroll: true)
            context.coordinator.focusEditorIfRequested()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.focusRequest = focusRequest
        context.coordinator.searchText = searchText
        context.coordinator.searchMatchIndex = searchMatchIndex
        context.coordinator.searchNavigationRequestID = searchNavigationRequestID
        context.coordinator.onFormatCommand = onFormatCommand
        context.coordinator.onAskAIAboutSelection = onAskAIAboutSelection
        context.coordinator.onViewportChanged = onViewportChanged
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
        context.coordinator.applySearch()
        DispatchQueue.main.async {
            context.coordinator.restoreInitialScrollIfNeeded()
            context.coordinator.applySearch()
            context.coordinator.focusEditorIfRequested()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let initialScrollY: Double
        let initialVisibleLocation: Int
        var focusRequest: UUID
        var searchText: String
        var searchMatchIndex: Int
        var searchNavigationRequestID: UUID
        var onFormatCommand: (MarkdownFormatCommand) -> Void
        var onAskAIAboutSelection: (String?) -> Void
        var onViewportChanged: (Double, Int) -> Void
        var onTextViewReady: (NSTextView) -> Void
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var didRestoreInitialScroll = false
        private var restoreAttempts = 0
        private var isObservingScroll = false
        private var handledFocusRequest: UUID?
        private var appliedSearchText = ""
        private var appliedSearchNavigationRequestID: UUID?

        init(
            text: Binding<String>,
            initialScrollY: Double,
            initialVisibleLocation: Int,
            focusRequest: UUID,
            searchText: String,
            searchMatchIndex: Int,
            searchNavigationRequestID: UUID,
            onFormatCommand: @escaping (MarkdownFormatCommand) -> Void,
            onAskAIAboutSelection: @escaping (String?) -> Void,
            onViewportChanged: @escaping (Double, Int) -> Void,
            onTextViewReady: @escaping (NSTextView) -> Void
        ) {
            self.text = text
            self.initialScrollY = initialScrollY
            self.initialVisibleLocation = max(0, initialVisibleLocation)
            self.focusRequest = focusRequest
            self.searchText = searchText
            self.searchMatchIndex = searchMatchIndex
            self.searchNavigationRequestID = searchNavigationRequestID
            self.onFormatCommand = onFormatCommand
            self.onAskAIAboutSelection = onAskAIAboutSelection
            self.onViewportChanged = onViewportChanged
            self.onTextViewReady = onTextViewReady
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(syncCurrentScroll),
                name: .markdownSyncCurrentState,
                object: nil
            )
        }

        func applySearch(forceScroll: Bool = false) {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchChanged = query != appliedSearchText
            let navigationChanged = searchNavigationRequestID != appliedSearchNavigationRequestID
            let shouldScroll = forceScroll || searchChanged || navigationChanged
            let textLength = (textView.string as NSString).length

            layoutManager.ensureLayout(for: textContainer)
            if textLength > 0 {
                layoutManager.removeTemporaryAttribute(
                    .backgroundColor,
                    forCharacterRange: NSRange(location: 0, length: textLength)
                )
            }

            let ranges = markdownSearchRanges(in: textView.string, query: query)
            if !ranges.isEmpty {
                let selectedIndex = min(max(0, searchMatchIndex), ranges.count - 1)
                for (index, range) in ranges.enumerated() {
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: index == selectedIndex
                            ? NSColor.systemOrange.withAlphaComponent(0.75)
                            : NSColor.systemYellow.withAlphaComponent(0.45),
                        forCharacterRange: range
                    )
                }

                if shouldScroll {
                    let selectedRange = ranges[min(max(0, searchMatchIndex), ranges.count - 1)]
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self,
                              let textView,
                              let layoutManager = textView.layoutManager,
                              let textContainer = textView.textContainer else { return }
                        layoutManager.ensureLayout(for: textContainer)
                        textView.scrollRangeToVisible(selectedRange)
                        self.publishCurrentScroll()
                    }
                }
            }

            appliedSearchText = query
            appliedSearchNavigationRequestID = searchNavigationRequestID
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
            let didScroll = Self.restore(
                scrollView,
                textView: textView,
                toY: initialScrollY,
                visibleLocation: initialVisibleLocation
            )
            if didScroll || initialScrollY <= 0 {
                didRestoreInitialScroll = true
            } else if restoreAttempts < 12 {
                restoreAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.restoreInitialScrollIfNeeded()
                }
            } else {
                didRestoreInitialScroll = true
            }
            publishCurrentScroll()
        }

        func focusEditorIfRequested() {
            guard handledFocusRequest != focusRequest,
                  let textView else { return }
            handledFocusRequest = focusRequest
            textView.window?.makeFirstResponder(textView)
        }

        private func publishCurrentScroll() {
            guard let scrollView else { return }
            onViewportChanged(
                Double(scrollView.contentView.bounds.origin.y),
                Self.visibleCharacterLocation(in: scrollView, textView: textView)
            )
        }

        @objc private func syncCurrentScroll() {
            publishCurrentScroll()
        }

        @objc private func scrollBoundsDidChange() {
            publishCurrentScroll()
        }

        private static func restore(
            _ scrollView: NSScrollView,
            textView: NSTextView?,
            toY scrollY: Double,
            visibleLocation: Int
        ) -> Bool {
            guard let documentView = scrollView.documentView else { return false }
            documentView.layoutSubtreeIfNeeded()
            if let textView, visibleLocation > 0, textView.string.count > 0 {
                return scrollToCharacterLocation(
                    visibleLocation,
                    in: scrollView,
                    textView: textView
                )
            }
            let visibleHeight = scrollView.contentView.bounds.height
            let maxY = max(0, documentView.bounds.height - visibleHeight)
            guard maxY > 0 || scrollY <= 0 else { return false }
            let safeY = min(max(0, CGFloat(scrollY)), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: safeY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return abs(scrollView.contentView.bounds.origin.y - safeY) <= 1 || safeY == 0
        }

        private static func visibleCharacterLocation(in scrollView: NSScrollView, textView: NSTextView?) -> Int {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return 0 }
            let containerOrigin = textView.textContainerOrigin
            let visibleRect = scrollView.contentView.documentVisibleRect.offsetBy(
                dx: -containerOrigin.x,
                dy: -containerOrigin.y
            )
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            return characterRange.location == NSNotFound ? 0 : characterRange.location
        }

        private static func scrollToCharacterLocation(
            _ location: Int,
            in scrollView: NSScrollView,
            textView: NSTextView
        ) -> Bool {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let documentView = scrollView.documentView else { return false }
            layoutManager.ensureLayout(for: textContainer)
            let textLength = (textView.string as NSString).length
            let safeLocation = min(max(0, location), max(0, textLength))
            let glyphIndex = safeLocation < textLength
                ? layoutManager.glyphIndexForCharacter(at: safeLocation)
                : max(0, layoutManager.numberOfGlyphs - 1)
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: min(1, max(0, layoutManager.numberOfGlyphs - glyphIndex))),
                in: textContainer
            )
            guard glyphRect.origin.y.isFinite else { return false }
            let containerOrigin = textView.textContainerOrigin
            let visibleHeight = scrollView.contentView.bounds.height
            let maxY = max(0, documentView.bounds.height - visibleHeight)
            let targetY = min(max(0, glyphRect.origin.y + containerOrigin.y), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return abs(scrollView.contentView.bounds.origin.y - targetY) <= 1 || targetY == 0
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
            menu.addItem(.separator())
            let askItem = NSMenuItem(
                title: "Ask AI About Selection…",
                action: #selector(askAIAboutSelectionFromMenu(_:)),
                keyEquivalent: ""
            )
            askItem.target = self
            menu.addItem(askItem)
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

        @objc private func askAIAboutSelectionFromMenu(_ sender: NSMenuItem) {
            let selectedText: String?
            if let textView {
                let range = textView.selectedRange()
                let length = (textView.string as NSString).length
                selectedText = range.length > 0 && range.location != NSNotFound && NSMaxRange(range) <= length
                    ? (textView.string as NSString).substring(with: range)
                    : nil
                onTextViewReady(textView)
            } else {
                selectedText = nil
            }
            onAskAIAboutSelection(selectedText)
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

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
                preview
            case .split:
                HSplitView {
                    editorWithFormatting
                        .frame(minWidth: 360)
                    preview
                        .frame(minWidth: 360)
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

    private var formattingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MarkdownFormatCommand.allCases, id: \.self) { command in
                    Button {
                        model.applyMarkdownFormat(command)
                    } label: {
                        Label(command.title, systemImage: command.systemImage)
                            .labelStyle(.iconOnly)
                    }
                    .help(command.title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editor: some View {
        MarkdownSourceEditor(text: Binding(
            get: { document.text },
            set: { model.updateMarkdown($0) }
        )) { textView in
            model.rememberMarkdownTextView(textView)
        }
        .contextMenu {
            ForEach(MarkdownFormatCommand.allCases, id: \.self) { command in
                Button(command.title) {
                    model.applyMarkdownFormat(command)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var preview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(markdownBlocks) { block in
                    blockView(block)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.body)
            .lineSpacing(4)
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
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
        case quote(String)
        case code(String)
    }

    let id = UUID()
    let kind: Kind

    static func parse(_ markdown: String) -> [MarkdownPreviewBlock] {
        var blocks: [MarkdownPreviewBlock] = []
        var inCodeBlock = false
        var codeLines: [String] = []

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.init(kind: .code(codeLines.joined(separator: "\n"))))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                blocks.append(.init(kind: .blank))
            } else if let heading = heading(from: trimmed) {
                blocks.append(.init(kind: .heading(level: heading.level, text: heading.text)))
            } else if let bullet = unorderedListText(from: trimmed) {
                blocks.append(.init(kind: .bullet(bullet)))
            } else if let numbered = orderedListText(from: trimmed) {
                blocks.append(.init(kind: .numbered(number: numbered.number, text: numbered.text)))
            } else if trimmed.hasPrefix(">") {
                let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                blocks.append(.init(kind: .quote(text)))
            } else {
                blocks.append(.init(kind: .paragraph(rawLine)))
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

private struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let onTextViewReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextViewReady: onTextViewReady)
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

        scrollView.documentView = textView
        context.coordinator.textView = textView
        onTextViewReady(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.onTextViewReady = onTextViewReady
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selectedRange.location, (text as NSString).length),
                length: 0
            ))
        }
        onTextViewReady(textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onTextViewReady: (NSTextView) -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, onTextViewReady: @escaping (NSTextView) -> Void) {
            self.text = text
            self.onTextViewReady = onTextViewReady
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

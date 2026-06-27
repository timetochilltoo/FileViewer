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
            VStack(alignment: .leading, spacing: 14) {
                if let attributed = renderedMarkdown {
                    Text(attributed)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(document.text)
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

    private var renderedMarkdown: AttributedString? {
        guard var attributed = try? AttributedString(markdown: document.text) else { return nil }
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return attributed }

        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: query, options: [.caseInsensitive]) {
            attributed[range].backgroundColor = .yellow.opacity(0.45)
            attributed[range].foregroundColor = .primary
            searchRange = range.upperBound..<attributed.endIndex
        }
        return attributed
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

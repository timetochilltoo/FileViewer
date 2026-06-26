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
        TextEditor(text: Binding(
            get: { document.text },
            set: { model.updateMarkdown($0) }
        ))
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
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

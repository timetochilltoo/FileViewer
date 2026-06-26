import SwiftUI

struct MarkdownWorkspace: View {
    @ObservedObject var model: AppModel
    let document: MarkdownDocument

    var body: some View {
        Group {
            switch model.markdownMode {
            case .source:
                editor
            case .preview:
                preview
            case .split:
                HSplitView {
                    editor
                        .frame(minWidth: 360)
                    preview
                        .frame(minWidth: 360)
                }
            }
        }
    }

    private var editor: some View {
        TextEditor(text: Binding(
            get: { document.text },
            set: { model.updateMarkdown($0) }
        ))
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let attributed = try? AttributedString(markdown: document.text) {
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
}

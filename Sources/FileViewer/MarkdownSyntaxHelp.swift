import AppKit
import SwiftUI

@MainActor
final class MarkdownSyntaxHelpPresenter {
    static let shared = MarkdownSyntaxHelpPresenter()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown Syntax Guide"
        window.center()
        window.contentView = NSHostingView(rootView: MarkdownSyntaxHelpView())
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MarkdownSyntaxHelpView: View {
    private let examples: [(title: String, syntax: String, note: String)] = [
        ("Heading", "# Big heading\n## Smaller heading", "Use one to six # characters."),
        ("Bold", "**important text**", "Two stars on each side."),
        ("Italic", "*emphasized text*", "One star on each side."),
        ("Bold + Italic", "***very important***", "Three stars on each side."),
        ("Strikethrough", "~~old text~~", "Common Markdown extension."),
        ("Link", "[OpenAI](https://openai.com)", "Text in brackets, address in parentheses."),
        ("Image", "![Alt text](image.png)", "Similar to a link, with ! before it."),
        ("Bullet list", "- first item\n- second item", "Use - or * followed by a space."),
        ("Numbered list", "1. first item\n2. second item", "Numbers can usually auto-renumber."),
        ("Task list", "- [ ] todo\n- [x] done", "Good for checklists."),
        ("Quote", "> quoted text", "Use > at the start of the line."),
        ("Inline code", "`short code`", "Use backticks around a short code phrase."),
        ("Code block", "```swift\nprint(\"Hello\")\n```", "Fence longer code with three backticks."),
        ("Table", "| Name | Value |\n| --- | --- |\n| A | 1 |", "Use pipes and a separator row."),
        ("Horizontal rule", "---", "Three dashes on their own line.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Markdown Syntax Guide")
                        .font(.largeTitle.weight(.bold))
                    Text("A quick cheat sheet for writing Markdown notes. Copy the pattern on the left, replace the words with yours, and preview the result in FileViewer.")
                        .foregroundStyle(.secondary)
                }

                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(examples, id: \.title) { example in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(example.title)
                                .font(.headline)
                            Text(example.syntax)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            Text(example.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import SwiftUI

struct FileViewerModelKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    var fileViewerModel: AppModel? {
        get { self[FileViewerModelKey.self] }
        set { self[FileViewerModelKey.self] = newValue }
    }
}

struct FileViewerCommands: Commands {
    @FocusedValue(\.fileViewerModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Markdown Document") {
                model?.newMarkdownDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open...") {
                model?.openWithPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Save") {
                model?.saveMarkdown()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model?.canSaveMarkdown != true)

            Button("Save As...") {
                model?.saveMarkdownAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(model?.isMarkdownDocument != true)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                model?.printDocument()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(model?.canPrintDocument != true)
        }

        CommandMenu("View") {
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command, .option])

            Divider()

            Button("Markdown Preview") {
                model?.setMarkdownMode(.preview)
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(model?.isMarkdownDocument != true)

            Button("Markdown Source") {
                model?.setMarkdownMode(.source)
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(model?.isMarkdownDocument != true)

            Button("Markdown Split") {
                model?.setMarkdownMode(.split)
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(model?.isMarkdownDocument != true)

            Divider()

            Button("Fit Page") {
                NotificationCenter.default.post(name: .pdfFitPage, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(model?.isPDFDocument != true)

            Button("Fit Width") {
                NotificationCenter.default.post(name: .pdfFitWidth, object: nil)
            }
            .keyboardShortcut("9", modifiers: .command)
            .disabled(model?.isPDFDocument != true)

            Button("Zoom In") {
                NotificationCenter.default.post(name: .pdfZoomIn, object: nil)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(model?.isPDFDocument != true)

            Button("Zoom Out") {
                NotificationCenter.default.post(name: .pdfZoomOut, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(model?.isPDFDocument != true)
        }

        CommandMenu("Navigate") {
            Button("Previous Page") {
                NotificationCenter.default.post(name: .pdfPreviousPage, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(model?.isPDFDocument != true)

            Button("Next Page") {
                NotificationCenter.default.post(name: .pdfNextPage, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(model?.isPDFDocument != true)
        }

        CommandMenu("Markdown") {
            Button("Bold") {
                model?.applyMarkdownFormat(.bold)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(model?.isMarkdownDocument != true)

            Button("Italic") {
                model?.applyMarkdownFormat(.italic)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(model?.isMarkdownDocument != true)

            Button("Underline") {
                model?.applyMarkdownFormat(.underline)
            }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(model?.isMarkdownDocument != true)

            Divider()

            Button("Heading") {
                model?.applyMarkdownFormat(.heading)
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
            .disabled(model?.isMarkdownDocument != true)

            Button("Bullet List") {
                model?.applyMarkdownFormat(.bulletList)
            }
            .disabled(model?.isMarkdownDocument != true)

            Button("Numbered List") {
                model?.applyMarkdownFormat(.numberedList)
            }
            .disabled(model?.isMarkdownDocument != true)

            Button("Quote") {
                model?.applyMarkdownFormat(.quote)
            }
            .disabled(model?.isMarkdownDocument != true)

            Button("Link") {
                model?.applyMarkdownFormat(.link)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(model?.isMarkdownDocument != true)

            Button("Code") {
                model?.applyMarkdownFormat(.code)
            }
            .disabled(model?.isMarkdownDocument != true)
        }

        CommandGroup(replacing: .help) {
            Button("Markdown Syntax Guide") {
                MarkdownSyntaxHelpPresenter.shared.show()
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }
}

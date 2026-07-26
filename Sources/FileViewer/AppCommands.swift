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
    // `FocusedValue` supplies the active window's model, but it does not observe
    // changes published by that model. Keep a focused object as well so File
    // menu validation refreshes immediately after actions such as creating an
    // untitled Markdown document, rather than waiting for an app focus change.
    @FocusedObject private var focusedModel: AppModel?
    @FocusedValue(\.fileViewerModel) private var model
    private var activeModel: AppModel? {
        focusedModel ?? model ?? FileViewerWindowRegistry.shared.activeModel
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Markdown Document") {
                activeModel?.newMarkdownDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open...") {
                activeModel?.openWithPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Save") {
                if activeModel?.isPDFDocument == true {
                    activeModel?.savePDFAnnotations()
                } else {
                    activeModel?.saveMarkdown()
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            // SwiftUI Commands can defer menu revalidation until the app regains
            // focus. A PDF may always be safely written, so keep Save available for
            // any open PDF rather than relying on its asynchronously updated dirty
            // flag. Markdown retains its normal dirty-state behavior.
            .disabled(activeModel?.canSaveMarkdown != true && activeModel?.isPDFDocument != true)

            Button("Save As...") {
                if activeModel?.isPDFDocument == true {
                    activeModel?.savePDFAnnotatedCopyAs()
                } else {
                    activeModel?.saveMarkdownAs()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(activeModel?.isMarkdownDocument != true && activeModel?.isPDFDocument != true)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                activeModel?.printDocument()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(activeModel?.canPrintDocument != true)
        }

        CommandMenu("Display") {
            Button("Toggle Sidebar") {
                if let activeModel {
                    NotificationCenter.default.post(name: .toggleSidebar, object: activeModel)
                }
            }
            .keyboardShortcut("0", modifiers: [.command, .option])

            Divider()

            Button("Markdown Preview") {
                activeModel?.setMarkdownMode(.preview)
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Markdown Source") {
                activeModel?.setMarkdownMode(.source)
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Markdown Split") {
                activeModel?.setMarkdownMode(.split)
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(activeModel?.isMarkdownDocument != true)

            Divider()

            Button("Fit Page") {
                activeModel?.postPDFCommand(.pdfFitPage)
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(activeModel?.isPDFDocument != true)

            Button("Fit Width") {
                activeModel?.postPDFCommand(.pdfFitWidth)
            }
            .keyboardShortcut("9", modifiers: .command)
            .disabled(activeModel?.isPDFDocument != true)

            Button("Zoom In") {
                activeModel?.postPDFCommand(.pdfZoomIn)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(activeModel?.isPDFDocument != true)

            Button("Zoom Out") {
                activeModel?.postPDFCommand(.pdfZoomOut)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(activeModel?.isPDFDocument != true)
        }

        CommandMenu("Navigate") {
            Button("Previous Page") {
                activeModel?.postPDFCommand(.pdfPreviousPage)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(activeModel?.isPDFDocument != true)

            Button("Next Page") {
                activeModel?.postPDFCommand(.pdfNextPage)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(activeModel?.isPDFDocument != true)
        }

        CommandMenu("Markdown") {
            Button("Bold") {
                activeModel?.applyMarkdownFormat(.bold)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Italic") {
                activeModel?.applyMarkdownFormat(.italic)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Underline") {
                activeModel?.applyMarkdownFormat(.underline)
            }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(activeModel?.isMarkdownDocument != true)

            Divider()

            Button("Heading") {
                activeModel?.applyMarkdownFormat(.heading)
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Bullet List") {
                activeModel?.applyMarkdownFormat(.bulletList)
            }
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Numbered List") {
                activeModel?.applyMarkdownFormat(.numberedList)
            }
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Quote") {
                activeModel?.applyMarkdownFormat(.quote)
            }
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Link") {
                activeModel?.applyMarkdownFormat(.link)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Code") {
                activeModel?.applyMarkdownFormat(.code)
            }
            .disabled(activeModel?.isMarkdownDocument != true)

            Divider()

            Button("Insert Table") {
                activeModel?.applyMarkdownFormat(.table)
            }
            .disabled(activeModel?.isMarkdownDocument != true)

            Button("Task List") {
                activeModel?.applyMarkdownFormat(.taskList)
            }
            .disabled(activeModel?.isMarkdownDocument != true)
        }

        CommandMenu("PDF") {
            Button("Highlight Selection") {
                postPDFAnnotation(.highlight)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(activeModel?.isPDFDocument != true)

            Button("Underline Selection") {
                postPDFAnnotation(.underline)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(activeModel?.isPDFDocument != true)

            Button("Strike Through Selection") {
                postPDFAnnotation(.strikeout)
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .disabled(activeModel?.isPDFDocument != true)

            Divider()

            Button("Reset Annotation Color to Yellow") {
                activeModel?.resetPDFAnnotationColor()
            }
            .disabled(activeModel?.isPDFDocument != true)

            Button("Recolor Annotation Mode") {
                activeModel?.togglePDFAnnotationRecolorMode()
            }
            .disabled(activeModel?.isPDFDocument != true)

            Divider()

            Button("Remove Markup from Selection") {
                guard let url = activeModel?.selectedPDFURL else { return }
                NotificationCenter.default.post(name: .pdfRemoveAnnotationsInSelection, object: url)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(activeModel?.isPDFDocument != true)

            Button("Add Sticky Note...") {
                guard let url = activeModel?.selectedPDFURL else { return }
                NotificationCenter.default.post(name: .pdfAddStickyNote, object: url)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(activeModel?.isPDFDocument != true)

            Button("Add Text Box...") {
                guard let url = activeModel?.selectedPDFURL else { return }
                NotificationCenter.default.post(name: .pdfAddTextBox, object: url)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(activeModel?.isPDFDocument != true)

            Button("Add Rectangle") {
                postPDFShape(.rectangle)
            }
            .disabled(activeModel?.isPDFDocument != true)

            Button("Add Oval") {
                postPDFShape(.oval)
            }
            .disabled(activeModel?.isPDFDocument != true)

            Button("Add Line") {
                activeModel?.beginPDFLineDrawingMode(.line)
            }
            .disabled(activeModel?.isPDFDocument != true)

            Button("Add Arrow") {
                activeModel?.beginPDFLineDrawingMode(.arrow)
            }
            .disabled(activeModel?.isPDFDocument != true)

            Button("Pen Drawing Mode") {
                activeModel?.togglePDFInkDrawingMode()
            }
            .disabled(activeModel?.isPDFDocument != true)

            Button("Move Annotation Mode") {
                activeModel?.togglePDFNoteMoveMode()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(activeModel?.isPDFDocument != true)

            Button("Edit Annotation Mode") {
                activeModel?.togglePDFAnnotationEditMode()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(activeModel?.isPDFDocument != true)

            Button("Delete Annotation Mode") {
                activeModel?.togglePDFAnnotationDeleteMode()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(activeModel?.isPDFDocument != true)

            Divider()

            Button("Undo PDF Annotation Change") {
                activeModel?.undoPDFAnnotation()
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(activeModel?.canUndoPDFAnnotation != true)

            Button("Redo PDF Annotation Change") {
                activeModel?.redoPDFAnnotation()
            }
            .keyboardShortcut("z", modifiers: [.command, .option, .shift])
            .disabled(activeModel?.canRedoPDFAnnotation != true)

            Divider()

            Button("Save PDF Changes") {
                activeModel?.savePDFAnnotations()
            }
            .disabled(activeModel?.isPDFDocument != true)

            Button("Save Annotated Copy As...") {
                activeModel?.savePDFAnnotatedCopyAs()
            }
            .disabled(activeModel?.isPDFDocument != true)

            Button("Export Annotation Summary...") {
                activeModel?.exportPDFAnnotationSummary()
            }
            .disabled(activeModel?.isPDFDocument != true)
        }

        CommandGroup(replacing: .help) {
            Button("Markdown Syntax Guide") {
                MarkdownSyntaxHelpPresenter.shared.show()
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }

    private func postPDFAnnotation(_ kind: PDFAnnotationKind) {
        guard let url = activeModel?.selectedPDFURL else { return }
        NotificationCenter.default.post(
            name: .pdfApplyAnnotation,
            object: PDFAnnotationCommand(url: url, kind: kind, color: activeModel?.pdfAnnotationNSColor ?? .systemYellow)
        )
    }

    private func postPDFShape(_ kind: PDFShapeAnnotationKind) {
        guard let url = activeModel?.selectedPDFURL else { return }
        NotificationCenter.default.post(
            name: .pdfAddShapeAnnotation,
            object: PDFShapeAnnotationCommand(url: url, kind: kind, color: activeModel?.pdfAnnotationNSColor ?? .systemYellow)
        )
    }
}

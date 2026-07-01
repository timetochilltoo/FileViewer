import PDFKit
import SwiftUI

struct PDFWorkspace: View {
    @ObservedObject var model: AppModel
    let viewerDocument: PDFViewerDocument

    var body: some View {
        PDFKitView(
            documentURL: viewerDocument.url,
            document: viewerDocument.document,
            searchText: model.searchText,
            page: Binding(
                get: { model.pdfPage },
                set: { model.pdfPage = $0 }
            ),
            pageCount: Binding(
                get: { model.pdfPageCount },
                set: { model.pdfPageCount = $0 }
            ),
            scale: Binding(
                get: { model.pdfScale },
                set: { model.pdfScale = $0 }
            ),
            searchMatchIndex: Binding(
                get: { model.searchMatchIndex },
                set: { model.searchMatchIndex = $0 }
            ),
            searchMatchCount: Binding(
                get: { model.searchMatchCount },
                set: { model.searchMatchCount = $0 }
            ),
            isNoteMoveModeEnabled: Binding(
                get: { model.isPDFNoteMoveModeEnabled },
                set: { model.isPDFNoteMoveModeEnabled = $0 }
            ),
            isAnnotationDeleteModeEnabled: Binding(
                get: { model.isPDFAnnotationDeleteModeEnabled },
                set: { model.isPDFAnnotationDeleteModeEnabled = $0 }
            )
        )
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct PDFKitView: NSViewRepresentable {
    let documentURL: URL
    let document: PDFDocument
    let searchText: String
    @Binding var page: Int
    @Binding var pageCount: Int
    @Binding var scale: CGFloat
    @Binding var searchMatchIndex: Int
    @Binding var searchMatchCount: Int
    @Binding var isNoteMoveModeEnabled: Bool
    @Binding var isAnnotationDeleteModeEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = MovableAnnotationPDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .underPageBackgroundColor
        view.onAnnotationMoved = { [weak coordinator = context.coordinator] in
            coordinator?.markAnnotationChanged()
        }
        view.onAnnotationDeleted = { [weak coordinator = context.coordinator] in
            coordinator?.markAnnotationChanged()
        }
        context.coordinator.pdfView = view
        context.coordinator.installObservers()
        DispatchQueue.main.async {
            pageCount = document.pageCount
            if page < 1 {
                page = 1
            }
            context.coordinator.applyRestoredPageAndScale()
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            view.autoScales = true
        }

        context.coordinator.parent = self
        if let movableView = view as? MovableAnnotationPDFView {
            movableView.isNoteMoveModeEnabled = isNoteMoveModeEnabled
            movableView.isAnnotationDeleteModeEnabled = isAnnotationDeleteModeEnabled
        }
        context.coordinator.applyRestoredPageAndScale()
        context.coordinator.applySearch(searchText)
        context.coordinator.goToSearchMatch(searchMatchIndex)
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var lastSearchText = ""
        private var lastSearchIndex = 0
        private var searchSelections: [PDFSelection] = []

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        func installObservers() {
            NotificationCenter.default.addObserver(self, selector: #selector(firstPage), name: .pdfFirstPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(previousPage), name: .pdfPreviousPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(nextPage), name: .pdfNextPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(lastPage), name: .pdfLastPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(goToPage(_:)), name: .pdfGoToPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(zoomIn), name: .pdfZoomIn, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(zoomOut), name: .pdfZoomOut, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(fitWidth), name: .pdfFitWidth, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(fitPage), name: .pdfFitPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(syncCurrentState), name: .pdfSyncCurrentState, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(applyAnnotation(_:)), name: .pdfApplyAnnotation, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(removeAnnotationsInSelection(_:)), name: .pdfRemoveAnnotationsInSelection, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(addStickyNote(_:)), name: .pdfAddStickyNote, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(addTextBox(_:)), name: .pdfAddTextBox, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: Notification.Name.PDFViewPageChanged, object: pdfView)
        }

        @MainActor @objc private func firstPage() {
            guard let firstPage = parent.document.page(at: 0) else { return }
            pdfView?.go(to: firstPage)
            syncPage()
        }

        @MainActor @objc private func previousPage() {
            pdfView?.goToPreviousPage(nil)
            syncPage()
        }

        @MainActor @objc private func nextPage() {
            pdfView?.goToNextPage(nil)
            syncPage()
        }

        @MainActor @objc private func lastPage() {
            guard parent.document.pageCount > 0,
                  let lastPage = parent.document.page(at: parent.document.pageCount - 1) else { return }
            pdfView?.go(to: lastPage)
            syncPage()
        }

        @MainActor @objc private func goToPage(_ notification: Notification) {
            let requestedPage = notification.object as? Int ?? parent.page
            guard let page = parent.document.page(at: max(0, min(parent.document.pageCount - 1, requestedPage - 1))) else { return }
            pdfView?.go(to: page)
            syncPage()
        }

        @MainActor @objc private func zoomIn() {
            pdfView?.zoomIn(nil)
            syncScale()
        }

        @MainActor @objc private func zoomOut() {
            pdfView?.zoomOut(nil)
            syncScale()
        }

        @MainActor @objc private func fitWidth() {
            guard let view = pdfView,
                  let page = view.currentPage else { return }
            view.autoScales = false
            let pageWidth = page.bounds(for: view.displayBox).width
            let availableWidth = max(view.bounds.width - 36, 240)
            view.scaleFactor = max(0.2, availableWidth / max(pageWidth, 1))
            syncScale()
        }

        @MainActor @objc private func fitPage() {
            guard let view = pdfView else { return }
            view.autoScales = true
            view.scaleFactor = view.scaleFactorForSizeToFit
            syncScale()
        }

        @MainActor @objc private func pageChanged() {
            syncPage()
        }

        @MainActor @objc private func syncCurrentState() {
            syncPage()
            syncScale()
        }

        @MainActor @objc private func applyAnnotation(_ notification: Notification) {
            guard let command = notification.object as? PDFAnnotationCommand,
                  command.url == parent.documentURL else { return }
            guard let selection = pdfView?.currentSelection,
                  addAnnotation(command.kind, to: selection) else {
                NSSound.beep()
                return
            }
            pdfView?.setCurrentSelection(nil, animate: false)
            NotificationCenter.default.post(name: .pdfAnnotationDidChange, object: parent.documentURL)
        }

        @MainActor @objc private func removeAnnotationsInSelection(_ notification: Notification) {
            guard let url = notification.object as? URL,
                  url == parent.documentURL else { return }
            guard let selection = pdfView?.currentSelection,
                  removeAnnotations(overlapping: selection) else {
                NSSound.beep()
                return
            }
            let selectedPages = selection.pages
            pdfView?.setCurrentSelection(nil, animate: false)
            selectedPages.forEach { $0.displaysAnnotations = true }
            pdfView?.needsDisplay = true
            NotificationCenter.default.post(name: .pdfAnnotationDidChange, object: parent.documentURL)
        }

        @MainActor @objc private func addStickyNote(_ notification: Notification) {
            guard let url = notification.object as? URL,
                  url == parent.documentURL,
                  let noteText = promptForPDFText(
                    title: "Add Sticky Note",
                    message: "Enter the note text to attach to this PDF page.",
                    confirmTitle: "Add Note"
                  ),
                  addStickyNote(text: noteText) else {
                return
            }
            pdfView?.needsDisplay = true
            NotificationCenter.default.post(name: .pdfAnnotationDidChange, object: parent.documentURL)
        }

        @MainActor @objc private func addTextBox(_ notification: Notification) {
            guard let url = notification.object as? URL,
                  url == parent.documentURL,
                  let text = promptForPDFText(
                    title: "Add Text Box",
                    message: "Enter the text to show directly on this PDF page.",
                    confirmTitle: "Add Text"
                  ),
                  addTextBox(text: text) else {
                return
            }
            pdfView?.needsDisplay = true
            NotificationCenter.default.post(name: .pdfAnnotationDidChange, object: parent.documentURL)
        }

        @MainActor func markAnnotationChanged() {
            pdfView?.needsDisplay = true
            NotificationCenter.default.post(name: .pdfAnnotationDidChange, object: parent.documentURL)
        }

        @MainActor func applySearch(_ text: String) {
            guard text != lastSearchText else { return }
            lastSearchText = text
            lastSearchIndex = 0
            pdfView?.highlightedSelections = []
            searchSelections = []
            setSearchState(count: 0, index: 0)

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            searchSelections = parent.document.findString(text, withOptions: [.caseInsensitive])
            pdfView?.highlightedSelections = searchSelections
            setSearchState(count: searchSelections.count, index: 0)
            if let first = searchSelections.first {
                pdfView?.setCurrentSelection(first, animate: false)
                pdfView?.go(to: first)
            }
        }

        @MainActor func goToSearchMatch(_ index: Int) {
            guard !searchSelections.isEmpty else { return }
            let safeIndex = min(max(0, index), searchSelections.count - 1)
            guard safeIndex != lastSearchIndex || pdfView?.currentSelection == nil else { return }
            lastSearchIndex = safeIndex
            let selection = searchSelections[safeIndex]
            pdfView?.setCurrentSelection(selection, animate: false)
            pdfView?.go(to: selection)
        }

        @MainActor func applyRestoredPageAndScale() {
            guard let view = pdfView else { return }

            let requestedPage = max(1, min(parent.page, max(parent.document.pageCount, 1)))
            if let currentPage = view.currentPage {
                let currentIndex = parent.document.index(for: currentPage)
                if currentIndex != requestedPage - 1,
                   let targetPage = parent.document.page(at: requestedPage - 1) {
                    view.go(to: targetPage)
                }
            } else if let targetPage = parent.document.page(at: requestedPage - 1) {
                view.go(to: targetPage)
            }

            if parent.scale > 0.1,
               abs(view.scaleFactor - parent.scale) > 0.01 {
                view.autoScales = false
                view.scaleFactor = parent.scale
            }
        }

        @MainActor private func setSearchState(count: Int, index: Int) {
            let countBinding = parent.$searchMatchCount
            let indexBinding = parent.$searchMatchIndex
            DispatchQueue.main.async {
                countBinding.wrappedValue = count
                indexBinding.wrappedValue = min(max(0, index), max(0, count - 1))
            }
        }

        @MainActor private func syncPage() {
            guard let view = pdfView,
                  let currentPage = view.currentPage else { return }
            let index = parent.document.index(for: currentPage)
            guard index != NSNotFound,
                  index >= 0,
                  index < parent.document.pageCount else { return }
            parent.page = index + 1
            parent.pageCount = parent.document.pageCount
        }

        @MainActor private func syncScale() {
            guard let view = pdfView else { return }
            parent.scale = view.scaleFactor
        }

        @MainActor private func addAnnotation(_ kind: PDFAnnotationKind, to selection: PDFSelection) -> Bool {
            let lineSelections = selection.selectionsByLine()
            let selections = lineSelections.isEmpty ? [selection] : lineSelections
            var addedAnnotation = false

            for lineSelection in selections {
                for page in lineSelection.pages {
                    let bounds = lineSelection.bounds(for: page).insetBy(dx: -1.5, dy: -1.5)
                    guard bounds.width > 0, bounds.height > 0 else { continue }
                    let annotation = PDFAnnotation(
                        bounds: bounds,
                        forType: kind.pdfAnnotationSubtype,
                        withProperties: nil
                    )
                    annotation.color = kind.annotationColor
                    page.addAnnotation(annotation)
                    addedAnnotation = true
                }
            }

            return addedAnnotation
        }

        @MainActor private func addStickyNote(text: String) -> Bool {
            guard let view = pdfView,
                  let page = view.currentSelection?.pages.first ?? view.currentPage else { return false }
            let point = stickyNotePoint(on: page)
            let bounds = clamped(
                CGRect(x: point.x, y: point.y, width: 28, height: 28),
                to: page.bounds(for: view.displayBox)
            )
            let annotation = PDFAnnotation(
                bounds: bounds,
                forType: .text,
                withProperties: nil
            )
            annotation.contents = text
            annotation.color = NSColor.systemYellow
            page.addAnnotation(annotation)
            return true
        }

        @MainActor private func addTextBox(text: String) -> Bool {
            guard let view = pdfView,
                  let page = view.currentSelection?.pages.first ?? view.currentPage else { return false }
            let point = textBoxPoint(on: page)
            let bounds = clamped(
                CGRect(x: point.x, y: point.y, width: 220, height: 64),
                to: page.bounds(for: view.displayBox)
            )
            let annotation = PDFAnnotation(
                bounds: bounds,
                forType: .freeText,
                withProperties: nil
            )
            annotation.contents = text
            annotation.font = .systemFont(ofSize: 13)
            annotation.fontColor = .labelColor
            annotation.color = NSColor.systemYellow.withAlphaComponent(0.25)
            let border = PDFBorder()
            border.lineWidth = 1
            annotation.border = border
            page.addAnnotation(annotation)
            return true
        }

        @MainActor private func stickyNotePoint(on page: PDFPage) -> CGPoint {
            if let selection = pdfView?.currentSelection {
                let bounds = selection.bounds(for: page)
                if bounds.width > 0, bounds.height > 0 {
                    return CGPoint(x: bounds.maxX + 8, y: bounds.maxY + 8)
                }
            }

            guard let view = pdfView else {
                let pageBounds = page.bounds(for: .cropBox)
                return CGPoint(x: pageBounds.midX, y: pageBounds.midY)
            }
            let viewCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            return view.convert(viewCenter, to: page)
        }

        @MainActor private func textBoxPoint(on page: PDFPage) -> CGPoint {
            if let selection = pdfView?.currentSelection {
                let bounds = selection.bounds(for: page)
                if bounds.width > 0, bounds.height > 0 {
                    return CGPoint(x: bounds.minX, y: bounds.minY - 76)
                }
            }

            guard let view = pdfView else {
                let pageBounds = page.bounds(for: .cropBox)
                return CGPoint(x: pageBounds.midX - 110, y: pageBounds.midY - 32)
            }
            let viewCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let pagePoint = view.convert(viewCenter, to: page)
            return CGPoint(x: pagePoint.x - 110, y: pagePoint.y - 32)
        }

        @MainActor private func promptForPDFText(title: String, message: String, confirmTitle: String) -> String? {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: confirmTitle)
            alert.addButton(withTitle: "Cancel")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            textField.placeholderString = "Text"
            alert.accessoryView = textField
            alert.window.initialFirstResponder = textField

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        @MainActor private func clamped(_ bounds: CGRect, to pageBounds: CGRect) -> CGRect {
            let margin: CGFloat = 8
            let safePageBounds = pageBounds.insetBy(dx: margin, dy: margin)
            var adjusted = bounds
            adjusted.origin.x = min(max(adjusted.origin.x, safePageBounds.minX), safePageBounds.maxX - adjusted.width)
            adjusted.origin.y = min(max(adjusted.origin.y, safePageBounds.minY), safePageBounds.maxY - adjusted.height)
            return adjusted
        }

        @MainActor private func removeAnnotations(overlapping selection: PDFSelection) -> Bool {
            let boundsByPage = selectedBoundsByPage(for: selection)
            var removedAnnotation = false

            for (page, selectedBounds) in boundsByPage {
                let expandedSelection = selectedBounds.insetBy(dx: -8, dy: -8)
                for annotation in page.annotations where annotation.isFileViewerTextMarkup {
                    let expandedAnnotation = annotation.bounds.insetBy(dx: -8, dy: -8)
                    if expandedAnnotation.intersects(expandedSelection) {
                        page.removeAnnotation(annotation)
                        removedAnnotation = true
                    }
                }
            }

            if !removedAnnotation {
                for (page, _) in boundsByPage {
                    let markupAnnotations = page.annotations.filter(\.isFileViewerTextMarkup)
                    guard markupAnnotations.count == 1,
                          let annotation = markupAnnotations.first else { continue }
                    page.removeAnnotation(annotation)
                    removedAnnotation = true
                }
            }

            return removedAnnotation
        }

        @MainActor private func selectedBoundsByPage(for selection: PDFSelection) -> [(PDFPage, CGRect)] {
            var boundsByPage: [(PDFPage, CGRect)] = []
            let lineSelections = selection.selectionsByLine()
            let selections = lineSelections.isEmpty ? [selection] : [selection] + lineSelections

            for partialSelection in selections {
                for page in partialSelection.pages {
                    let bounds = partialSelection.bounds(for: page)
                    guard bounds.width > 0, bounds.height > 0 else { continue }
                    if let index = boundsByPage.firstIndex(where: { $0.0 === page }) {
                        boundsByPage[index].1 = boundsByPage[index].1.union(bounds)
                    } else {
                        boundsByPage.append((page, bounds))
                    }
                }
            }

            return boundsByPage
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private final class MovableAnnotationPDFView: PDFView {
    var isNoteMoveModeEnabled = false
    var isAnnotationDeleteModeEnabled = false
    var onAnnotationMoved: (() -> Void)?
    var onAnnotationDeleted: (() -> Void)?
    private weak var draggedAnnotation: PDFAnnotation?
    private weak var draggedPage: PDFPage?
    private var dragOffset = CGPoint.zero

    override func mouseDown(with event: NSEvent) {
        if isAnnotationDeleteModeEnabled {
            guard let hit = movableAnnotationHit(for: event) else {
                NSSound.beep()
                return
            }
            guard confirmDelete(annotation: hit.annotation) else { return }
            hit.page.removeAnnotation(hit.annotation)
            needsDisplay = true
            onAnnotationDeleted?()
            return
        }

        guard isNoteMoveModeEnabled,
              let hit = movableAnnotationHit(for: event) else {
            super.mouseDown(with: event)
            return
        }

        draggedAnnotation = hit.annotation
        draggedPage = hit.page
        dragOffset = CGPoint(
            x: hit.pagePoint.x - hit.annotation.bounds.origin.x,
            y: hit.pagePoint.y - hit.annotation.bounds.origin.y
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard isNoteMoveModeEnabled,
              let annotation = draggedAnnotation,
              let page = draggedPage else {
            super.mouseDragged(with: event)
            return
        }

        let windowPoint = convert(event.locationInWindow, from: nil)
        let pagePoint = convert(windowPoint, to: page)
        var newBounds = annotation.bounds
        newBounds.origin = CGPoint(
            x: pagePoint.x - dragOffset.x,
            y: pagePoint.y - dragOffset.y
        )
        annotation.bounds = clamped(newBounds, to: page.bounds(for: displayBox))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isNoteMoveModeEnabled,
              draggedAnnotation != nil else {
            super.mouseUp(with: event)
            return
        }

        draggedAnnotation = nil
        draggedPage = nil
        onAnnotationMoved?()
    }

    private func movableAnnotationHit(for event: NSEvent) -> (page: PDFPage, annotation: PDFAnnotation, pagePoint: CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        let pagePoint = convert(viewPoint, to: page)
        for annotation in page.annotations.reversed() where annotation.isMovableFileViewerAnnotation {
            if annotation.bounds.insetBy(dx: -8, dy: -8).contains(pagePoint) {
                return (page, annotation, pagePoint)
            }
        }
        return nil
    }

    private func clamped(_ bounds: CGRect, to pageBounds: CGRect) -> CGRect {
        var adjusted = bounds
        adjusted.origin.x = min(max(adjusted.origin.x, pageBounds.minX), pageBounds.maxX - adjusted.width)
        adjusted.origin.y = min(max(adjusted.origin.y, pageBounds.minY), pageBounds.maxY - adjusted.height)
        return adjusted
    }

    private func confirmDelete(annotation: PDFAnnotation) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete PDF Annotation?"
        alert.informativeText = annotation.deleteConfirmationText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private extension PDFAnnotation {
    var isFileViewerTextMarkup: Bool {
        guard let type else { return false }
        let normalizedType = type.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return ["highlight", "underline", "strikeout"].contains(normalizedType)
    }

    var isStickyNote: Bool {
        guard let type else { return false }
        let normalizedType = type.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return normalizedType == "text"
    }

    var isFreeTextBox: Bool {
        guard let type else { return false }
        let normalizedType = type.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return normalizedType == "freetext"
    }

    var isMovableFileViewerAnnotation: Bool {
        isStickyNote || isFreeTextBox
    }

    var deleteConfirmationText: String {
        if isStickyNote {
            return "This will remove the sticky note from the PDF."
        }
        if isFreeTextBox {
            return "This will remove the text box from the PDF."
        }
        return "This will remove the annotation from the PDF."
    }
}


private extension PDFAnnotationKind {
    var pdfAnnotationSubtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeout: .strikeOut
        }
    }

    var annotationColor: NSColor {
        switch self {
        case .highlight:
            NSColor.systemYellow.withAlphaComponent(0.55)
        case .underline:
            NSColor.systemBlue.withAlphaComponent(0.85)
        case .strikeout:
            NSColor.systemRed.withAlphaComponent(0.85)
        }
    }
}

struct PDFThumbnailSidebar: NSViewRepresentable {
    let document: PDFDocument
    let selectPage: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selectPage: selectPage)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let pdfView = PDFView()
        pdfView.document = document

        let thumbnailView = PDFThumbnailView()
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 96, height: 132)
        context.coordinator.pdfView = pdfView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )

        let scrollView = NSScrollView()
        scrollView.documentView = thumbnailView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let thumbnailView = scrollView.documentView as? PDFThumbnailView,
              thumbnailView.pdfView?.document !== document else { return }
        thumbnailView.pdfView?.document = document
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        let selectPage: (Int) -> Void

        init(selectPage: @escaping (Int) -> Void) {
            self.selectPage = selectPage
        }

        @MainActor @objc func pageChanged() {
            guard let pdfView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: page)
            guard index != NSNotFound,
                  index >= 0,
                  index < document.pageCount else { return }
            selectPage(index + 1)
        }
    }
}

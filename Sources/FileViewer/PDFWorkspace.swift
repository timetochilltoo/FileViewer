import PDFKit
import SwiftUI

struct PDFWorkspace: View {
    @ObservedObject var model: AppModel
    let viewerDocument: PDFViewerDocument

    var body: some View {
        PDFKitView(
            document: viewerDocument.document,
            searchText: model.searchText,
            page: $model.pdfPage,
            pageCount: $model.pdfPageCount,
            scale: $model.pdfScale
        )
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let searchText: String
    @Binding var page: Int
    @Binding var pageCount: Int
    @Binding var scale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .underPageBackgroundColor
        context.coordinator.pdfView = view
        context.coordinator.installObservers()
        DispatchQueue.main.async {
            pageCount = document.pageCount
            page = 1
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            view.autoScales = true
        }

        context.coordinator.parent = self
        context.coordinator.applySearch(searchText)
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var lastSearchText = ""
        private var searchSelections: [PDFSelection] = []

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        func installObservers() {
            NotificationCenter.default.addObserver(self, selector: #selector(previousPage), name: .pdfPreviousPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(nextPage), name: .pdfNextPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(goToPage(_:)), name: .pdfGoToPage, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(zoomIn), name: .pdfZoomIn, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(zoomOut), name: .pdfZoomOut, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: Notification.Name.PDFViewPageChanged, object: pdfView)
        }

        @MainActor @objc private func previousPage() {
            pdfView?.goToPreviousPage(nil)
            syncPage()
        }

        @MainActor @objc private func nextPage() {
            pdfView?.goToNextPage(nil)
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

        @MainActor @objc private func pageChanged() {
            syncPage()
        }

        @MainActor func applySearch(_ text: String) {
            guard text != lastSearchText else { return }
            lastSearchText = text
            pdfView?.highlightedSelections = []
            searchSelections = []

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            searchSelections = parent.document.findString(text, withOptions: [.caseInsensitive])
            pdfView?.highlightedSelections = searchSelections
            if let first = searchSelections.first {
                pdfView?.go(to: first)
            }
        }

        @MainActor private func syncPage() {
            guard let view = pdfView,
                  let currentPage = view.currentPage else { return }
            let index = parent.document.index(for: currentPage)
            DispatchQueue.main.async {
                self.parent.page = index + 1
                self.parent.pageCount = self.parent.document.pageCount
            }
        }

        @MainActor private func syncScale() {
            guard let view = pdfView else { return }
            DispatchQueue.main.async {
                self.parent.scale = view.scaleFactor
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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
            selectPage(document.index(for: page) + 1)
        }
    }
}

import PDFKit
import SwiftUI

struct PDFPageActions: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button("Show Pages Sidebar") { model.showPDFPages() }
        Button("Select All Pages") { model.selectedPDFPages = Set(0..<model.pdfPageCount) }
        Divider()
        Button("Duplicate Selected Pages") { model.editPDFPages(.duplicate) }
        Button("Delete Selected Pages…") { model.deleteSelectedPDFPages() }
            .disabled(model.selectedPDFPages.count >= model.pdfPageCount)
        Button("Move Selected Pages…") { model.moveSelectedPDFPages() }
        Button("Move Selected Pages to End") { model.editPDFPages(.move(to: model.pdfPageCount)) }
        Button("Insert PDFs…") { model.insertPDFPages() }
        Divider()
        Button("Extract Selected Pages as PDF…") { model.exportSelectedPDFPages() }
        Button("Split Selected Pages into PDFs…") { model.exportPDFPagesIndividually(asImages: false) }
        Button("Export Selected Pages as PNG…") { model.exportPDFPagesIndividually(asImages: true) }
    }
}

struct PDFPagesSidebar: View {
    @ObservedObject var model: AppModel
    let document: PDFDocument

    private var selection: Binding<Set<Int>> {
        Binding(get: { model.selectedPDFPages }, set: { pages in
            model.selectedPDFPages = pages
            if let page = pages.sorted().first {
                model.postPDFCommand(.pdfGoToPage, object: page + 1)
            }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.selectedPDFPages.count) selected").font(.caption)
                Spacer()
                Menu("Page Tools") { PDFPageActions(model: model) }
            }
            .padding(10)
            Text("⌘-click or Shift-click to select multiple pages.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            List(selection: selection) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    VStack(spacing: 6) {
                        if let page = document.page(at: index) {
                            Image(nsImage: page.thumbnail(of: NSSize(width: 180, height: 210), for: .cropBox))
                                .resizable().scaledToFit().frame(height: 160)
                        }
                        Text("Page \(index + 1)").font(.caption)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .tag(index)
                }
            }
            .contextMenu { PDFPageActions(model: model) }
        }
    }
}

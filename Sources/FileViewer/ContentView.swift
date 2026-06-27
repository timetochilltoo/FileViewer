import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var sidebarVisible = true

    var body: some View {
        NavigationSplitView {
            if sidebarVisible {
                SidebarView(model: model)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            }
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                tabBar
                if !model.tabs.isEmpty {
                    Divider()
                }
                statusBar
                Divider()
                documentBody
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                Task { @MainActor in
                    model.open(url: url)
                }
            }
            return true
        }
        .focusedSceneValue(\.fileViewerModel, model)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            sidebarVisible.toggle()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                model.newMarkdownDocument()
            } label: {
                Label("New", systemImage: "plus")
            }
            .help("New Markdown Document")

            Button {
                model.openWithPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }

            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")

            if case .markdown = model.document {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Markdown View")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Markdown View", selection: Binding(
                        get: { model.markdownMode },
                        set: { model.setMarkdownMode($0) }
                    )) {
                        ForEach(MarkdownMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                .frame(width: 280)

                Button {
                    model.saveMarkdown()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSaveMarkdown)
                .help("Save")

                Button {
                    model.saveMarkdownAs()
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Save As")
            }

            if case .pdf = model.document {
                PDFToolbar(model: model)
            }

            Button {
                model.printDocument()
            } label: {
                Image(systemName: "printer")
            }
            .disabled(!model.canPrintDocument)
            .help("Print")

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: Binding(
                    get: { model.searchText },
                    set: { model.searchText = $0 }
                ))
                    .textFieldStyle(.plain)
                    .frame(width: 220)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var tabBar: some View {
        if !model.tabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.tabs) { tab in
                        Button {
                            model.selectTab(tab.id)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: tab.document.kind == .pdf ? "doc.richtext" : "doc.plaintext")
                                Text(tab.document.name)
                                    .lineLimit(1)
                                if case .markdown(let markdown) = tab.document, markdown.hasUnsavedChanges {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 7, height: 7)
                                }
                                Button {
                                    model.closeTab(tab.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Close Tab")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                tab.id == model.selectedTabID
                                    ? Color.accentColor.opacity(0.16)
                                    : Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var statusBar: some View {
        HStack {
            Text(model.document?.name ?? "No file open")
                .lineLimit(1)
            if case .markdown(let markdown) = model.document, markdown.hasUnsavedChanges {
                Text("Unsaved changes")
                    .foregroundStyle(.orange)
            }
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
            }
            if model.isMarkdownDocument {
                let matches = model.markdownMatchCount()
                if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("\(matches) Markdown match\(matches == 1 ? "" : "es")")
                        .foregroundStyle(matches == 0 ? .orange : .secondary)
                }
            }
            Spacer()
            if case .pdf = model.document {
                Text("Page \(model.pdfPage) of \(max(model.pdfPageCount, 1))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var documentBody: some View {
        switch model.document {
        case .markdown(let markdown):
            MarkdownWorkspace(model: model, document: markdown)
        case .pdf(let pdfDocument):
            PDFWorkspace(model: model, viewerDocument: pdfDocument)
        case nil:
            EmptyDocumentView {
                model.openWithPanel()
            }
        }
    }
}

struct PDFToolbar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                NotificationCenter.default.post(name: .pdfPreviousPage, object: nil)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous Page")

            TextField("Page", value: Binding(
                get: { model.pdfPage },
                set: { model.pdfPage = $0 }
            ), format: .number)
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
                .onSubmit {
                    NotificationCenter.default.post(name: .pdfGoToPage, object: model.pdfPage)
                }

            Button {
                NotificationCenter.default.post(name: .pdfNextPage, object: nil)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next Page")

            Button {
                NotificationCenter.default.post(name: .pdfZoomOut, object: nil)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")

            Button {
                NotificationCenter.default.post(name: .pdfZoomIn, object: nil)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")

            Button {
                NotificationCenter.default.post(name: .pdfFitWidth, object: nil)
            } label: {
                Image(systemName: "arrow.left.and.right")
            }
            .help("Fit Width")

            Button {
                NotificationCenter.default.post(name: .pdfFitPage, object: nil)
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Fit Page")
        }
    }
}

struct EmptyDocumentView: View {
    let open: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a Markdown or PDF file")
                .font(.title2.weight(.semibold))
            Text("Drag a file into the window, or choose one from your Mac.")
                .foregroundStyle(.secondary)
            Button(action: open) {
                Label("Open File", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let pdfPreviousPage = Notification.Name("FileViewer.pdfPreviousPage")
    static let pdfNextPage = Notification.Name("FileViewer.pdfNextPage")
    static let pdfGoToPage = Notification.Name("FileViewer.pdfGoToPage")
    static let pdfZoomIn = Notification.Name("FileViewer.pdfZoomIn")
    static let pdfZoomOut = Notification.Name("FileViewer.pdfZoomOut")
    static let pdfFitWidth = Notification.Name("FileViewer.pdfFitWidth")
    static let pdfFitPage = Notification.Name("FileViewer.pdfFitPage")
    static let pdfSearch = Notification.Name("FileViewer.pdfSearch")
    static let toggleSidebar = Notification.Name("FileViewer.toggleSidebar")
}

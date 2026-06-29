import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model: AppModel
    @State private var sidebarVisible = true

    init(initialURLs: [URL] = []) {
        _model = StateObject(wrappedValue: AppModel(opening: initialURLs))
    }

    init(restoring session: SavedSessionWindow) {
        _model = StateObject(wrappedValue: AppModel(restoring: session))
    }

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
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }
                    Task { @MainActor in
                        model.open(url: url)
                    }
                }
            }
            return true
        }
        .focusedSceneValue(\.fileViewerModel, model)
        .background(WindowRegistrationView(model: model))
        .onAppear {
            FileViewerWindowRegistry.shared.register(model)
        }
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
                    .labelStyle(.iconOnly)
            }
            .help("New Markdown Document")

            Button {
                model.openWithPanel()
            } label: {
                Label("Open", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .help("Open")

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
                .frame(minWidth: 170, idealWidth: 220, maxWidth: 260)

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
                .frame(minWidth: 0)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                SearchTextField(text: Binding(
                    get: { model.searchText },
                    set: { model.searchText = $0 }
                ), onSubmit: {
                    model.nextSearchMatch()
                })
                .frame(minWidth: 80, idealWidth: 180, maxWidth: 220)
                if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(model.searchStatusText)
                        .font(.caption)
                        .foregroundStyle(model.searchMatchCount == 0 ? .orange : .secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                    Button {
                        model.previousSearchMatch()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canNavigateSearch)
                    .help("Previous Search Match")
                    Button {
                        model.nextSearchMatch()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canNavigateSearch)
                    .help("Next Search Match")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .frame(minWidth: 120, idealWidth: 300, maxWidth: 360)
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
                                    model.requestCloseTab(tab.id)
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
                if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search: \(model.searchStatusText)")
                        .foregroundStyle(model.searchMatchCount == 0 ? .orange : .secondary)
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

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit)
        textField.placeholderString = "Search"
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        @objc func submit() {
            onSubmit()
        }
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
    static let pdfSyncCurrentState = Notification.Name("FileViewer.pdfSyncCurrentState")
    static let toggleSidebar = Notification.Name("FileViewer.toggleSidebar")
}

private struct WindowRegistrationView: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                FileViewerWindowRegistry.shared.register(model, window: window)
            }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window {
                FileViewerWindowRegistry.shared.register(model, window: window)
            }
        }
    }
}

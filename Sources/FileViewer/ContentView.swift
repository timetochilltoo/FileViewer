import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model: AppModel
    @State private var sidebarVisible = true
    @State private var aiPanelDragStartWidth: CGFloat?
    private let sidebarWidth: CGFloat = 320
    private let dividerWidth: CGFloat = 1

    init(initialURLs: [URL] = []) {
        _model = StateObject(wrappedValue: AppModel(opening: initialURLs))
    }

    init(restoring session: SavedSessionWindow) {
        _model = StateObject(wrappedValue: AppModel(restoring: session))
    }

    var body: some View {
        GeometryReader { proxy in
            let reservedSidebarWidth = sidebarVisible ? min(sidebarWidth, max(0, proxy.size.width - 360)) : 0
            let reservedDividerWidth = sidebarVisible ? dividerWidth : 0
            let availableWidth = max(0, proxy.size.width - reservedSidebarWidth - reservedDividerWidth)
            let showsAI = model.aiPanelVisible && model.document != nil
            let maximumAIWidth = max(280, availableWidth - 320)
            let reservedAIWidth = showsAI ? min(max(280, model.aiPanelWidth), maximumAIWidth) : 0
            let aiDividerWidth: CGFloat = showsAI ? 6 : 0
            let documentWidth = max(0, availableWidth - reservedAIWidth - aiDividerWidth)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if sidebarVisible {
                        SidebarView(model: model)
                            .frame(width: reservedSidebarWidth, height: proxy.size.height)
                            .clipped()
                        Divider()
                            .frame(width: reservedDividerWidth)
                    }

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
                    .frame(width: documentWidth, height: proxy.size.height)
                    .clipped()

                    if showsAI {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: aiDividerWidth, height: proxy.size.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let startingWidth = aiPanelDragStartWidth ?? model.aiPanelWidth
                                        if aiPanelDragStartWidth == nil { aiPanelDragStartWidth = startingWidth }
                                        model.aiPanelWidth = min(600, max(280, startingWidth - value.translation.width))
                                    }
                                    .onEnded { _ in aiPanelDragStartWidth = nil }
                            )
                            .help("Drag to resize the AI Assistant")
                        AIAssistantPanel(model: model, manager: model.aiAssistant)
                            .frame(width: reservedAIWidth, height: proxy.size.height)
                            .clipped()
                    }
                }

                if sidebarVisible {
                    sidebarOverlayToggle
                        .position(x: max(32, reservedSidebarWidth - 36), y: 42)
                        .zIndex(50)
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { notification in
            // The menu command carries its owning model. A global sidebar toggle
            // made every open window change at once.
            if let requestedModel = notification.object as? AppModel, requestedModel === model {
                toggleSidebar()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pdfAnnotationDidChange)) { notification in
            guard let url = notification.object as? URL else { return }
            model.markPDFAnnotationsChanged(for: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pdfAnnotationWillChange)) { notification in
            guard let snapshot = notification.object as? PDFAnnotationUndoSnapshot else { return }
            model.preparePDFAnnotationUndoSnapshot(snapshot)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pdfAnnotationDidAddObjects)) { notification in
            guard let change = notification.object as? PDFAnnotationObjectChange else { return }
            model.recordPDFAnnotationObjectChange(change)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                model.openWithPanel()
            } label: {
                Label("Open", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .help("Open")

            if !sidebarVisible {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Show Sidebar")
            }

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
            }

            if case .pdf = model.document {
                PDFToolbar(model: model)
            }

            Spacer()
                .frame(minWidth: 0)

            Button {
                model.aiPanelVisible.toggle()
                if model.aiPanelVisible {
                    model.aiAssistant.ensureSession(
                        for: model.selectedTabID,
                        hasSelection: !model.pdfSelectedText.isEmpty || !model.currentMarkdownSelectedText().isEmpty
                    )
                    if model.aiAssistant.connectionStatus == .notChecked {
                        Task { await model.aiAssistant.refreshModels() }
                    }
                }
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(model.aiPanelVisible ? Color.purple : Color.primary)
            }
            .disabled(model.document == nil)
            .help(model.aiPanelVisible ? "Hide AI Assistant" : "Show AI Assistant")

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

    private func toggleSidebar() {
        sidebarVisible.toggle()
    }

    private var sidebarOverlayToggle: some View {
        Button {
            toggleSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .help("Hide Sidebar")
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
                if model.canSavePDF {
                    Text("Unsaved PDF changes")
                        .foregroundStyle(.orange)
                }
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
                model.postPDFCommand(.pdfFirstPage)
            } label: {
                Image(systemName: "backward.end")
            }
            .help("First Page")

            Button {
                model.postPDFCommand(.pdfPreviousPage)
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
                    model.postPDFCommand(.pdfGoToPage, object: model.pdfPage)
                }

            Button {
                model.postPDFCommand(.pdfNextPage)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next Page")

            Button {
                model.postPDFCommand(.pdfLastPage)
            } label: {
                Image(systemName: "forward.end")
            }
            .help("Last Page")

            Button {
                model.postPDFCommand(.pdfZoomOut)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")

            Button {
                model.postPDFCommand(.pdfZoomIn)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")

            Button {
                model.postPDFCommand(.pdfFitWidth)
            } label: {
                Image(systemName: "arrow.left.and.right")
            }
            .help("Fit Width")

            Button {
                model.postPDFCommand(.pdfFitPage)
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Fit Page")

            Divider()
                .frame(height: 18)

            Menu {
                Section("Markup") {
                    Button("Highlight", systemImage: "highlighter") { postAnnotation(.highlight) }
                    Button("Underline", systemImage: "underline") { postAnnotation(.underline) }
                    Button("Strike Through", systemImage: "strikethrough") { postAnnotation(.strikeout) }
                    Button("Remove Selected Markup", systemImage: "eraser") { removeSelectedMarkup() }
                }

                Section("Add") {
                    Button("Sticky Note", systemImage: "note.text.badge.plus") { addStickyNote() }
                    Button("Text Box", systemImage: "text.badge.plus") { addTextBox() }
                    Button("Rectangle", systemImage: "rectangle") { postShape(.rectangle) }
                    Button("Oval", systemImage: "oval") { postShape(.oval) }
                    Button("Line", systemImage: "line.diagonal") { model.beginPDFLineDrawingMode(.line) }
                    Button("Arrow", systemImage: "arrow.up.right") { model.beginPDFLineDrawingMode(.arrow) }
                    Button(model.isPDFInkDrawingModeEnabled ? "Stop Pen" : "Freehand Pen", systemImage: "pencil.tip") {
                        model.togglePDFInkDrawingMode()
                    }
                }

                Section("Edit") {
                    Button(model.isPDFAnnotationRecolorModeEnabled ? "Stop Recolor" : "Recolor Existing Annotation", systemImage: "paintpalette") {
                        model.togglePDFAnnotationRecolorMode()
                    }
                    Button(model.isPDFNoteMoveModeEnabled ? "Stop Moving" : "Move Note or Text Box", systemImage: "hand.draw") {
                        model.togglePDFNoteMoveMode()
                    }
                    Button(model.isPDFAnnotationEditModeEnabled ? "Stop Editing" : "Edit Note or Text Box", systemImage: "square.and.pencil") {
                        model.togglePDFAnnotationEditMode()
                    }
                    Button(model.isPDFAnnotationDeleteModeEnabled ? "Stop Deleting" : "Delete Note or Text Box", systemImage: "trash") {
                        model.togglePDFAnnotationDeleteMode()
                    }
                }

                Divider()
                ColorPicker("Color", selection: $model.pdfAnnotationColor, supportsOpacity: false)
                Picker("Stroke Width", selection: $model.pdfAnnotationStrokeWidth) {
                    ForEach(PDFAnnotationStrokeWidth.allCases) { width in
                        Text(width.title).tag(width)
                    }
                }
                Button("Reset Color to Yellow", systemImage: "arrow.counterclockwise.circle") {
                    model.resetPDFAnnotationColor()
                }
            } label: {
                Label("Annotate", systemImage: "pencil.and.outline")
                    .foregroundStyle(annotationModeIsActive ? Color.accentColor : Color.primary)
            }
            .help("PDF annotation tools")

            Button {
                model.undoPDFAnnotation()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndoPDFAnnotation)
            .help("Undo PDF Annotation Change")

            Button {
                model.redoPDFAnnotation()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedoPDFAnnotation)
            .help("Redo PDF Annotation Change")
        }
    }

    private var annotationModeIsActive: Bool {
        model.isPDFNoteMoveModeEnabled ||
        model.isPDFAnnotationDeleteModeEnabled ||
        model.isPDFAnnotationEditModeEnabled ||
        model.isPDFAnnotationRecolorModeEnabled ||
        model.isPDFInkDrawingModeEnabled ||
        model.pdfLineDrawingMode != nil
    }

    private func removeSelectedMarkup() {
        model.pdfLineDrawingMode = nil
        model.isPDFAnnotationRecolorModeEnabled = false
        model.isPDFInkDrawingModeEnabled = false
        guard let url = model.selectedPDFURL else { return }
        NotificationCenter.default.post(name: .pdfRemoveAnnotationsInSelection, object: url)
    }

    private func addStickyNote() {
        model.pdfLineDrawingMode = nil
        model.isPDFAnnotationRecolorModeEnabled = false
        model.isPDFInkDrawingModeEnabled = false
        guard let url = model.selectedPDFURL else { return }
        NotificationCenter.default.post(name: .pdfAddStickyNote, object: url)
    }

    private func addTextBox() {
        model.pdfLineDrawingMode = nil
        model.isPDFAnnotationRecolorModeEnabled = false
        model.isPDFInkDrawingModeEnabled = false
        guard let url = model.selectedPDFURL else { return }
        NotificationCenter.default.post(name: .pdfAddTextBox, object: url)
    }

    private func postAnnotation(_ kind: PDFAnnotationKind) {
        model.pdfLineDrawingMode = nil
        model.isPDFAnnotationRecolorModeEnabled = false
        model.isPDFInkDrawingModeEnabled = false
        guard let url = model.selectedPDFURL else { return }
        NotificationCenter.default.post(
            name: .pdfApplyAnnotation,
            object: PDFAnnotationCommand(url: url, kind: kind, color: model.pdfAnnotationNSColor)
        )
    }

    private func postShape(_ kind: PDFShapeAnnotationKind) {
        model.pdfLineDrawingMode = nil
        model.isPDFAnnotationRecolorModeEnabled = false
        model.isPDFInkDrawingModeEnabled = false
        guard let url = model.selectedPDFURL else { return }
        NotificationCenter.default.post(
            name: .pdfAddShapeAnnotation,
            object: PDFShapeAnnotationCommand(url: url, kind: kind, color: model.pdfAnnotationNSColor)
        )
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
    static let pdfFirstPage = Notification.Name("FileViewer.pdfFirstPage")
    static let pdfPreviousPage = Notification.Name("FileViewer.pdfPreviousPage")
    static let pdfNextPage = Notification.Name("FileViewer.pdfNextPage")
    static let pdfLastPage = Notification.Name("FileViewer.pdfLastPage")
    static let pdfGoToPage = Notification.Name("FileViewer.pdfGoToPage")
    static let pdfGoToAnnotation = Notification.Name("FileViewer.pdfGoToAnnotation")
    static let pdfZoomIn = Notification.Name("FileViewer.pdfZoomIn")
    static let pdfZoomOut = Notification.Name("FileViewer.pdfZoomOut")
    static let pdfFitWidth = Notification.Name("FileViewer.pdfFitWidth")
    static let pdfFitPage = Notification.Name("FileViewer.pdfFitPage")
    static let pdfSearch = Notification.Name("FileViewer.pdfSearch")
    static let pdfSyncCurrentState = Notification.Name("FileViewer.pdfSyncCurrentState")
    static let pdfApplyAnnotation = Notification.Name("FileViewer.pdfApplyAnnotation")
    static let pdfRemoveAnnotationsInSelection = Notification.Name("FileViewer.pdfRemoveAnnotationsInSelection")
    static let pdfAddStickyNote = Notification.Name("FileViewer.pdfAddStickyNote")
    static let pdfAddTextBox = Notification.Name("FileViewer.pdfAddTextBox")
    static let pdfAddShapeAnnotation = Notification.Name("FileViewer.pdfAddShapeAnnotation")
    static let pdfAnnotationWillChange = Notification.Name("FileViewer.pdfAnnotationWillChange")
    static let pdfAnnotationDidChange = Notification.Name("FileViewer.pdfAnnotationDidChange")
    static let pdfAnnotationDidAddObjects = Notification.Name("FileViewer.pdfAnnotationDidAddObjects")
    static let pdfAnnotationDisplayNeedsRefresh = Notification.Name("FileViewer.pdfAnnotationDisplayNeedsRefresh")
    static let pdfFormFieldBaselineDidReset = Notification.Name("FileViewer.pdfFormFieldBaselineDidReset")
    static let markdownSyncCurrentState = Notification.Name("FileViewer.markdownSyncCurrentState")
    static let toggleSidebar = Notification.Name("FileViewer.toggleSidebar")
}

enum PDFNotificationUserInfo {
    static let tabID = "FileViewer.pdfTabID"
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

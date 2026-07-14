import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AIAssistantPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var manager: AIAssistantManager
    @State private var exportError: String?
    @State private var showsProviderSettings = false

    private var tabID: DocumentTab.ID? { model.selectedTabID }
    private var session: AIAssistantSession { manager.session(for: tabID) }
    private var hasSelection: Bool {
        if case .pdf = model.document {
            return !model.pdfSelectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !model.currentMarkdownSelectedText().isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            configuration
            Divider()
            conversation
            Divider()
            composer
        }
        .background(.background)
        .onAppear {
            manager.ensureSession(for: tabID, hasSelection: hasSelection)
            if manager.connectionStatus == .notChecked {
                Task { await manager.refreshModels() }
            }
        }
        .onChange(of: model.selectedTabID) { _, newValue in
            manager.ensureSession(for: newValue, hasSelection: hasSelection)
        }
        .alert("Could Not Save Markdown", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .sheet(isPresented: $showsProviderSettings) {
            AIProviderSettingsSheet(manager: manager)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant")
                    .font(.headline)
                Text(model.document?.name ?? "No document")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                manager.clearSession(for: tabID, hasSelection: hasSelection)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(session.messages.isEmpty)
            .help("Clear Conversation")
            Button {
                showsProviderSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("AI Provider Settings")
            Button {
                model.aiPanelVisible = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close AI Assistant")
        }
        .padding(12)
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(manager.connectionStatus.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") {
                    Task { await manager.refreshModels() }
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            Picker("Provider", selection: Binding(
                get: { manager.activeProviderID },
                set: { id in
                    manager.setActiveProvider(id)
                    Task { await manager.refreshModels() }
                }
            )) {
                ForEach(manager.providerProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.menu)

            if !manager.availableModels.isEmpty {
                Picker("Model", selection: $manager.selectedModel) {
                    ForEach(manager.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
            }

            Picker("Context", selection: sessionBinding(\.scope)) {
                ForEach(AIContextScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.menu)

            Picker("Answer in", selection: sessionBinding(\.answerLanguage)) {
                ForEach(answerLanguages, id: \.self) { language in
                    Text(language).tag(language)
                }
            }
            .pickerStyle(.menu)

            if session.scope == .selectedText && !hasSelection {
                Label("Select text in the document first.", systemImage: "selection.pin.in.out")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if session.scope == .relevantSections {
                Text("Relevant Sections finds material matching a question. Translate will use the current page or section instead.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Summarize") { submit(.summarize) }
                Button("Translate") { submit(.translate) }
                Spacer()
            }
            .disabled(!canSend)

            Picker("Translate to", selection: sessionBinding(\.targetLanguage)) {
                ForEach(answerLanguages, id: \.self) { language in
                    Text(language).tag(language)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(12)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.messages.isEmpty {
                        ContentUnavailableView(
                            "Ask About This Document",
                            systemImage: "sparkles",
                            description: Text("Choose a context, then ask a question, summarize, or translate.")
                        )
                        .padding(.top, 36)
                    }
                    ForEach(session.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
            }
            .onChange(of: session.messages.last?.content) { _, _ in
                if let id = session.messages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: AIMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if message.content.isEmpty && session.isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(rendered(message.content))
                    .textSelection(.enabled)
            }
            if message.role == .assistant, !message.content.isEmpty, !session.isGenerating {
                Divider()
                HStack(spacing: 10) {
                    Button {
                        copyAnswer(for: message)
                    } label: {
                        Label("Copy Answer", systemImage: "doc.on.clipboard")
                    }
                    .help("Copy only the AI response")
                    Button {
                        copyMarkdown(for: message)
                    } label: {
                        Label("Copy as Markdown", systemImage: "doc.on.doc")
                    }
                    .help("Copy the response with document and model details")
                    Button {
                        saveMarkdown(for: message)
                    } label: {
                        Label("Save as Markdown…", systemImage: "square.and.arrow.down")
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.contextDescription.isEmpty {
                Text("Context: \(session.contextDescription)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            AIComposerTextEditor(
                text: sessionBinding(\.draft),
                canSend: canSend && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSend: { submit(.ask) }
            )
                .frame(minHeight: 70, maxHeight: 130)
                .padding(5)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Return sends • Shift-Return adds a new line")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if session.isGenerating {
                    Button("Stop") { manager.stop(for: tabID) }
                } else {
                    Button("Send") { submit(.ask) }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!canSend || session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
    }

    private var answerLanguages: [String] {
        ["English", "Traditional Chinese", "Simplified Chinese"]
    }

    private var canSend: Bool {
        model.document != nil && manager.connectionStatus.isConnected && !session.isGenerating &&
            (session.scope != .selectedText || hasSelection)
    }

    private var connectionColor: Color {
        switch manager.connectionStatus {
        case .connected: .green
        case .checking: .orange
        case .notChecked: .secondary
        case .unavailable: .red
        }
    }

    private func sessionBinding<Value>(_ keyPath: WritableKeyPath<AIAssistantSession, Value>) -> Binding<Value> {
        Binding(
            get: { manager.session(for: tabID)[keyPath: keyPath] },
            set: { value in manager.updateSession(for: tabID) { $0[keyPath: keyPath] = value } }
        )
    }

    private func submit(_ task: AITaskKind) {
        guard let tabID, let document = model.document, let tab = model.selectedTab else { return }
        manager.send(
            taskKind: task,
            tabID: tabID,
            document: document,
            tab: tab,
            markdownSelection: model.currentMarkdownSelectedText()
        )
    }

    private func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func markdownExport(for message: AIMessage) -> String {
        AIResponseMarkdownExport.make(
            response: message.content,
            sourceName: model.document?.name ?? "Unknown document",
            contextDescription: session.contextDescription,
            modelName: manager.selectedModel
        )
    }

    private func copyMarkdown(for message: AIMessage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdownExport(for: message), forType: .string)
    }

    private func copyAnswer(for message: AIMessage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AIResponsePlainTextExport.make(response: message.content), forType: .string)
    }

    private func saveMarkdown(for message: AIMessage) {
        let panel = NSSavePanel()
        panel.title = "Save AI Response as Markdown"
        panel.prompt = "Save"
        panel.nameFieldStringValue = AIResponseMarkdownExport.suggestedFileName(
            sourceName: model.document?.name ?? "AI Response"
        )
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = markdownExport(for: message)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct AIProviderSettingsSheet: View {
    @ObservedObject var manager: AIAssistantManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var name = ""
    @State private var kind: AIProviderKind = .lmStudio
    @State private var endpoint = ""
    @State private var defaultModel = ""
    @State private var allowRemoteAccess = false
    @State private var apiKey = ""
    @State private var message: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Providers")
                    .font(.headline)
                List(selection: $selectedID) {
                    ForEach(manager.providerProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                HStack {
                    Menu {
                        ForEach(AIProviderKind.allCases) { kind in
                            Button("Add \(kind.title)") { add(kind: kind) }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        if let selectedID { remove(id: selectedID) }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(manager.providerProfiles.count <= 1)
                    Spacer()
                }
            }
            .padding()
            .frame(width: 220)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Form {
                    Section("Connection") {
                        TextField("Name", text: $name)
                        Picker("Provider", selection: $kind) {
                            ForEach(AIProviderKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .onChange(of: kind) { _, newKind in
                            endpoint = newKind.defaultEndpoint
                            // Changing a profile type must not silently authorize
                            // a remote endpoint to receive document contents.
                            allowRemoteAccess = false
                        }
                        TextField("Server URL", text: $endpoint)
                        TextField("Default model (optional)", text: $defaultModel)
                        Toggle("Allow this provider to receive document text", isOn: $allowRemoteAccess)
                        SecureField(
                            kind.needsAPIKey ? "API key" : "API key (optional)",
                            text: $apiKey,
                            prompt: Text(kind.needsAPIKey ? "Required — leave blank to keep a saved key" : "Optional — leave blank to keep any saved key")
                        )
                        Text("The key is stored in macOS Keychain and is never saved in app preferences or exported documents.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button("Save Provider") { save() }
                        if selectedID != manager.activeProviderID {
                            Button("Use This Provider") {
                                guard let selectedID else { return }
                                manager.setActiveProvider(selectedID)
                                Task { await manager.refreshModels() }
                            }
                        }
                        if let message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding()
            }
            .frame(minWidth: 420)
        }
        .frame(width: 700, height: 420)
        .onAppear {
            selectedID = manager.activeProviderID
            loadSelectedProfile()
        }
        .onChange(of: selectedID) { _, _ in loadSelectedProfile() }
    }

    private var selectedProfile: AIProviderProfile {
        manager.providerProfiles.first(where: { $0.id == selectedID }) ?? manager.activeProfile
    }

    private func loadSelectedProfile() {
        let profile = selectedProfile
        name = profile.name
        kind = profile.kind
        endpoint = profile.endpoint
        defaultModel = profile.defaultModel
        allowRemoteAccess = profile.allowRemoteAccess
        apiKey = ""
        message = nil
    }

    private func add(kind: AIProviderKind) {
        manager.addProvider(kind: kind)
        selectedID = manager.activeProviderID
        loadSelectedProfile()
    }

    private func remove(id: UUID) {
        manager.removeProvider(id)
        selectedID = manager.activeProviderID
        loadSelectedProfile()
    }

    private func save() {
        guard let selectedID else { return }
        let profile = AIProviderProfile(
            id: selectedID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : name,
            kind: kind,
            endpoint: endpoint,
            defaultModel: defaultModel,
            allowRemoteAccess: allowRemoteAccess
        )
        do {
            try manager.updateProvider(profile, apiKey: apiKey.isEmpty ? nil : apiKey)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

/// An AppKit-backed composer provides normal chat behaviour while retaining a
/// multiline editor: Return sends, and Shift-Return inserts a line break.
private struct AIComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    let canSend: Bool
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SendingTextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 5)
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SendingTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.canSend = { canSend }
        textView.onSend = onSend
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class SendingTextView: NSTextView {
    var canSend: (() -> Bool)?
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isReturn, !flags.contains(.shift), !flags.contains(.option), !flags.contains(.control), !hasMarkedText(), canSend?() == true {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }
}

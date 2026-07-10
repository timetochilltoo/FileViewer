import SwiftUI

struct AIAssistantPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var manager: AIAssistantManager

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

            if session.scope == .selectedText && !hasSelection {
                Label("Select text in the document first.", systemImage: "selection.pin.in.out")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Summarize") { submit(.summarize) }
                Button("Translate") { submit(.translate) }
                Spacer()
            }
            .disabled(!canSend)

            if session.scope == .selectedText || !session.targetLanguage.isEmpty {
                Picker("Translate to", selection: sessionBinding(\.targetLanguage)) {
                    ForEach(["Traditional Chinese", "Simplified Chinese", "English", "Japanese", "Korean"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .pickerStyle(.menu)
            }
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
            TextEditor(text: sessionBinding(\.draft))
                .font(.body)
                .frame(minHeight: 70, maxHeight: 130)
                .padding(5)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Local LM Studio • 127.0.0.1")
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
}

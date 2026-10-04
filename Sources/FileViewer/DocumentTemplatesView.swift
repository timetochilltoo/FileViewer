import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DocumentTemplatesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var store = DocumentTemplateStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selection: DocumentTemplate.ID?
    @State private var errorMessage: String?

    private var selected: DocumentTemplate? { store.templates.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Document Templates").font(.title2.bold())
            Text("Create a fresh document from an independent local copy.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Import Template…") { importTemplate() }
                Button("Save Current as Template…") { saveCurrent() }
                    .disabled(model.document == nil)
                Spacer()
                Button("Move to Trash") { trashSelected() }
                    .disabled(selected == nil)
            }
            List(store.templates, selection: $selection) { template in
                HStack {
                    Image(systemName: template.kind == .pdf ? "doc.richtext" : "doc.text")
                    Text(template.name).lineLimit(1)
                    Spacer()
                    Text(template.kind == .pdf ? "PDF" : "Markdown").foregroundStyle(.secondary)
                }
                .tag(template.id)
                .help(template.name)
            }
            .overlay {
                if store.templates.isEmpty {
                    ContentUnavailableView("No Templates", systemImage: "doc.on.doc", description: Text("Import a Markdown/PDF file, or save the current document as a template."))
                }
            }
            Text("Markdown templates store text only; place image assets beside the new saved file. PDFs require a new filename. Originals stay unchanged.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Document") { createDocument() }
                    .disabled(selected == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 440)
        .onAppear { perform { try store.refresh() } }
        .alert("Template Action Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func importTemplate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            guard let kind = DocumentTemplateStore.kind(for: url) else { throw TemplateError.invalidFile }
            let template = try store.save(data: DocumentTemplateStore.read(url, kind: kind), kind: kind, name: url.deletingPathExtension().lastPathComponent)
            selection = template.id
        }
    }

    private func saveCurrent() {
        perform {
            // Capture the current tab before presenting a naming dialog.
            let snapshot = try model.currentTemplateSnapshot()
            let alert = NSAlert()
            alert.messageText = "Save Current as Template"
            alert.informativeText = "This includes current edits and leaves the original document unchanged."
            let field = NSTextField(string: (snapshot.name as NSString).deletingPathExtension)
            field.frame = NSRect(x: 0, y: 0, width: 340, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: "Save Template")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            selection = try store.save(data: snapshot.data, kind: snapshot.kind, name: field.stringValue).id
        }
    }

    private func createDocument() {
        guard let template = selected else { return }
        perform {
            let data = try store.data(for: template)
            switch template.kind {
            case .markdown:
                try model.createMarkdownFromTemplate(data: data, name: template.name)
            case .pdf:
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = template.name + " copy.pdf"
                panel.message = "Choose a new filename for your document. Existing files will not be overwritten."
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try model.createPDFFromTemplate(data: data, destination: url)
            }
            dismiss()
        }
    }

    private func trashSelected() {
        guard let template = selected else { return }
        let alert = NSAlert()
        alert.messageText = "Move “\(template.name)” to Trash?"
        alert.informativeText = "This removes the reusable template. Created documents and the original file are kept."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform { try store.trash(template); selection = nil }
    }
}

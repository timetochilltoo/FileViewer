import Foundation
import PDFKit
import SwiftUI

enum DocumentKind: String, Codable, CaseIterable {
    case markdown
    case pdf
}

enum MarkdownMode: String, Codable, CaseIterable {
    case preview
    case source
    case split

    var title: String {
        switch self {
        case .preview: "Preview"
        case .source: "Source"
        case .split: "Split"
        }
    }
}

enum SidebarMode: String, CaseIterable {
    case recent
    case contents
    case pages

    var title: String {
        switch self {
        case .recent: "Recent"
        case .contents: "Contents"
        case .pages: "Pages"
        }
    }
}

struct RecentDocument: Identifiable, Codable, Equatable {
    var id: String { url.path }
    let name: String
    let kind: DocumentKind
    let url: URL
    let openedAt: Date
}

struct MarkdownHeading: Identifiable, Equatable {
    let id: String
    let level: Int
    let title: String
}

enum ViewerDocument: Equatable {
    case markdown(MarkdownDocument)
    case pdf(PDFViewerDocument)

    var name: String {
        switch self {
        case .markdown(let document): document.url.lastPathComponent
        case .pdf(let document): document.url.lastPathComponent
        }
    }

    var url: URL {
        switch self {
        case .markdown(let document): document.url
        case .pdf(let document): document.url
        }
    }

    var kind: DocumentKind {
        switch self {
        case .markdown: .markdown
        case .pdf: .pdf
        }
    }
}

struct MarkdownDocument: Equatable {
    let url: URL
    var text: String
    var savedText: String

    var hasUnsavedChanges: Bool {
        text != savedText
    }
}

struct PDFViewerDocument: Equatable {
    let url: URL
    let document: PDFDocument

    static func == (lhs: PDFViewerDocument, rhs: PDFViewerDocument) -> Bool {
        lhs.url == rhs.url
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var document: ViewerDocument?
    @Published var sidebarMode: SidebarMode = .recent
    @Published var markdownMode: MarkdownMode = .split
    @Published var searchText = ""
    @Published var statusMessage = ""
    @Published var recents: [RecentDocument] = []
    @Published var pdfPage = 1
    @Published var pdfPageCount = 0
    @Published var pdfScale: CGFloat = 1.0

    private let recentsKey = "FileViewer.recents"
    private let markdownModeKey = "FileViewer.markdownMode"

    init() {
        loadSettings()
    }

    var markdownHeadings: [MarkdownHeading] {
        guard case .markdown(let document) = document else { return [] }
        return Self.extractHeadings(from: document.text)
    }

    var canSaveMarkdown: Bool {
        guard case .markdown(let document) = document else { return false }
        return document.hasUnsavedChanges
    }

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .text, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        statusMessage = ""
        searchText = ""

        do {
            if Self.isMarkdown(url) {
                let text = try String(contentsOf: url, encoding: .utf8)
                document = .markdown(MarkdownDocument(url: url, text: text, savedText: text))
                sidebarMode = .contents
                addRecent(name: url.lastPathComponent, kind: .markdown, url: url)
                return
            }

            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                document = .pdf(PDFViewerDocument(url: url, document: pdf))
                pdfPageCount = pdf.pageCount
                pdfPage = 1
                sidebarMode = .pages
                addRecent(name: url.lastPathComponent, kind: .pdf, url: url)
                return
            }

            statusMessage = "This file type is not supported yet."
        } catch {
            statusMessage = "Could not open this file."
        }
    }

    func updateMarkdown(_ text: String) {
        guard case .markdown(var markdown) = document else { return }
        markdown.text = text
        document = .markdown(markdown)
    }

    func saveMarkdown() {
        guard case .markdown(var markdown) = document else { return }

        do {
            try markdown.text.write(to: markdown.url, atomically: true, encoding: .utf8)
            markdown.savedText = markdown.text
            document = .markdown(markdown)
            statusMessage = "Saved."
        } catch {
            statusMessage = "Could not save this Markdown file."
        }
    }

    func saveMarkdownAs() {
        guard case .markdown(var markdown) = document else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = markdown.url.lastPathComponent
        panel.allowedContentTypes = [.text, .plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.text.write(to: url, atomically: true, encoding: .utf8)
                markdown = MarkdownDocument(url: url, text: markdown.text, savedText: markdown.text)
                document = .markdown(markdown)
                addRecent(name: url.lastPathComponent, kind: .markdown, url: url)
                statusMessage = "Saved as new Markdown file."
            } catch {
                statusMessage = "Could not save the new Markdown file."
            }
        }
    }

    func setMarkdownMode(_ mode: MarkdownMode) {
        markdownMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: markdownModeKey)
    }

    func addRecent(name: String, kind: DocumentKind, url: URL) {
        let next = RecentDocument(name: name, kind: kind, url: url, openedAt: Date())
        recents.removeAll { $0.url == url }
        recents.insert(next, at: 0)
        recents = Array(recents.prefix(12))
        saveRecents()
    }

    func reopenRecent(_ recent: RecentDocument) {
        open(url: recent.url)
    }

    private func loadSettings() {
        if let mode = UserDefaults.standard.string(forKey: markdownModeKey),
           let markdownMode = MarkdownMode(rawValue: mode) {
            self.markdownMode = markdownMode
        }

        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let decoded = try? JSONDecoder().decode([RecentDocument].self, from: data) else {
            return
        }
        recents = decoded
    }

    private func saveRecents() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        UserDefaults.standard.set(data, forKey: recentsKey)
    }

    static func isMarkdown(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    static func extractHeadings(from text: String) -> [MarkdownHeading] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> MarkdownHeading? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") else { return nil }
                let level = trimmed.prefix { $0 == "#" }.count
                guard (1...6).contains(level) else { return nil }
                let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return nil }
                return MarkdownHeading(id: title.slugID, level: level, title: title)
            }
    }
}

extension String {
    var slugID: String {
        lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace || $0 == "-" }
            .split(separator: " ")
            .joined(separator: "-")
    }
}

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

enum MarkdownFormatCommand: String, CaseIterable {
    case bold
    case italic
    case underline
    case heading
    case bulletList
    case numberedList
    case quote
    case link
    case code

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .heading: "Heading"
        case .bulletList: "Bullet List"
        case .numberedList: "Numbered List"
        case .quote: "Quote"
        case .link: "Link"
        case .code: "Code"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .heading: "textformat.size"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .quote: "quote.opening"
        case .link: "link"
        case .code: "curlybraces"
        }
    }

    var placeholderText: String {
        switch self {
        case .bold: "bold text"
        case .italic: "italic text"
        case .underline: "underlined text"
        case .heading: "Heading"
        case .bulletList: "list item"
        case .numberedList: "list item"
        case .quote: "quoted text"
        case .link: "link text"
        case .code: "code"
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

struct DocumentTab: Identifiable, Equatable {
    let id: UUID
    var document: ViewerDocument
    var searchText: String
    var pdfPage: Int
    var pdfPageCount: Int
    var pdfScale: CGFloat

    init(document: ViewerDocument) {
        id = UUID()
        self.document = document
        searchText = ""
        pdfPage = 1
        if case .pdf(let pdf) = document {
            pdfPageCount = pdf.document.pageCount
        } else {
            pdfPageCount = 0
        }
        pdfScale = 1.0
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
    @Published var tabs: [DocumentTab] = []
    @Published var selectedTabID: DocumentTab.ID?
    @Published var sidebarMode: SidebarMode = .recent
    @Published var markdownMode: MarkdownMode = .split
    @Published var statusMessage = ""
    @Published var recents: [RecentDocument] = []

    private let recentsKey = "FileViewer.recents"
    private let markdownModeKey = "FileViewer.markdownMode"
    private weak var lastActiveMarkdownTextView: NSTextView?

    init() {
        loadSettings()
    }

    var selectedTab: DocumentTab? {
        guard let index = selectedTabIndex else { return nil }
        return tabs[index]
    }

    var selectedTabIndex: Int? {
        guard let selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == selectedTabID }
    }

    var document: ViewerDocument? {
        get { selectedTab?.document }
        set {
            guard let index = selectedTabIndex else { return }
            if let newValue {
                tabs[index].document = newValue
            } else {
                tabs.remove(at: index)
                selectedTabID = tabs.first?.id
            }
        }
    }

    var searchText: String {
        get { selectedTab?.searchText ?? "" }
        set {
            guard let index = selectedTabIndex else { return }
            objectWillChange.send()
            tabs[index].searchText = newValue
        }
    }

    var pdfPage: Int {
        get { selectedTab?.pdfPage ?? 1 }
        set {
            guard let index = selectedTabIndex else { return }
            objectWillChange.send()
            tabs[index].pdfPage = newValue
        }
    }

    var pdfPageCount: Int {
        get { selectedTab?.pdfPageCount ?? 0 }
        set {
            guard let index = selectedTabIndex else { return }
            objectWillChange.send()
            tabs[index].pdfPageCount = newValue
        }
    }

    var pdfScale: CGFloat {
        get { selectedTab?.pdfScale ?? 1.0 }
        set {
            guard let index = selectedTabIndex else { return }
            objectWillChange.send()
            tabs[index].pdfScale = newValue
        }
    }

    var markdownHeadings: [MarkdownHeading] {
        guard case .markdown(let document) = document else { return [] }
        return Self.extractHeadings(from: document.text)
    }

    var canSaveMarkdown: Bool {
        guard case .markdown(let document) = document else { return false }
        return document.hasUnsavedChanges
    }

    var isMarkdownDocument: Bool {
        if case .markdown = document { return true }
        return false
    }

    var isPDFDocument: Bool {
        if case .pdf = document { return true }
        return false
    }

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .text, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            panel.urls.forEach { open(url: $0) }
        }
    }

    func open(url: URL) {
        statusMessage = ""
        if let existing = tabs.first(where: { $0.document.url == url }) {
            selectedTabID = existing.id
            updateSidebarForSelectedDocument()
            return
        }

        do {
            if Self.isMarkdown(url) {
                let text = try String(contentsOf: url, encoding: .utf8)
                appendTab(.markdown(MarkdownDocument(url: url, text: text, savedText: text)))
                sidebarMode = .contents
                addRecent(name: url.lastPathComponent, kind: .markdown, url: url)
                return
            }

            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                appendTab(.pdf(PDFViewerDocument(url: url, document: pdf)))
                sidebarMode = .pages
                addRecent(name: url.lastPathComponent, kind: .pdf, url: url)
                return
            }

            statusMessage = "This file type is not supported yet."
        } catch {
            statusMessage = "Could not open this file."
        }
    }

    func selectTab(_ id: DocumentTab.ID) {
        selectedTabID = id
        statusMessage = ""
        updateSidebarForSelectedDocument()
    }

    func closeTab(_ id: DocumentTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
            updateSidebarForSelectedDocument()
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

    func markdownMatchCount() -> Int {
        guard case .markdown(let markdown) = document else { return 0 }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return 0 }
        var count = 0
        var searchRange = markdown.text.startIndex..<markdown.text.endIndex
        while let range = markdown.text.range(of: query, options: [.caseInsensitive], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<markdown.text.endIndex
        }
        return count
    }

    func applyMarkdownFormat(_ command: MarkdownFormatCommand) {
        guard isMarkdownDocument else { return }
        guard let textView = markdownTextViewForFormatting() else {
            insertMarkdownFallback(for: command)
            return
        }

        let selectedRange = textView.selectedRange()
        let selectedText = (textView.string as NSString).substring(with: selectedRange)
        let replacement = Self.markdownReplacement(for: command, selectedText: selectedText)
        textView.insertText(replacement.text, replacementRange: selectedRange)
        if replacement.selectionOffset >= 0 {
            textView.setSelectedRange(NSRange(
                location: selectedRange.location + replacement.selectionOffset,
                length: replacement.selectionLength
            ))
        }
        updateMarkdown(textView.string)
    }

    func rememberMarkdownTextView(_ textView: NSTextView) {
        lastActiveMarkdownTextView = textView
    }

    private func markdownTextViewForFormatting() -> NSTextView? {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.string == currentMarkdownText {
            return textView
        }
        if let textView = lastActiveMarkdownTextView,
           textView.window != nil,
           textView.string == currentMarkdownText {
            return textView
        }
        guard let contentView = NSApp.keyWindow?.contentView else { return nil }
        return contentView.firstMarkdownTextView(matching: currentMarkdownText)
    }

    private var currentMarkdownText: String {
        guard case .markdown(let markdown) = document else { return "" }
        return markdown.text
    }

    private func insertMarkdownFallback(for command: MarkdownFormatCommand) {
        guard case .markdown(var markdown) = document else { return }
        let replacement = Self.markdownReplacement(for: command, selectedText: "")
        markdown.text += markdown.text.hasSuffix("\n") || markdown.text.isEmpty
            ? replacement.text
            : "\n" + replacement.text
        document = .markdown(markdown)
    }

    private static func markdownReplacement(
        for command: MarkdownFormatCommand,
        selectedText: String
    ) -> (text: String, selectionOffset: Int, selectionLength: Int) {
        let text = selectedText.isEmpty ? command.placeholderText : selectedText
        switch command {
        case .bold:
            return ("**\(text)**", 2, text.count)
        case .italic:
            return ("*\(text)*", 1, text.count)
        case .underline:
            return ("<u>\(text)</u>", 3, text.count)
        case .heading:
            return ("## \(text)", 3, text.count)
        case .bulletList:
            return (prefixLines(text, prefix: "- "), 2, text.count)
        case .numberedList:
            return (numberLines(text), 3, text.count)
        case .quote:
            return (prefixLines(text, prefix: "> "), 2, text.count)
        case .link:
            return ("[\(text)](https://example.com)", 1, text.count)
        case .code:
            if text.contains("\n") {
                return ("```\n\(text)\n```", 4, text.count)
            }
            return ("`\(text)`", 1, text.count)
        }
    }

    private static func prefixLines(_ text: String, prefix: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private static func numberLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
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

    private func appendTab(_ document: ViewerDocument) {
        let tab = DocumentTab(document: document)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func updateSidebarForSelectedDocument() {
        switch document {
        case .markdown:
            sidebarMode = .contents
        case .pdf:
            sidebarMode = .pages
        case nil:
            sidebarMode = .recent
        }
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

private extension NSView {
    func firstMarkdownTextView(matching text: String) -> NSTextView? {
        if let textView = self as? NSTextView,
           textView.string == text {
            return textView
        }
        for subview in subviews {
            if let textView = subview.firstMarkdownTextView(matching: text) {
                return textView
            }
        }
        return nil
    }
}

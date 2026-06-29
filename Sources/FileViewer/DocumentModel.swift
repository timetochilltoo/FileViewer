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
    case table
    case taskList

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
        case .table: "Insert Table"
        case .taskList: "Task List"
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
        case .table: "tablecells"
        case .taskList: "checklist"
        }
    }

    var helpText: String {
        switch self {
        case .bold: "Make selected text bold, or remove bold if it is already bold."
        case .italic: "Make selected text italic, or remove italic if it is already italic."
        case .underline: "Underline selected text using the app’s <u>underline</u> Markdown convenience."
        case .heading: "Turn the selected line into a heading, or remove heading marks from an existing heading."
        case .bulletList: "Turn selected line(s) into bullet list items."
        case .numberedList: "Turn selected line(s) into a numbered list."
        case .quote: "Turn selected line(s) into a block quote."
        case .link: "Insert a Markdown link around selected text."
        case .code: "Format selected text as inline code, or selected lines as a code block."
        case .table: "Insert a simple Markdown table, or convert comma-separated selected lines into a table."
        case .taskList: "Insert a task checklist, or convert selected lines into unchecked tasks."
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
        case .table: "table"
        case .taskList: "task"
        }
    }

    var formatsWholeLines: Bool {
        switch self {
        case .heading, .bulletList, .numberedList, .quote, .table, .taskList:
            true
        case .bold, .italic, .underline, .link, .code:
            false
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

struct PDFOutlineEntry: Identifiable, Equatable {
    let id: String
    let level: Int
    let title: String
    let page: Int?
}

enum ViewerDocument: Equatable {
    case markdown(MarkdownDocument)
    case pdf(PDFViewerDocument)

    var name: String {
        switch self {
        case .markdown(let document): document.name
        case .pdf(let document): document.url.lastPathComponent
        }
    }

    var url: URL? {
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
    var searchMatchIndex: Int
    var searchMatchCount: Int
    var markdownSourceScrollY: Double
    var markdownPreviewScrollY: Double
    var pdfPage: Int
    var pdfPageCount: Int
    var pdfScale: CGFloat

    init(document: ViewerDocument) {
        id = UUID()
        self.document = document
        searchText = ""
        searchMatchIndex = 0
        searchMatchCount = 0
        markdownSourceScrollY = 0
        markdownPreviewScrollY = 0
        pdfPage = 1
        if case .pdf(let pdf) = document {
            pdfPageCount = pdf.document.pageCount
        } else {
            pdfPageCount = 0
        }
        pdfScale = 1.0
    }

    init(document: ViewerDocument, pdfPage: Int, pdfScale: CGFloat) {
        self.init(document: document)
        self.pdfPage = max(1, pdfPage)
        self.pdfScale = max(0.1, pdfScale)
    }

    init(document: ViewerDocument, markdownSourceScrollY: Double, markdownPreviewScrollY: Double) {
        self.init(document: document)
        self.markdownSourceScrollY = max(0, markdownSourceScrollY)
        self.markdownPreviewScrollY = max(0, markdownPreviewScrollY)
    }
}

struct SavedSessionWindow: Codable, Equatable {
    var tabs: [SavedSessionTab]
    var selectedTabIndex: Int
}

struct SavedSessionTab: Codable, Equatable {
    var kind: DocumentKind
    var path: String
    var markdownSourceScrollY: Double?
    var markdownPreviewScrollY: Double?
    var pdfPage: Int
    var pdfScale: Double
}

struct SavedPDFState: Codable, Equatable {
    var path: String
    var pdfPage: Int
    var pdfScale: Double
}

struct SavedMarkdownState: Codable, Equatable {
    var path: String
    var sourceScrollY: Double
    var previewScrollY: Double
}

struct MarkdownDocument: Equatable {
    var url: URL?
    var untitledName: String
    var text: String
    var savedText: String

    var hasUnsavedChanges: Bool {
        text != savedText
    }

    var name: String {
        url?.lastPathComponent ?? untitledName
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
    private static let sessionKey = "FileViewer.session.windows"
    private static let pdfStateKey = "FileViewer.pdf.lastStates"
    private static let markdownStateKey = "FileViewer.markdown.lastStates"
    private weak var lastActiveMarkdownTextView: NSTextView?
    private weak var lastActiveMarkdownPreviewTextView: NSTextView?
    private var lastActiveMarkdownSelectionKind: MarkdownSelectionKind = .source

    private enum MarkdownSelectionKind {
        case source
        case preview
    }

    private(set) var restoredFromSession = false

    init(opening urls: [URL] = []) {
        loadSettings()
        urls.forEach { open(url: $0) }
    }

    init(restoring window: SavedSessionWindow) {
        loadSettings()
        restore(window: window)
        restoredFromSession = !tabs.isEmpty
    }

    var selectedTab: DocumentTab? {
        guard let index = selectedTabIndex else { return nil }
        return tabs[index]
    }

    var canAcceptExternalOpenInCurrentWindow: Bool {
        tabs.isEmpty
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
            tabs[index].searchMatchIndex = 0
            tabs[index].searchMatchCount = searchMatchCount(for: newValue, in: tabs[index].document)
        }
    }

    var searchMatchIndex: Int {
        get { selectedTab?.searchMatchIndex ?? 0 }
        set {
            guard let index = selectedTabIndex else { return }
            objectWillChange.send()
            tabs[index].searchMatchIndex = max(0, newValue)
        }
    }

    var searchMatchCount: Int {
        get {
            if isMarkdownDocument {
                return markdownMatchCount()
            }
            return selectedTab?.searchMatchCount ?? 0
        }
        set {
            guard let index = selectedTabIndex else { return }
            objectWillChange.send()
            tabs[index].searchMatchCount = max(0, newValue)
            if tabs[index].searchMatchIndex >= tabs[index].searchMatchCount {
                tabs[index].searchMatchIndex = max(0, tabs[index].searchMatchCount - 1)
            }
        }
    }

    var searchStatusText: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "" }
        let count = searchMatchCount
        guard count > 0 else { return "0 matches" }
        let current = min(searchMatchIndex, count - 1) + 1
        if isPDFDocument {
            return "PDF: \(current) of \(count)"
        }
        return "\(current) of \(count)"
    }

    var canNavigateSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchMatchCount > 0
    }

    func previousSearchMatch() {
        let count = searchMatchCount
        guard count > 0 else { return }
        searchMatchIndex = (searchMatchIndex - 1 + count) % count
    }

    func nextSearchMatch() {
        let count = searchMatchCount
        guard count > 0 else { return }
        searchMatchIndex = (searchMatchIndex + 1) % count
    }

    private func searchMatchCount(for searchText: String, in document: ViewerDocument) -> Int {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return 0 }
        switch document {
        case .markdown(let markdown):
            return Self.markdownMatchCount(in: markdown.text, query: query)
        case .pdf(let pdf):
            return pdf.document.findString(query, withOptions: [.caseInsensitive]).count
        }
    }

    var pdfPage: Int {
        get { selectedTab?.pdfPage ?? 1 }
        set {
            guard let index = selectedTabIndex else { return }
            objectWillChange.send()
            tabs[index].pdfPage = newValue
            savePDFStateIfNeeded(for: tabs[index])
            saveCurrentSession()
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
            savePDFStateIfNeeded(for: tabs[index])
            saveCurrentSession()
        }
    }

    var markdownSourceScrollY: Double {
        selectedTab?.markdownSourceScrollY ?? 0
    }

    var markdownPreviewScrollY: Double {
        selectedTab?.markdownPreviewScrollY ?? 0
    }

    var markdownHeadings: [MarkdownHeading] {
        guard case .markdown(let document) = document else { return [] }
        return Self.extractHeadings(from: document.text)
    }

    var pdfOutlineEntries: [PDFOutlineEntry] {
        guard case .pdf(let document) = document else { return [] }
        return Self.extractPDFOutline(from: document.document)
    }

    var canSaveMarkdown: Bool {
        guard case .markdown(let document) = document else { return false }
        return document.url == nil || document.hasUnsavedChanges
    }

    var isMarkdownDocument: Bool {
        if case .markdown = document { return true }
        return false
    }

    var isPDFDocument: Bool {
        if case .pdf = document { return true }
        return false
    }

    var canPrintDocument: Bool {
        document != nil
    }

    func newMarkdownDocument() {
        let untitledCount = tabs.reduce(0) { count, tab in
            if case .markdown(let markdown) = tab.document,
               markdown.url == nil {
                return count + 1
            }
            return count
        }
        let name = untitledCount == 0 ? "Untitled.md" : "Untitled \(untitledCount + 1).md"
        appendTab(.markdown(MarkdownDocument(url: nil, untitledName: name, text: "", savedText: "")))
        sidebarMode = .contents
        statusMessage = "New Markdown document."
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
        syncVisibleDocumentState()
        statusMessage = ""
        do {
            if Self.isMarkdown(url) {
                let text = try String(contentsOf: url, encoding: .utf8)
                let savedState = Self.loadMarkdownState(for: url)
                appendTab(DocumentTab(
                    document: .markdown(MarkdownDocument(
                        url: url,
                        untitledName: url.lastPathComponent,
                        text: text,
                        savedText: text
                    )),
                    markdownSourceScrollY: savedState?.sourceScrollY ?? 0,
                    markdownPreviewScrollY: savedState?.previewScrollY ?? 0
                ))
                sidebarMode = .contents
                addRecent(name: url.lastPathComponent, kind: .markdown, url: url)
                saveCurrentSession()
                return
            }

            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                let savedState = Self.loadPDFState(for: url)
                appendTab(DocumentTab(
                    document: .pdf(PDFViewerDocument(url: url, document: pdf)),
                    pdfPage: savedState?.pdfPage ?? 1,
                    pdfScale: CGFloat(savedState?.pdfScale ?? 1.0)
                ))
                sidebarMode = .pages
                addRecent(name: url.lastPathComponent, kind: .pdf, url: url)
                saveCurrentSession()
                return
            }

            statusMessage = "This file type is not supported yet."
        } catch {
            statusMessage = "Could not open this file."
        }
    }

    func selectTab(_ id: DocumentTab.ID) {
        syncVisibleDocumentState()
        selectedTabID = id
        statusMessage = ""
        updateSidebarForSelectedDocument()
        saveCurrentSession()
    }

    func requestCloseTab(_ id: DocumentTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard canCloseTab(at: index) else { return }
        closeTab(at: index)
    }

    func canCloseAllDocuments() -> Bool {
        syncVisibleDocumentState()
        let tabIDs = tabs.map(\.id)
        for id in tabIDs {
            guard let index = tabs.firstIndex(where: { $0.id == id }) else { continue }
            guard canCloseTab(at: index) else { return false }
        }
        return true
    }

    private func canCloseTab(at index: Int) -> Bool {
        guard tabs.indices.contains(index) else { return true }
        guard case .markdown(let markdown) = tabs[index].document,
              markdown.hasUnsavedChanges else {
            return true
        }

        switch closeConfirmation(for: markdown) {
        case .save:
            return saveMarkdownTab(at: index)
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        syncVisibleDocumentState()
        savePDFStateIfNeeded(for: tabs[index])
        saveMarkdownStateIfNeeded(for: tabs[index])
        let id = tabs[index].id
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
            updateSidebarForSelectedDocument()
        }
        saveCurrentSession()
    }

    func updateMarkdown(_ text: String) {
        guard case .markdown(var markdown) = document else { return }
        markdown.text = text
        document = .markdown(markdown)
    }

    func saveMarkdown() {
        guard case .markdown(var markdown) = document else { return }
        guard let url = markdown.url else {
            saveMarkdownAs()
            return
        }

        do {
            try markdown.text.write(to: url, atomically: true, encoding: .utf8)
            markdown.savedText = markdown.text
            document = .markdown(markdown)
            statusMessage = "Saved."
        } catch {
            statusMessage = "Could not save this Markdown file."
        }
    }

    private enum CloseConfirmationAction {
        case save
        case discard
        case cancel
    }

    private func closeConfirmation(for markdown: MarkdownDocument) -> CloseConfirmationAction {
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(markdown.name)” before closing?"
        alert.informativeText = "If you don’t save, your changes will be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func saveMarkdownTab(at index: Int) -> Bool {
        guard tabs.indices.contains(index),
              case .markdown(var markdown) = tabs[index].document else {
            return true
        }

        guard let url = markdown.url else {
            return saveMarkdownTabAs(at: index)
        }

        do {
            try markdown.text.write(to: url, atomically: true, encoding: .utf8)
            markdown.savedText = markdown.text
            tabs[index].document = .markdown(markdown)
            statusMessage = "Saved."
            return true
        } catch {
            statusMessage = "Could not save this Markdown file."
            showSaveFailedAlert(for: markdown)
            return false
        }
    }

    private func saveMarkdownTabAs(at index: Int) -> Bool {
        guard tabs.indices.contains(index),
              case .markdown(var markdown) = tabs[index].document else {
            return true
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = markdown.name
        panel.allowedContentTypes = [.text, .plainText]

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            try markdown.text.write(to: url, atomically: true, encoding: .utf8)
            markdown = MarkdownDocument(
                url: url,
                untitledName: url.lastPathComponent,
                text: markdown.text,
                savedText: markdown.text
            )
            tabs[index].document = .markdown(markdown)
            addRecent(name: url.lastPathComponent, kind: .markdown, url: url)
            statusMessage = "Saved as new Markdown file."
            return true
        } catch {
            statusMessage = "Could not save the new Markdown file."
            showSaveFailedAlert(for: markdown)
            return false
        }
    }

    private func showSaveFailedAlert(for markdown: MarkdownDocument) {
        let alert = NSAlert()
        alert.messageText = "Could not save “\(markdown.name)”"
        alert.informativeText = "The document was not closed, so your unsaved changes are still open."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func saveMarkdownAs() {
        guard case .markdown(var markdown) = document else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = markdown.name
        panel.allowedContentTypes = [.text, .plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.text.write(to: url, atomically: true, encoding: .utf8)
                markdown = MarkdownDocument(
                    url: url,
                    untitledName: url.lastPathComponent,
                    text: markdown.text,
                    savedText: markdown.text
                )
                document = .markdown(markdown)
                addRecent(name: url.lastPathComponent, kind: .markdown, url: url)
                statusMessage = "Saved as new Markdown file."
            } catch {
                statusMessage = "Could not save the new Markdown file."
            }
        }
    }

    func printDocument() {
        switch document {
        case .pdf(let pdf):
            let printInfo = NSPrintInfo.shared
            let operation = pdf.document.printOperation(
                for: printInfo,
                scalingMode: .pageScaleDownToFit,
                autoRotate: true
            )
            operation?.run()
        case .markdown(let markdown):
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            textView.string = markdown.text
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.isEditable = false
            let operation = NSPrintOperation(view: textView)
            operation.jobTitle = markdown.name
            operation.run()
        case nil:
            statusMessage = "Open a document before printing."
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
        return Self.markdownMatchCount(in: markdown.text, query: query)
    }

    private static func markdownMatchCount(in text: String, query: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: [.caseInsensitive], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    func applyMarkdownFormat(_ command: MarkdownFormatCommand) {
        guard isMarkdownDocument else { return }
        if let firstResponder = NSApp.keyWindow?.firstResponder as? NSTextView,
           firstResponder.string == currentMarkdownText {
            lastActiveMarkdownSelectionKind = .source
        } else if let firstResponder = NSApp.keyWindow?.firstResponder as? NSTextView,
                  firstResponder === lastActiveMarkdownPreviewTextView {
            lastActiveMarkdownSelectionKind = .preview
        }

        if lastActiveMarkdownSelectionKind == .preview,
           let previewTextView = markdownPreviewTextViewForFormatting(),
           applyMarkdownFormatFromPreview(command, previewTextView: previewTextView) {
            return
        }

        guard let textView = markdownTextViewForFormatting() else {
            if let previewTextView = markdownPreviewTextViewForFormatting(),
               applyMarkdownFormatFromPreview(command, previewTextView: previewTextView) {
                return
            }
            insertMarkdownFallback(for: command)
            return
        }

        let originalRange = textView.selectedRange()
        let backingString = textView.string as NSString
        let selectedRange = command.formatsWholeLines
            ? backingString.lineRange(for: originalRange)
            : originalRange
        let replacement = Self.markdownReplacement(
            for: command,
            in: textView.string,
            selectedRange: selectedRange
        )
        textView.insertText(replacement.text, replacementRange: replacement.range)
        textView.setSelectedRange(replacement.selection)
        textView.window?.makeFirstResponder(textView)
        updateMarkdown(textView.string)
    }

    func rememberMarkdownTextView(_ textView: NSTextView) {
        lastActiveMarkdownTextView = textView
        lastActiveMarkdownSelectionKind = .source
    }

    func rememberMarkdownPreviewTextView(_ textView: NSTextView) {
        lastActiveMarkdownPreviewTextView = textView
        lastActiveMarkdownSelectionKind = .preview
    }

    func recordMarkdownSourceScrollY(_ scrollY: Double) {
        guard let index = selectedTabIndex,
              case .markdown = tabs[index].document else { return }
        let safeScrollY = max(0, scrollY)
        guard abs(tabs[index].markdownSourceScrollY - safeScrollY) > 0.5 else { return }
        tabs[index].markdownSourceScrollY = safeScrollY
    }

    func recordMarkdownPreviewScrollY(_ scrollY: Double) {
        guard let index = selectedTabIndex,
              case .markdown = tabs[index].document else { return }
        let safeScrollY = max(0, scrollY)
        guard abs(tabs[index].markdownPreviewScrollY - safeScrollY) > 0.5 else { return }
        tabs[index].markdownPreviewScrollY = safeScrollY
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

    private func markdownPreviewTextViewForFormatting() -> NSTextView? {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView === lastActiveMarkdownPreviewTextView {
            return textView
        }
        if let textView = lastActiveMarkdownPreviewTextView,
           textView.window != nil {
            return textView
        }
        return nil
    }

    private var currentMarkdownText: String {
        guard case .markdown(let markdown) = document else { return "" }
        return markdown.text
    }

    private func insertMarkdownFallback(for command: MarkdownFormatCommand) {
        guard case .markdown(var markdown) = document else { return }
        let replacement = Self.markdownReplacement(
            for: command,
            in: "",
            selectedRange: NSRange(location: 0, length: 0)
        )
        markdown.text += markdown.text.hasSuffix("\n") || markdown.text.isEmpty
            ? replacement.text
            : "\n" + replacement.text
        document = .markdown(markdown)
    }

    private func applyMarkdownFormatFromPreview(
        _ command: MarkdownFormatCommand,
        previewTextView: NSTextView
    ) -> Bool {
        let selectedPreviewText = (previewTextView.string as NSString)
            .substring(with: previewTextView.selectedRange())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedPreviewText.isEmpty else { return false }
        guard case .markdown(var markdown) = document else { return false }
        guard let sourceRange = Self.sourceRange(
            forPreviewSelection: selectedPreviewText,
            command: command,
            in: markdown.text
        ) else {
            statusMessage = "Could not find that preview selection in the Markdown source."
            return false
        }

        let replacement = Self.markdownReplacement(
            for: command,
            in: markdown.text,
            selectedRange: sourceRange
        )
        markdown.text = (markdown.text as NSString).replacingCharacters(
            in: replacement.range,
            with: replacement.text
        )
        document = .markdown(markdown)
        statusMessage = "Updated Markdown from preview selection."
        return true
    }

    private static func sourceRange(
        forPreviewSelection selectedText: String,
        command: MarkdownFormatCommand,
        in markdown: String
    ) -> NSRange? {
        if command.formatsWholeLines,
           let lineRange = sourceLineRange(forPreviewSelection: selectedText, in: markdown) {
            return lineRange
        }

        let backingString = markdown as NSString
        let exactRange = backingString.range(
            of: selectedText,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        guard exactRange.location != NSNotFound else {
            return nil
        }
        return command.formatsWholeLines
            ? backingString.lineRange(for: exactRange)
            : exactRange
    }

    private static func sourceLineRange(
        forPreviewSelection selectedText: String,
        in markdown: String
    ) -> NSRange? {
        let backingString = markdown as NSString
        let fullRange = NSRange(location: 0, length: backingString.length)
        var lineRanges: [NSRange] = []
        backingString.enumerateSubstrings(
            in: fullRange,
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosingRange, _ in
            lineRanges.append(enclosingRange)
        }

        for lineRange in lineRanges {
            let line = backingString.substring(with: lineRange)
                .trimmingCharacters(in: .newlines)
            let comparableLine = headingBody(line)
                ?? line
                    .replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\s*\d+\.\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\s*>\s?"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            if comparableLine.caseInsensitiveCompare(selectedText) == .orderedSame {
                return lineRange
            }
        }

        return nil
    }

    private struct MarkdownFormatReplacement {
        let range: NSRange
        let text: String
        let selection: NSRange
    }

    private static func markdownReplacement(
        for command: MarkdownFormatCommand,
        in fullText: String,
        selectedRange: NSRange
    ) -> MarkdownFormatReplacement {
        let backingString = fullText as NSString
        let selectedText = backingString.substring(with: selectedRange)
        let text = selectedText.isEmpty ? command.placeholderText : selectedText

        switch command {
        case .bold:
            return inlineToggle(
                backingString: backingString,
                selectedRange: selectedRange,
                selectedText: selectedText,
                placeholder: text,
                prefix: "**",
                suffix: "**"
            )
        case .italic:
            return inlineToggle(
                backingString: backingString,
                selectedRange: selectedRange,
                selectedText: selectedText,
                placeholder: text,
                prefix: "*",
                suffix: "*",
                avoidBoldMarkers: true
            )
        case .underline:
            return inlineToggle(
                backingString: backingString,
                selectedRange: selectedRange,
                selectedText: selectedText,
                placeholder: text,
                prefix: "<u>",
                suffix: "</u>"
            )
        case .heading:
            return lineToggle(
                selectedRange: selectedRange,
                selectedText: text,
                replacement: headingReplacement(text)
            )
        case .bulletList:
            return lineToggle(
                selectedRange: selectedRange,
                selectedText: text,
                replacement: bulletReplacement(text)
            )
        case .numberedList:
            return lineToggle(
                selectedRange: selectedRange,
                selectedText: text,
                replacement: numberedReplacement(text)
            )
        case .quote:
            return lineToggle(
                selectedRange: selectedRange,
                selectedText: text,
                replacement: quoteReplacement(text)
            )
        case .table:
            return lineToggle(
                selectedRange: selectedRange,
                selectedText: text,
                replacement: tableReplacement(selectedText)
            )
        case .taskList:
            return lineToggle(
                selectedRange: selectedRange,
                selectedText: text,
                replacement: taskListReplacement(selectedText)
            )
        case .link:
            return inlineToggle(
                backingString: backingString,
                selectedRange: selectedRange,
                selectedText: selectedText,
                placeholder: text,
                prefix: "[",
                suffix: "](https://example.com)"
            )
        case .code:
            if text.contains("\n") {
                let replacement = "```\n\(text)\n```"
                return MarkdownFormatReplacement(
                    range: selectedRange,
                    text: replacement,
                    selection: NSRange(location: selectedRange.location + 4, length: (text as NSString).length)
                )
            }
            return inlineToggle(
                backingString: backingString,
                selectedRange: selectedRange,
                selectedText: selectedText,
                placeholder: text,
                prefix: "`",
                suffix: "`"
            )
        }
    }

    private static func inlineToggle(
        backingString: NSString,
        selectedRange: NSRange,
        selectedText: String,
        placeholder: String,
        prefix: String,
        suffix: String,
        avoidBoldMarkers: Bool = false
    ) -> MarkdownFormatReplacement {
        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length
        let selectedLength = (selectedText as NSString).length

        if selectedLength >= prefixLength + suffixLength,
           selectedText.hasPrefix(prefix),
           selectedText.hasSuffix(suffix) {
            let innerRange = NSRange(
                location: prefixLength,
                length: selectedLength - prefixLength - suffixLength
            )
            let innerText = (selectedText as NSString).substring(with: innerRange)
            return MarkdownFormatReplacement(
                range: selectedRange,
                text: innerText,
                selection: NSRange(location: selectedRange.location, length: (innerText as NSString).length)
            )
        }

        let canExpandLeft = selectedRange.location >= prefixLength
        let canExpandRight = selectedRange.location + selectedRange.length + suffixLength <= backingString.length
        if canExpandLeft, canExpandRight {
            let leftRange = NSRange(location: selectedRange.location - prefixLength, length: prefixLength)
            let rightRange = NSRange(location: selectedRange.location + selectedRange.length, length: suffixLength)
            let hasMatchingSurroundingMarkers = backingString.substring(with: leftRange) == prefix
                && backingString.substring(with: rightRange) == suffix
            let isSafeSingleItalicToggle = !avoidBoldMarkers
                || !isPartOfDoubleAsterisk(backingString, markerRange: leftRange, checkingLeftSide: true)
                && !isPartOfDoubleAsterisk(backingString, markerRange: rightRange, checkingLeftSide: false)

            if hasMatchingSurroundingMarkers, isSafeSingleItalicToggle {
                let expandedRange = NSRange(
                    location: selectedRange.location - prefixLength,
                    length: selectedRange.length + prefixLength + suffixLength
                )
                return MarkdownFormatReplacement(
                    range: expandedRange,
                    text: selectedText,
                    selection: NSRange(location: expandedRange.location, length: selectedLength)
                )
            }
        }

        let text = selectedText.isEmpty ? placeholder : selectedText
        let replacement = "\(prefix)\(text)\(suffix)"
        return MarkdownFormatReplacement(
            range: selectedRange,
            text: replacement,
            selection: NSRange(location: selectedRange.location + prefixLength, length: (text as NSString).length)
        )
    }

    private static func isPartOfDoubleAsterisk(
        _ backingString: NSString,
        markerRange: NSRange,
        checkingLeftSide: Bool
    ) -> Bool {
        guard markerRange.length == 1,
              backingString.substring(with: markerRange) == "*" else {
            return false
        }

        let adjacentLocation = checkingLeftSide
            ? markerRange.location - 1
            : markerRange.location + 1
        guard adjacentLocation >= 0, adjacentLocation < backingString.length else {
            return false
        }
        return backingString.substring(with: NSRange(location: adjacentLocation, length: 1)) == "*"
    }

    private static func lineToggle(
        selectedRange: NSRange,
        selectedText: String,
        replacement: String
    ) -> MarkdownFormatReplacement {
        MarkdownFormatReplacement(
            range: selectedRange,
            text: replacement,
            selection: NSRange(location: selectedRange.location, length: (replacement as NSString).length)
        )
    }

    private static func headingReplacement(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let allNonEmptyLinesAreHeadings = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { headingBody(String($0)) != nil }

        return lines
            .map { line -> String in
                let lineText = String(line)
                let trimmed = lineText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return lineText }
                if allNonEmptyLinesAreHeadings, let body = headingBody(lineText) {
                    return body
                }
                return "## \(headingBody(lineText) ?? trimmed)"
            }
            .joined(separator: "\n")
    }

    private static func headingBody(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let headingMarks = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(headingMarks),
              trimmed.dropFirst(headingMarks).first?.isWhitespace == true else {
            return nil
        }
        return String(trimmed.dropFirst(headingMarks)).trimmingCharacters(in: .whitespaces)
    }

    private static func bulletReplacement(_ text: String) -> String {
        prefixToggle(
            text,
            prefix: "- ",
            removalPattern: #"^\s*[-*]\s+"#
        )
    }

    private static func quoteReplacement(_ text: String) -> String {
        prefixToggle(
            text,
            prefix: "> ",
            removalPattern: #"^\s*>\s?"#
        )
    }

    private static func numberedReplacement(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let allNonEmptyLinesAreNumbered = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { line in
                line.range(of: #"^\s*\d+\.\s+"#, options: .regularExpression) != nil
            }

        if allNonEmptyLinesAreNumbered {
            return lines
                .map { line -> String in
                    String(line).replacingOccurrences(
                        of: #"^\s*\d+\.\s+"#,
                        with: "",
                        options: .regularExpression
                    )
                }
                .joined(separator: "\n")
        }

        return lines.enumerated()
            .map { index, line in
                let lineText = String(line)
                guard !lineText.trimmingCharacters(in: .whitespaces).isEmpty else { return lineText }
                return "\(index + 1). \(lineText)"
            }
            .joined(separator: "\n")
    }

    private static func tableReplacement(_ selectedText: String) -> String {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return """
            | Column 1 | Column 2 | Column 3 |
            |---|---|---|
            | Value 1 | Value 2 | Value 3 |
            | Value 4 | Value 5 | Value 6 |
            """
        }

        let rows = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let cells = String(line)
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                return "| " + cells.joined(separator: " | ") + " |"
            }

        guard let firstRow = rows.first else { return tableReplacement("") }
        let columnCount = max(firstRow.filter { $0 == "|" }.count - 1, 1)
        let separator = "| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |"
        return ([firstRow, separator] + rows.dropFirst()).joined(separator: "\n")
    }

    private static func taskListReplacement(_ selectedText: String) -> String {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return """
            - [ ] Task 1
            - [ ] Task 2
            - [ ] Task 3
            """
        }

        return selectedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let lineText = String(line)
                guard !lineText.trimmingCharacters(in: .whitespaces).isEmpty else { return lineText }
                let withoutExistingMarker = lineText.replacingOccurrences(
                    of: #"^\s*[-*+]\s+(\[[ xX]\]\s+)?"#,
                    with: "",
                    options: .regularExpression
                )
                return "- [ ] \(withoutExistingMarker)"
            }
            .joined(separator: "\n")
    }

    private static func prefixToggle(
        _ text: String,
        prefix: String,
        removalPattern: String
    ) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let allNonEmptyLinesHavePrefix = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { line in
                line.range(of: removalPattern, options: .regularExpression) != nil
            }

        return lines
            .map { line -> String in
                let lineText = String(line)
                guard !lineText.trimmingCharacters(in: .whitespaces).isEmpty else { return lineText }
                if allNonEmptyLinesHavePrefix {
                    return lineText.replacingOccurrences(
                        of: removalPattern,
                        with: "",
                        options: .regularExpression
                    )
                }
                return prefix + lineText
            }
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

    static func loadSavedSessionWindows() -> [SavedSessionWindow] {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let decoded = try? JSONDecoder().decode([SavedSessionWindow].self, from: data) else {
            return []
        }
        return decoded.filter { !$0.tabs.isEmpty }
    }

    static func saveSessionWindows(_ windows: [SavedSessionWindow]) {
        let restorableWindows = windows.filter { !$0.tabs.isEmpty }
        guard let data = try? JSONEncoder().encode(restorableWindows) else { return }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    private static func loadPDFStates() -> [SavedPDFState] {
        guard let data = UserDefaults.standard.data(forKey: pdfStateKey),
              let decoded = try? JSONDecoder().decode([SavedPDFState].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func savePDFStates(_ states: [SavedPDFState]) {
        let trimmed = Array(states.prefix(100))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: pdfStateKey)
    }

    private static func loadPDFState(for url: URL) -> SavedPDFState? {
        loadPDFStates().first { $0.path == url.path }
    }

    private static func loadMarkdownStates() -> [SavedMarkdownState] {
        guard let data = UserDefaults.standard.data(forKey: markdownStateKey),
              let decoded = try? JSONDecoder().decode([SavedMarkdownState].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveMarkdownStates(_ states: [SavedMarkdownState]) {
        let trimmed = Array(states.prefix(100))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: markdownStateKey)
    }

    private static func loadMarkdownState(for url: URL) -> SavedMarkdownState? {
        loadMarkdownStates().first { $0.path == url.path }
    }

    private func savePDFStateIfNeeded(for tab: DocumentTab) {
        guard case .pdf(let pdf) = tab.document else { return }
        var states = Self.loadPDFStates()
        states.removeAll { $0.path == pdf.url.path }
        states.insert(SavedPDFState(
            path: pdf.url.path,
            pdfPage: tab.pdfPage,
            pdfScale: Double(tab.pdfScale)
        ), at: 0)
        Self.savePDFStates(states)
    }

    private func saveMarkdownStateIfNeeded(for tab: DocumentTab) {
        guard case .markdown(let markdown) = tab.document,
              let url = markdown.url else { return }
        var states = Self.loadMarkdownStates()
        states.removeAll { $0.path == url.path }
        states.insert(SavedMarkdownState(
            path: url.path,
            sourceScrollY: tab.markdownSourceScrollY,
            previewScrollY: tab.markdownPreviewScrollY
        ), at: 0)
        Self.saveMarkdownStates(states)
    }

    func sessionSnapshot() -> SavedSessionWindow? {
        syncVisibleDocumentState()
        let restorableTabs = tabs.compactMap { tab -> SavedSessionTab? in
            guard let url = tab.document.url else { return nil }
            if case .pdf = tab.document {
                savePDFStateIfNeeded(for: tab)
            } else if case .markdown = tab.document {
                saveMarkdownStateIfNeeded(for: tab)
            }
            return SavedSessionTab(
                kind: tab.document.kind,
                path: url.path,
                markdownSourceScrollY: tab.markdownSourceScrollY,
                markdownPreviewScrollY: tab.markdownPreviewScrollY,
                pdfPage: tab.pdfPage,
                pdfScale: Double(tab.pdfScale)
            )
        }
        guard !restorableTabs.isEmpty else { return nil }

        let selectedRestorableIndex: Int
        if let selectedTab,
           let selectedURL = selectedTab.document.url,
           let match = restorableTabs.firstIndex(where: { $0.path == selectedURL.path }) {
            selectedRestorableIndex = match
        } else {
            selectedRestorableIndex = min(max(0, selectedTabIndex ?? 0), restorableTabs.count - 1)
        }

        return SavedSessionWindow(
            tabs: restorableTabs,
            selectedTabIndex: selectedRestorableIndex
        )
    }

    private func saveCurrentSession() {
        FileViewerWindowRegistry.shared.saveCurrentSession()
    }

    private func syncVisibleDocumentState() {
        syncVisibleMarkdownState()
        syncVisiblePDFState()
    }

    private func syncVisibleMarkdownState() {
        guard isMarkdownDocument else { return }
        NotificationCenter.default.post(name: .markdownSyncCurrentState, object: nil)
    }

    private func syncVisiblePDFState() {
        guard isPDFDocument else { return }
        NotificationCenter.default.post(name: .pdfSyncCurrentState, object: nil)
    }

    func restoreSavedSession(window: SavedSessionWindow) {
        guard tabs.isEmpty else { return }
        restore(window: window)
        restoredFromSession = !tabs.isEmpty
    }

    private func restore(window: SavedSessionWindow) {
        for savedTab in window.tabs {
            let url = URL(fileURLWithPath: savedTab.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            do {
                switch savedTab.kind {
                case .markdown:
                    guard Self.isMarkdown(url) else { continue }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let savedState = Self.loadMarkdownState(for: url)
                    appendTab(DocumentTab(
                        document: .markdown(MarkdownDocument(
                            url: url,
                            untitledName: url.lastPathComponent,
                            text: text,
                            savedText: text
                        )),
                        markdownSourceScrollY: savedState?.sourceScrollY ?? savedTab.markdownSourceScrollY ?? 0,
                        markdownPreviewScrollY: savedState?.previewScrollY ?? savedTab.markdownPreviewScrollY ?? 0
                    ))
                case .pdf:
                    guard url.pathExtension.lowercased() == "pdf",
                          let pdf = PDFDocument(url: url) else { continue }
                    let savedState = Self.loadPDFState(for: url)
                    appendTab(DocumentTab(
                        document: .pdf(PDFViewerDocument(url: url, document: pdf)),
                        pdfPage: savedState?.pdfPage ?? savedTab.pdfPage,
                        pdfScale: CGFloat(savedState?.pdfScale ?? savedTab.pdfScale)
                    ))
                }
            } catch {
                continue
            }
        }

        if tabs.indices.contains(window.selectedTabIndex) {
            selectedTabID = tabs[window.selectedTabIndex].id
        } else {
            selectedTabID = tabs.first?.id
        }
        updateSidebarForSelectedDocument()
    }

    private func appendTab(_ document: ViewerDocument) {
        let tab = DocumentTab(document: document)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func appendTab(_ tab: DocumentTab) {
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

    static func extractPDFOutline(from document: PDFDocument) -> [PDFOutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [PDFOutlineEntry] = []

        func appendChildren(of outline: PDFOutline, level: Int, path: String) {
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                let childPath = "\(path).\(index)"
                let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                let page: Int?
                if let destinationPage = destination?.page {
                    let pageIndex = document.index(for: destinationPage)
                    page = pageIndex == NSNotFound ? nil : pageIndex + 1
                } else {
                    page = nil
                }

                if let title, !title.isEmpty {
                    entries.append(PDFOutlineEntry(
                        id: childPath,
                        level: level,
                        title: title,
                        page: page
                    ))
                }

                appendChildren(of: child, level: level + 1, path: childPath)
            }
        }

        appendChildren(of: root, level: 1, path: "root")
        return entries
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

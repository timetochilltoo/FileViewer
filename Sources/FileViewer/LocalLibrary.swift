import Foundation
import PDFKit

/// A local-only entry built from a readable Markdown or PDF file. The full
/// searchable text stays in memory for the current app session; normalized
/// folder/file paths and user tags are the only Library data persisted by AppModel.
struct LibraryIndexEntry: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let kind: DocumentKind
    let folderPath: String
    let titleText: String
    let searchableText: String
    let modifiedAt: Date
    let isRecent: Bool
    let isExplicit: Bool

    init(
        url: URL,
        name: String,
        kind: DocumentKind,
        folderPath: String,
        titleText: String,
        searchableText: String,
        modifiedAt: Date,
        isRecent: Bool = false,
        isExplicit: Bool = false
    ) {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        self.id = normalizedURL.path
        self.url = normalizedURL
        self.name = name
        self.kind = kind
        self.folderPath = folderPath
        self.titleText = titleText
        self.searchableText = searchableText
        self.modifiedAt = modifiedAt
        self.isRecent = isRecent
        self.isExplicit = isExplicit
    }
}

struct LibrarySearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let kind: DocumentKind
    let location: String
    let snippet: String
    let reason: String
    let modifiedAt: Date
    let isRecent: Bool
    let isExplicit: Bool
    let tags: [String]
}

/// Builds a bounded in-memory index from explicitly added files, recent files,
/// and selected local folders. It never follows network URLs and never writes
/// document text to preferences or a cache file.
enum LocalLibraryIndexer {
    static let maximumFiles = 2_000
    static let maximumSearchableCharactersPerFile = 200_000
    static let maximumTotalSearchableCharacters = 20_000_000

    static func build(
        roots: [URL],
        recentURLs: [URL],
        libraryFiles: [URL] = []
    ) async -> [LibraryIndexEntry] {
        let worker = Task.detached(priority: .utility) {
            buildSynchronously(roots: roots, recentURLs: recentURLs, libraryFiles: libraryFiles)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func search(
        query: String,
        entries: [LibraryIndexEntry],
        tagsByPath: [String: [String]] = [:],
        limit: Int = 200
    ) -> [LibrarySearchResult] {
        let terms = normalizedTerms(query)
        let sortedEntries = entries.sorted { lhs, rhs in
            if lhs.isRecent != rhs.isRecent { return lhs.isRecent }
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        guard !terms.isEmpty else {
            return sortedEntries.prefix(limit).map {
                LibrarySearchResult(
                    id: $0.id,
                    url: $0.url,
                    name: $0.name,
                    kind: $0.kind,
                    location: $0.folderPath,
                    snippet: firstSnippet(in: $0.searchableText),
                    reason: $0.isRecent ? "Recent file" : ($0.isExplicit ? "Added to Library" : "Indexed file"),
                    modifiedAt: $0.modifiedAt,
                    isRecent: $0.isRecent,
                    isExplicit: $0.isExplicit,
                    tags: tagsByPath[$0.id] ?? []
                )
            }
        }

        return entries.compactMap { entry -> (score: Int, result: LibrarySearchResult)? in
            let name = folded(entry.name)
            let title = folded(entry.titleText)
            let folder = folded(entry.folderPath)
            let body = folded(entry.searchableText)
            let tags = tagsByPath[entry.id] ?? []
            let tagText = folded(tags.joined(separator: " "))
            let searchable = "\(name)\n\(title)\n\(folder)\n\(tagText)\n\(body)"
            guard terms.allSatisfy({ searchable.contains($0) }) else { return nil }

            var score = 0
            var matchedName = false
            var matchedTitle = false
            var matchedTag = false
            var matchedBody = false
            for term in terms {
                if name.contains(term) {
                    score += 100
                    matchedName = true
                }
                if title.contains(term) {
                    score += 60
                    matchedTitle = true
                }
                if tagText.contains(term) {
                    score += 80
                    matchedTag = true
                }
                if folder.contains(term) { score += 20 }
                if body.contains(term) {
                    score += 10
                    matchedBody = true
                }
            }

            let reason: String
            if matchedName {
                reason = "Match in filename"
            } else if matchedTitle {
                reason = "Match in heading or title"
            } else if matchedTag {
                reason = "Match in tag"
            } else if matchedBody {
                reason = "Match in document text"
            } else {
                reason = "Match in folder"
            }

            return (
                score: score,
                result: LibrarySearchResult(
                    id: entry.id,
                    url: entry.url,
                    name: entry.name,
                    kind: entry.kind,
                    location: entry.folderPath,
                    snippet: matchingSnippet(in: entry.searchableText, terms: terms),
                    reason: reason,
                    modifiedAt: entry.modifiedAt,
                    isRecent: entry.isRecent,
                    isExplicit: entry.isExplicit,
                    tags: tags
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.result.modifiedAt != rhs.result.modifiedAt {
                return lhs.result.modifiedAt > rhs.result.modifiedAt
            }
            if lhs.result.isRecent != rhs.result.isRecent {
                return lhs.result.isRecent
            }
            return lhs.result.name.localizedCaseInsensitiveCompare(rhs.result.name) == .orderedAscending
        }
        .prefix(limit)
        .map(\.result)
    }

    private static func buildSynchronously(
        roots: [URL],
        recentURLs: [URL],
        libraryFiles: [URL]
    ) -> [LibraryIndexEntry] {
        var candidates: [(url: URL, isExplicit: Bool)] = []
        var seenPaths = Set<String>()
        let recentPaths = Set(recentURLs.compactMap { normalizedFileURL($0)?.path })

        func addCandidate(_ url: URL, isExplicit: Bool = false) {
            guard !Task.isCancelled else { return }
            guard let normalized = normalizedFileURL(url),
                  isSupportedFile(normalized),
                  FileManager.default.isReadableFile(atPath: normalized.path),
                  seenPaths.insert(normalized.path).inserted else { return }
            candidates.append((normalized, isExplicit))
        }

        for libraryFile in libraryFiles {
            guard !Task.isCancelled else { return [] }
            addCandidate(libraryFile, isExplicit: true)
        }

        for recentURL in recentURLs {
            guard !Task.isCancelled else { return [] }
            addCandidate(recentURL)
        }

        for root in roots {
            guard !Task.isCancelled else { return [] }
            guard let normalizedRoot = normalizedDirectoryURL(root) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: normalizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isReadableKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return [] }
                if candidates.count >= maximumFiles { break }
                addCandidate(url)
            }
            if candidates.count >= maximumFiles { break }
        }

        var remainingCharacters = maximumTotalSearchableCharacters
        var entries: [LibraryIndexEntry] = []
        for candidate in candidates.prefix(maximumFiles) {
            guard !Task.isCancelled else { return [] }
            guard remainingCharacters > 0,
                  let entry = indexEntry(
                      for: candidate.url,
                      maximumCharacters: min(maximumSearchableCharactersPerFile, remainingCharacters),
                      isRecent: recentPaths.contains(candidate.url.path),
                      isExplicit: candidate.isExplicit
                  ) else { continue }
            remainingCharacters -= entry.searchableText.count
            entries.append(entry)
        }
        return entries
    }

    private static func indexEntry(
        for url: URL,
        maximumCharacters: Int,
        isRecent: Bool,
        isExplicit: Bool
    ) -> LibraryIndexEntry? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate else { return nil }

        let name = url.lastPathComponent
        let kind: DocumentKind
        let titleText: String
        let searchableText: String

        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
            let text = String(decoding: data.prefix(maximumCharacters * 4), as: UTF8.self)
            kind = .markdown
            titleText = markdownHeadings(in: text).joined(separator: " ")
            searchableText = text
        case "pdf":
            guard let document = PDFDocument(url: url) else { return nil }
            let extracted = pdfSearchText(from: document, maximumCharacters: maximumCharacters)
            guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // Keep image-only PDFs in the library so users can find and
                // open them by filename even before OCR is available.
                kind = .pdf
                titleText = pdfTitle(from: document) ?? ""
                searchableText = titleText
                return LibraryIndexEntry(
                    url: url,
                    name: name,
                    kind: kind,
                    folderPath: url.deletingLastPathComponent().path,
                    titleText: titleText,
                    searchableText: searchableText,
                    modifiedAt: modifiedAt,
                    isRecent: isRecent,
                    isExplicit: isExplicit
                )
            }
            kind = .pdf
            titleText = pdfTitle(from: document) ?? ""
            searchableText = extracted
        default:
            return nil
        }

        return LibraryIndexEntry(
            url: url,
            name: name,
            kind: kind,
            folderPath: url.deletingLastPathComponent().path,
            titleText: titleText,
            searchableText: searchableText,
            modifiedAt: modifiedAt,
            isRecent: isRecent,
            isExplicit: isExplicit
        )
    }

    private static func pdfSearchText(from document: PDFDocument, maximumCharacters: Int) -> String {
        var output = ""
        for index in 0..<document.pageCount {
            if Task.isCancelled { return "" }
            guard let page = document.page(at: index) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !pageText.isEmpty {
                output += "\n[Page \(index + 1)]\n\(pageText)"
            }
            for annotation in page.annotations {
                let annotationText = (annotation.contents ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !annotationText.isEmpty {
                    output += "\n[Annotation on Page \(index + 1)]\n\(annotationText)"
                }
            }
            if output.count >= maximumCharacters { break }
        }
        return String(output.prefix(maximumCharacters))
    }

    private static func pdfTitle(from document: PDFDocument) -> String? {
        (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func markdownHeadings(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.first == "#" else { return nil }
            let title = trimmed.drop(while: { $0 == "#" || $0 == " " })
            return title.isEmpty ? nil : String(title)
        }
    }

    private static func normalizedFileURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return normalized
    }

    private static func normalizedDirectoryURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return normalized
    }

    private static func isSupportedFile(_ url: URL) -> Bool {
        ["md", "markdown", "pdf"].contains(url.pathExtension.lowercased())
    }

    private static func normalizedTerms(_ query: String) -> [String] {
        query
            .split { $0.isWhitespace || $0.isNewline }
            .map { folded(String($0)).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func firstSnippet(in text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .map { snippet(String($0)) } ?? ""
    }

    private static func matchingSnippet(in text: String, terms: [String]) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let foldedTerms = terms.map(folded)
        return lines.first(where: { line in
            let candidate = folded(line)
            return foldedTerms.contains(where: candidate.contains)
        }).map(snippet) ?? firstSnippet(in: text)
    }

    private static func snippet(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return compact.count > 180 ? "\(compact.prefix(177))..." : compact
    }
}

/// File-backed operations used by Library actions. Each operation writes a
/// temporary sibling first, validates that the temporary file is readable, and
/// then installs it at the destination so a failed copy leaves the source and
/// any existing destination untouched.
enum LocalLibraryFileOperations {
    static func copyFileAtomically(from source: URL, to destination: URL) -> Bool {
        let normalizedSourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
        let normalizedDestinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        guard source.isFileURL,
              destination.isFileURL,
              normalizedSourcePath != normalizedDestinationPath,
              FileManager.default.isReadableFile(atPath: source.path) else {
            return false
        }

        let temporary = temporaryURL(for: destination)
        defer { try? FileManager.default.removeItem(at: temporary) }

        do {
            try FileManager.default.copyItem(at: source, to: temporary)
            guard FileManager.default.isReadableFile(atPath: temporary.path) else { return false }
            return installTemporaryFile(temporary, at: destination)
        } catch {
            return false
        }
    }

    static func writeMarkdownAtomically(_ text: String, to destination: URL) -> Bool {
        guard destination.isFileURL else { return false }
        let temporary = temporaryURL(for: destination)
        defer { try? FileManager.default.removeItem(at: temporary) }

        do {
            try Data(text.utf8).write(to: temporary)
            guard String(data: try Data(contentsOf: temporary), encoding: .utf8) != nil else {
                return false
            }
            return installTemporaryFile(temporary, at: destination)
        } catch {
            return false
        }
    }

    private static func temporaryURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".FileViewer-" + UUID().uuidString)
            .appendingPathExtension(destination.pathExtension)
    }

    private static func installTemporaryFile(_ temporary: URL, at destination: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(
                    destination,
                    withItemAt: temporary,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            return true
        } catch {
            return false
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

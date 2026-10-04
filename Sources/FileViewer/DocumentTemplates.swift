import AppKit
import Darwin
import PDFKit

struct DocumentTemplate: Identifiable, Equatable {
    enum Kind: String { case markdown, pdf }
    let url: URL
    let kind: Kind
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum TemplateError: LocalizedError {
    case invalidFile, invalidName, unavailable, destinationExists
    var errorDescription: String? {
        switch self {
        case .invalidFile: "Choose a readable UTF-8 Markdown file (up to 5 MiB) or unlocked PDF with pages (up to 100 MiB)."
        case .invalidName: "Use a name of 1–80 characters without slashes, control characters, or a leading dot."
        case .unavailable: "The local template folder is unavailable."
        case .destinationExists: "Choose a new filename. Templates never overwrite existing files."
        }
    }
}

@MainActor
final class DocumentTemplateStore: ObservableObject {
    static let shared = DocumentTemplateStore()
    @Published private(set) var templates: [DocumentTemplate] = []
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FileViewer/Templates", isDirectory: true)
    }

    func refresh() throws {
        try prepareRoot()
        templates = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles])
            .prefix(5000).compactMap { url in
                guard let kind = Self.kind(for: url),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size <= (kind == .markdown ? 5 : 100) * 1024 * 1024 else { return nil }
                return DocumentTemplate(url: url, kind: kind)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func kind(for url: URL) -> DocumentTemplate.Kind? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": .markdown
        case "pdf": .pdf
        default: nil
        }
    }

    static func validate(_ data: Data, kind: DocumentTemplate.Kind) throws {
        guard data.count <= (kind == .markdown ? 5 : 100) * 1024 * 1024 else { throw TemplateError.invalidFile }
        switch kind {
        case .markdown:
            guard String(data: data, encoding: .utf8) != nil else { throw TemplateError.invalidFile }
        case .pdf:
            guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0 else { throw TemplateError.invalidFile }
        }
    }

    /// Bounded descriptor read avoids symlink files and blocking special files.
    static func read(_ url: URL, kind: DocumentTemplate.Kind) throws -> Data {
        guard url.isFileURL else { throw TemplateError.invalidFile }
        let file = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw TemplateError.invalidFile }
        defer { Darwin.close(file) }
        var metadata = stat()
        let limit = (kind == .markdown ? 5 : 100) * 1024 * 1024
        guard fstat(file, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0, metadata.st_size <= limit else { throw TemplateError.invalidFile }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            guard count >= 0 else { throw TemplateError.invalidFile }
            if count == 0 { break }
            guard data.count + count <= limit else { throw TemplateError.invalidFile }
            data.append(contentsOf: buffer.prefix(count))
        }
        try validate(data, kind: kind)
        return data
    }

    @discardableResult
    func save(data: Data, kind: DocumentTemplate.Kind, name: String) throws -> DocumentTemplate {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw TemplateError.invalidName }
        try Self.validate(data, kind: kind)
        try prepareRoot()
        let temporary = root.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let suffix = kind == .markdown ? "md" : "pdf"
        for index in 1...1000 {
            let filename = index == 1 ? name : "\(name) (\(index))"
            let url = root.appendingPathComponent(filename).appendingPathExtension(suffix)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            do { try FileManager.default.moveItem(at: temporary, to: url) }
            catch {
                if FileManager.default.fileExists(atPath: url.path) { continue }
                throw error
            }
            try refresh()
            return DocumentTemplate(url: url, kind: kind)
        }
        throw TemplateError.destinationExists
    }

    func data(for template: DocumentTemplate) throws -> Data {
        guard template.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { throw TemplateError.invalidFile }
        return try Self.read(template.url, kind: template.kind)
    }

    func trash(_ template: DocumentTemplate) throws {
        guard template.url.isFileURL,
              template.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { throw TemplateError.invalidFile }
        let values = try template.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw TemplateError.invalidFile }
        try FileManager.default.trashItem(at: template.url, resultingItemURL: nil)
        try refresh()
    }

    private func prepareRoot() throws {
        guard root.isFileURL else { throw TemplateError.unavailable }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw TemplateError.unavailable }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
}

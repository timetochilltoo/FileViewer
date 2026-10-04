import AppKit
import Darwin
import ImageIO
import UniformTypeIdentifiers

struct MarkdownLocalImage: Equatable {
    let alt: String
    let destination: String

    /// Standalone inline-image syntax; reference definitions and HTML stay literal.
    static func parse(_ line: String) -> Self? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let expression = try? NSRegularExpression(pattern: #"^!\[((?:\\.|[^\]\\])*)\]\((.*)\)$"#),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let altRange = Range(match.range(at: 1), in: text),
              let targetRange = Range(match.range(at: 2), in: text) else { return nil }
        let target = text[targetRange].trimmingCharacters(in: .whitespaces)
        var path = ""
        var suffix = ""
        if target.hasPrefix("<"), let end = target.firstIndex(of: ">") {
            path = String(target[target.index(after: target.startIndex)..<end])
            suffix = String(target[target.index(after: end)...]).trimmingCharacters(in: .whitespaces)
        } else {
            var escaped = false
            var depth = 0
            var end = target.endIndex
            for index in target.indices {
                let character = target[index]
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1; if depth < 0 { return nil } }
                if character.isWhitespace && depth == 0 { end = index; break }
            }
            guard depth == 0 else { return nil }
            path = String(target[..<end])
            suffix = String(target[end...]).trimmingCharacters(in: .whitespaces)
        }
        guard !path.isEmpty else { return nil }
        if !suffix.isEmpty {
            guard let first = suffix.first, let last = suffix.last,
                  (first == "\"" && last == "\"") || (first == "'" && last == "'") || (first == "(" && last == ")") else { return nil }
        }
        return Self(alt: unescape(String(text[altRange])), destination: unescape(path))
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if escaped {
                if !character.isPunctuation && character != " " { result.append("\\") }
                result.append(character)
                escaped = false
            } else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        if escaped { result.append("\\") }
        return result
    }

    func localURL(documentURL: URL?) -> URL? {
        guard let documentURL, documentURL.isFileURL, documentURL.host?.isEmpty != false,
              !destination.hasPrefix("//"),
              let parts = URLComponents(string: destination), parts.query == nil, parts.fragment == nil,
              parts.user == nil, parts.password == nil, parts.host?.isEmpty != false else { return nil }
        let directory = documentURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let candidate: URL
        if let scheme = parts.scheme {
            guard scheme.lowercased() == "file", let url = parts.url, url.isFileURL else { return nil }
            candidate = url.standardizedFileURL
        } else {
            guard let path = destination.removingPercentEncoding, !path.contains("\0") else { return nil }
            candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path).standardizedFileURL : directory.appendingPathComponent(path).standardizedFileURL
        }
        let root = directory.pathComponents
        guard candidate.pathComponents.count > root.count,
              Array(candidate.pathComponents.prefix(root.count)) == root else { return nil }
        return candidate
    }
}

/// Bounded raster decoding, with no URL loader, external resources, or symlink traversal.
enum MarkdownImageLoader {
    static let maximumBytes = 20 * 1024 * 1024
    static let maximumPixels = 40_000_000
    static let maximumDimension = 1200

    @MainActor
    static func load(_ reference: MarkdownLocalImage, documentURL: URL?, remainingBytes: inout Int) -> NSImage? {
        guard let url = reference.localURL(documentURL: documentURL), let documentURL else { return nil }
        let root = documentURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        guard let data = read(url, root: root, limit: min(maximumBytes, remainingBytes)) else { return nil }
        remainingBytes -= data.count
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier, UTType.tiff.identifier,
               UTType.heic.identifier, UTType.webP.identifier, UTType.bmp.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maximumPixels / height,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func read(_ url: URL, root: URL, limit: Int) -> Data? {
        guard limit > 0 else { return nil }
        var directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { return nil }
        defer { close(directory) }
        let components = Array(url.pathComponents.dropFirst(root.pathComponents.count))
        guard let name = components.last else { return nil }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return nil }
            close(directory)
            directory = next
        }
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { return nil }
        defer { close(file) }
        var metadata = stat()
        guard fstat(file, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size > 0, metadata.st_size <= limit else { return nil }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count == 0 { return result }
            guard count > 0, result.count <= limit - count else { return nil }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}

/// TextKit relayout scales the image down when a Split pane or window narrows.
final class MarkdownImageCell: NSTextAttachmentCell {
    override func cellSize() -> NSSize {
        fittedSize(width: 640)
    }

    private func fittedSize(width: CGFloat) -> NSSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let ratio = min(1, min(max(1, width) / image.size.width, 480 / image.size.height))
        return NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let width = min(640, lineFrag.width - textContainer.lineFragmentPadding * 2)
        return NSRect(origin: .zero, size: fittedSize(width: width))
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        image?.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

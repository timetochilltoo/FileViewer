import AppKit
import PDFKit

enum MarkdownExportFormat: String { case pdf, html }

enum MarkdownExportError: LocalizedError {
    case tooLarge, renderFailed, destinationExists, invalidDestination
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Export supports Markdown up to 5 MiB and PDFs up to 1000 pages."
        case .renderFailed: "The exported document could not be rendered or verified."
        case .destinationExists: "Choose a new filename. Export never overwrites an existing or open file."
        case .invalidDestination: "Choose a local destination with the correct file extension."
        }
    }
}

@MainActor
enum MarkdownExport {
    static func data(markdown: String, title: String, documentURL: URL?, format: MarkdownExportFormat) throws -> Data {
        guard markdown.utf8.count <= 5 * 1024 * 1024 else { throw MarkdownExportError.tooLarge }
        switch format {
        case .html: return Data(html(markdown: markdown, title: title, documentURL: documentURL).utf8)
        case .pdf: return try pdf(markdown: markdown, documentURL: documentURL)
        }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Raw HTML is always text. Only a small, explicit set of inline Markdown becomes markup.
    static func inline(_ text: String) -> String {
        let pattern = #"\*\*([^*]+)\*\*|\*([^*]+)\*|`([^`]+)`|<u>(.*?)</u>|\[([^\]]+)\]\(([^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return escape(text) }
        let source = text as NSString
        var output = ""
        var location = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += escape(source.substring(with: NSRange(location: location, length: match.range.location - location)))
            func value(_ index: Int) -> String { source.substring(with: match.range(at: index)) }
            if match.range(at: 1).location != NSNotFound { output += "<strong>\(escape(value(1)))</strong>" }
            else if match.range(at: 2).location != NSNotFound { output += "<em>\(escape(value(2)))</em>" }
            else if match.range(at: 3).location != NSNotFound { output += "<code>\(escape(value(3)))</code>" }
            else if match.range(at: 4).location != NSNotFound { output += "<u>\(escape(value(4)))</u>" }
            else {
                let target = value(6)
                if let url = URL(string: target), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    output += "<a href=\"\(escape(target))\" rel=\"noreferrer noopener\">\(escape(value(5)))</a>"
                } else { output += escape(value(5)) }
            }
            location = NSMaxRange(match.range)
        }
        output += escape(source.substring(from: location))
        return output
    }

    static func html(markdown: String, title: String, documentURL: URL?) -> String {
        var body = ""
        var list: String?
        var imageBudget = 40 * 1024 * 1024
        var imageCount = 0
        func closeList() { if let list { body += "</\(list)>\n" }; list = nil }
        for block in MarkdownPreviewBlock.parse(markdown) {
            switch block.kind {
            case .bullet, .task:
                if list != "ul" { closeList(); body += "<ul>\n"; list = "ul" }
            case .numbered:
                if list != "ol" { closeList(); body += "<ol>\n"; list = "ol" }
            default: closeList()
            }
            switch block.kind {
            case .blank: body += "\n"
            case .heading(let level, let text): body += "<h\(level) id=\"heading-\(block.sourceLocation)\">\(inline(text))</h\(level)>\n"
            case .paragraph(let text): body += "<p>\(inline(text))</p>\n"
            case .quote(let text): body += "<blockquote>\(inline(text))</blockquote>\n"
            case .bullet(let text): body += "<li>\(inline(text))</li>\n"
            case .numbered(let number, let text): body += "<li value=\"\(number)\">\(inline(text))</li>\n"
            case .task(let checked, let text): body += "<li class=\"task\">\(checked ? "☑" : "☐") \(inline(text))</li>\n"
            case .code(let code):
                body += "<figure class=\"code\"><figcaption>\(escape(code.language.isEmpty ? "Code" : code.language))</figcaption><pre><code>\(escape(code.text))</code></pre></figure>\n"
            case .table(let table):
                body += "<table>"
                for (rowIndex, row) in table.rows.enumerated() {
                    body += rowIndex == 0 ? "<thead><tr>" : (rowIndex == 1 ? "<tbody><tr>" : "<tr>")
                    for (column, cell) in row.enumerated() {
                        let tag = rowIndex == 0 ? "th" : "td"
                        let alignment = switch table.alignments[column] { case .left: "left"; case .center: "center"; case .right: "right" }
                        body += "<\(tag) style=\"text-align:\(alignment)\">\(inline(cell))</\(tag)>"
                    }
                    body += rowIndex == 0 ? "</tr></thead>" : "</tr>"
                }
                if table.rows.count > 1 { body += "</tbody>" }
                body += "</table>\n"
            case .image(let reference):
                imageCount += 1
                if imageCount <= 20, let image = MarkdownImageLoader.load(reference, documentURL: documentURL, remainingBytes: &imageBudget),
                   let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    body += "<figure><img src=\"data:image/png;base64,\(png.base64EncodedString())\" alt=\"\(escape(reference.alt))\"><figcaption>\(escape(reference.alt))</figcaption></figure>\n"
                } else { body += "<p class=\"unavailable\">\(escape(reference.alt.isEmpty ? "Image" : reference.alt)) — Image unavailable or blocked</p>\n" }
            }
        }
        closeList()
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>\(escape(title))</title><style>
        body{font:16px/1.55 -apple-system,BlinkMacSystemFont,sans-serif;color:#202124;background:white;max-width:900px;margin:40px auto;padding:0 24px;overflow-wrap:anywhere}
        h1,h2,h3{line-height:1.25}pre,code{font-family:ui-monospace,monospace}pre{white-space:pre-wrap;background:#f3f4f6;padding:14px;border-radius:6px}blockquote{border-left:3px solid #b8bec7;margin-left:0;padding-left:16px;color:#555}
        table{border-collapse:collapse;width:100%;table-layout:fixed;margin:20px 0}th,td{border:1px solid #ccd0d5;padding:8px;vertical-align:top}th{background:#f0f2f5}img{max-width:100%;max-height:480px;object-fit:contain}figure{margin:20px 0}figcaption,.unavailable{font-size:13px;color:#666}.task{list-style:none}a{color:#1459b8}
        @page{size:A4;margin:18mm}@media print{body{margin:0;padding:0;max-width:none}thead{display:table-header-group}img,tr{break-inside:avoid}}
        </style></head><body>\(body)</body></html>
        """
    }

    static func pdf(markdown: String, documentURL: URL?) throws -> Data {
        let info = NSPrintInfo(dictionary: [:])
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        let pageSize = NSSize(width: 523, height: 770)
        let view = MarkdownExportPrintView(size: pageSize, text: MarkdownPreviewTextView.attributedPreview(markdown: markdown, searchText: "", searchMatchIndex: 0, documentURL: documentURL, forExport: true))
        guard view.pageCount <= 1000 else { throw MarkdownExportError.tooLarge }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("FileViewer-Rendered-" + UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporary
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false; operation.showsProgressPanel = false
        guard operation.run(), let data = try? Data(contentsOf: temporary),
              let pdf = PDFDocument(data: data), pdf.pageCount == view.pageCount else { throw MarkdownExportError.renderFailed }
        return data
    }

    static func write(_ data: Data, format: MarkdownExportFormat, to url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == format.rawValue else { throw MarkdownExportError.invalidDestination }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw MarkdownExportError.destinationExists }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".FileViewer-Export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        if format == .pdf {
            guard let expected = PDFDocument(data: data), expected.pageCount > 0,
                  PDFDocument(url: temporary)?.pageCount == expected.pageCount else { throw MarkdownExportError.renderFailed }
        } else {
            guard String(data: data, encoding: .utf8) != nil, try Data(contentsOf: temporary) == data else { throw MarkdownExportError.renderFailed }
        }
        try FileManager.default.moveItem(at: temporary, to: url)
    }
}

@MainActor
private final class MarkdownExportPrintView: NSView {
    let pageSize: NSSize
    let pageRects: [NSRect]
    var pageCount: Int { pageRects.count }
    override var isFlipped: Bool { true }

    init(size: NSSize, text: NSAttributedString) {
        pageSize = size
        let textView = NSTextView(frame: NSRect(origin: .zero, size: NSSize(width: size.width, height: 1)))
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: size.width, height: .greatestFiniteMagnitude)
        textView.isEditable = false
        textView.textStorage?.setAttributedString(text)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let height = ceil(textView.layoutManager!.usedRect(for: textView.textContainer!).height) + 8
        var lineStarts: [CGFloat] = []
        textView.layoutManager!.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: textView.layoutManager!.numberOfGlyphs)) { rect, _, _, _, _ in
            lineStarts.append(rect.minY)
        }
        lineStarts.sort()
        var pages: [NSRect] = []
        var top: CGFloat = 0
        repeat {
            let limit = top + size.height
            let end: CGFloat
            if height <= limit { end = max(top + 1, height) }
            else { end = lineStarts.last(where: { $0 > top + 1 && $0 <= limit }) ?? limit }
            pages.append(NSRect(x: 0, y: top, width: size.width, height: end - top))
            top = end
        } while top < height && pages.count <= 1000
        pageRects = pages
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: size.width, height: max(1, height))))
        appearance = NSAppearance(named: .aqua)
        textView.frame = bounds
        textView.drawsBackground = true
        textView.backgroundColor = .white
        addSubview(textView)
    }
    required init?(coder: NSCoder) { nil }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool { range.pointee = NSRange(location: 1, length: pageCount); return true }
    override func rectForPage(_ page: Int) -> NSRect { pageRects[page - 1] }
}

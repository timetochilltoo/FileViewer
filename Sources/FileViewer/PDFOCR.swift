import PDFKit
import Vision

struct PDFOCRJob: Identifiable, Sendable {
    let id = UUID()
    let tabID: UUID
    let name: String
    let data: Data
    let pages: [Int]
}

enum PDFOCRError: LocalizedError {
    case invalidInput, tooLarge, rendering, tooMuchText
    var errorDescription: String? {
        switch self {
        case .invalidInput: "Choose readable, unlocked PDF pages to recognize."
        case .tooLarge: "Recognize up to 100 pages at a time from a PDF snapshot no larger than 100 MiB."
        case .rendering: "A PDF page could not be rendered for text recognition."
        case .tooMuchText: "The recognized text exceeds 5 MiB. Try fewer pages."
        }
    }
}

enum PDFOCR {
    static let maximumPages = 100
    static let maximumBytes = 100 * 1024 * 1024

    /// Creates its own PDFKit objects on the worker. No live PDF or image objects
    /// cross actors, and neither the snapshot nor recognized text is persisted.
    static func recognize(data: Data, pages: [Int], name: String,
                          progress: @Sendable (Int) async -> Void = { _ in }) async throws -> String {
        guard data.count <= maximumBytes, pages.count <= maximumPages else { throw PDFOCRError.tooLarge }
        guard !pages.isEmpty, Set(pages).count == pages.count,
              let pdf = PDFDocument(data: data), !pdf.isLocked,
              pages.allSatisfy({ (0..<pdf.pageCount).contains($0) }) else { throw PDFOCRError.invalidInput }
        var sections = ["# Recognized PDF text", "Source:\n\n" + literalBlock(name),
                        "Recognized locally on this Mac. Check text and reading order against the original; OCR can make mistakes. The PDF has not been changed."]
        var outputBytes = sections.reduce(0) { $0 + $1.utf8.count }
        for (offset, index) in pages.sorted().enumerated() {
            try Task.checkCancellation()
            let text: String = try autoreleasepool {
                guard let page = pdf.page(at: index) else { throw PDFOCRError.invalidInput }
                let image = try render(page)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            try Task.checkCancellation()
            // Fence OCR as literal Markdown to keep recognized document syntax
            // (including image paths/HTML) from becoming active preview content.
            let literal = text.isEmpty ? "No text recognized on this page." : text
            let section = "## Page \(index + 1)\n\n" + literalBlock(literal)
            outputBytes += section.utf8.count + 2
            guard outputBytes <= 5 * 1024 * 1024 else { throw PDFOCRError.tooMuchText }
            sections.append(section)
            await progress(offset + 1)
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    static func literalBlock(_ text: String) -> String {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return fence + "\n" + text + "\n" + fence
    }

    static func render(_ page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw PDFOCRError.rendering
        }
        let rotated = abs(page.rotation % 180) == 90
        let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let scale = min(3, 2400 / max(size.width, size.height))
        let width = max(1, Int(ceil(size.width * scale)))
        let height = max(1, Int(ceil(size.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PDFOCRError.rendering }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        // PDFKit drawing already applies the page's rotation/crop transform.
        // Applying page.transform here again clips and double-rotates scans.
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw PDFOCRError.rendering }
        return image
    }
}

import PDFKit

enum PDFPageOperation {
    case delete
    case duplicate
    /// Insertion boundary in the original document, in 0...pageCount.
    case move(to: Int)
    case insert(documents: [PDFDocument], at: Int)
}

struct PDFPageEditResult {
    let document: PDFDocument
    let selection: Set<Int>
}

struct PDFPageEditSnapshot {
    let data: Data
    let selection: Set<Int>
    let page: Int
    let viewRotation: Int
}

enum PDFPageTools {
    /// Edits a detached copy so failure never partially changes the live PDF.
    static func applying(_ operation: PDFPageOperation, to source: PDFDocument,
                         selection: Set<Int>, viewRotation: Int) -> PDFPageEditResult? {
        guard source.pageCount > 0, !source.isLocked,
              selection.allSatisfy({ (0..<source.pageCount).contains($0) }),
              let data = source.dataRepresentation(), let copy = PDFDocument(data: data) else { return nil }
        let selected = selection.sorted()
        switch operation {
        case .delete:
            guard !selected.isEmpty, selected.count < copy.pageCount else { return nil }
            for index in selected.reversed() { copy.removePage(at: index) }
            return PDFPageEditResult(document: copy, selection: [min(selected[0], copy.pageCount - 1)])
        case .duplicate:
            guard !selected.isEmpty else { return nil }
            var pages: [PDFPage] = []
            for index in selected {
                guard let page = copy.page(at: index)?.copy() as? PDFPage else { return nil }
                pages.append(page)
            }
            for (index, page) in zip(selected, pages).reversed() { copy.insert(page, at: index + 1) }
            let duplicates = Set(selected.enumerated().map { $0.element + $0.offset + 1 })
            return PDFPageEditResult(document: copy, selection: duplicates)
        case .move(let boundary):
            guard !selected.isEmpty, (0...copy.pageCount).contains(boundary) else { return nil }
            let pages = selected.compactMap { copy.page(at: $0) }
            guard pages.count == selected.count else { return nil }
            let destination = boundary - selected.filter { $0 < boundary }.count
            for index in selected.reversed() { copy.removePage(at: index) }
            for (offset, page) in pages.enumerated() { copy.insert(page, at: destination + offset) }
            return PDFPageEditResult(document: copy, selection: Set(destination..<(destination + pages.count)))
        case .insert(let documents, let boundary):
            guard (0...copy.pageCount).contains(boundary), !documents.isEmpty else { return nil }
            var pages: [PDFPage] = []
            for document in documents {
                guard !document.isLocked, document.pageCount > 0 else { return nil }
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index)?.copy() as? PDFPage else { return nil }
                    page.rotation = ((page.rotation + viewRotation) % 360 + 360) % 360
                    pages.append(page)
                }
            }
            for (offset, page) in pages.enumerated() { copy.insert(page, at: boundary + offset) }
            return PDFPageEditResult(document: copy, selection: Set(boundary..<(boundary + pages.count)))
        }
    }

    static func extract(from source: PDFDocument, selection: Set<Int>, viewRotation: Int) -> PDFDocument? {
        guard !selection.isEmpty, !source.isLocked,
              selection.allSatisfy({ (0..<source.pageCount).contains($0) }) else { return nil }
        let output = PDFDocument()
        for index in selection.sorted() {
            guard let page = source.page(at: index)?.copy() as? PDFPage else { return nil }
            page.rotation = ((page.rotation - viewRotation) % 360 + 360) % 360
            output.insert(page, at: output.pageCount)
        }
        output.documentAttributes = source.documentAttributes
        return output
    }
}

import Foundation

/// Fences may contain shorter or differently marked fences as literal code.
struct MarkdownCodeFence {
    let marker: Character
    let count: Int
    let language: String

    init?(opening line: String) {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let body = line.dropFirst(indent)
        guard let marker = body.first, marker == "`" || marker == "~" else { return nil }
        let count = body.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        let info = body.dropFirst(count).trimmingCharacters(in: .whitespaces)
        guard marker != "`" || !info.contains("`") else { return nil }
        self.marker = marker
        self.count = count
        // Render the first info-string token as plain text, never executable markup.
        self.language = String(info.split(whereSeparator: \.isWhitespace).first ?? "")
    }

    func closes(_ line: String) -> Bool {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return false }
        let body = line.dropFirst(indent)
        let length = body.prefix { $0 == marker }.count
        return length >= count && body.dropFirst(length).allSatisfy(\.isWhitespace)
    }
}

extension NSAttributedString.Key {
    static let fileViewerCodeContent = Self("FileViewerCodeContent")
}

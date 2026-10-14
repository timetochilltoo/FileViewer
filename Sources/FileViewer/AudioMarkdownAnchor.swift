import Foundation

/// Heading identity deliberately excludes mutable source offsets. Repeated
/// headings retain their ordinal only while the matching count is unchanged.
struct AudioMarkdownAnchor: Codable, Equatable, Hashable, Identifiable {
    let title: String
    let level: Int
    let occurrence: Int
    let duplicateCount: Int

    var id: Self { self }
    static let documentStart = Self(title: "", level: 0, occurrence: 0, duplicateCount: 0)
    var isDocumentStart: Bool { self == Self.documentStart }
    var isValid: Bool {
        isDocumentStart || ((1...6).contains(level) && !title.isEmpty && title.count <= 1024
            && (1...10000).contains(duplicateCount) && (0..<duplicateCount).contains(occurrence))
    }
    var label: String {
        isDocumentStart ? "Document Start" : title + (duplicateCount > 1 ? " (\(occurrence + 1)/\(duplicateCount))" : "")
    }

    static func options(for headings: [MarkdownHeading]) -> [Self] {
        let counts = Dictionary(grouping: headings, by: { "\($0.level):\($0.title)" }).mapValues(\.count)
        var seen: [String: Int] = [:]
        return headings.compactMap { heading in
            let key = "\(heading.level):\(heading.title)"
            let ordinal = seen[key, default: 0]
            seen[key] = ordinal + 1
            let anchor = Self(title: heading.title, level: heading.level, occurrence: ordinal, duplicateCount: counts[key] ?? 0)
            return anchor.isValid ? anchor : nil
        }
    }

    func resolve(in headings: [MarkdownHeading]) -> MarkdownHeading? {
        guard isValid, !isDocumentStart else { return nil }
        let matches = headings.filter { $0.title == title && $0.level == level }
        guard matches.count == duplicateCount, matches.indices.contains(occurrence) else { return nil }
        return matches[occurrence]
    }
}

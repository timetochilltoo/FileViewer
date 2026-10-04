import Foundation

struct MarkdownTable: Equatable {
    enum Alignment: Equatable { case left, center, right }
    let rows: [[String]]
    let alignments: [Alignment]

    static func parse(startingAt index: Int, in lines: [String]) -> (table: Self, nextIndex: Int)? {
        guard index >= 0, index + 1 < lines.count,
              let header = cells(lines[index]), let separators = cells(lines[index + 1]),
              !header.isEmpty, header.count == separators.count else { return nil }
        var alignments: [Alignment] = []
        for separator in separators {
            guard separator.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil else { return nil }
            alignments.append(separator.hasSuffix(":") ? (separator.hasPrefix(":") ? .center : .right) : .left)
        }
        var rows = [header]
        var next = index + 2
        while next < lines.count {
            let trimmed = lines[next].trimmingCharacters(in: .whitespaces)
            // New blocks terminate a table; outer pipes allow literal markers in cells.
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix(">"),
                  !["- ", "+ ", "* ", "!["].contains(where: trimmed.hasPrefix),
                  MarkdownCodeFence(opening: lines[next]) == nil,
                  let row = cells(lines[next]) else { break }
            rows.append(Array(row.prefix(header.count)) + Array(repeating: "", count: max(0, header.count - row.count)))
            next += 1
        }
        return (Self(rows: rows, alignments: alignments), next)
    }

    /// Strip only one outer pipe at each end, preserving empty cells and escaped pipes.
    static func cells(_ line: String) -> [String]? {
        let text = line.trimmingCharacters(in: .whitespaces)
        var result: [String] = []
        var cell = ""
        var index = text.startIndex
        var hasPipe = false
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\\", next < text.endIndex, text[next] == "|" || text[next] == "\\" {
                cell.append(text[next])
                index = text.index(after: next)
                continue
            }
            if character == "`" {
                let end = text[index...].prefix { $0 == "`" }.endIndex
                let marker = String(text[index..<end])
                if let close = text[end...].range(of: marker) {
                    // Matched inline code keeps its literal pipes in this renderer.
                    cell += String(text[index..<close.upperBound]).replacingOccurrences(of: #"\|"#, with: "|")
                    index = close.upperBound
                    continue
                }
            }
            if character == "|" {
                hasPipe = true
                result.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else { cell.append(character) }
            index = next
        }
        guard hasPipe else { return nil }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        if text.hasPrefix("|"), result.first == "" { result.removeFirst() }
        // An escaped trailing pipe belongs to a cell, not to the table boundary.
        if text.hasSuffix("|"), result.last == "" { result.removeLast() }
        return result
    }
}

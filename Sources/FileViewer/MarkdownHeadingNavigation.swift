import Foundation

extension NSAttributedString.Key {
    static let fileViewerHeadingLocation = Self("FileViewerHeadingLocation")
}

enum MarkdownHeadingNavigation {
    static func previewRange(for sourceLocation: Int, in text: NSAttributedString) -> NSRange? {
        var found: NSRange?
        text.enumerateAttribute(.fileViewerHeadingLocation, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            if let location = value as? Int, location == sourceLocation {
                found = NSRange(location: range.location, length: 1)
                stop.pointee = true
            }
        }
        return found
    }
}

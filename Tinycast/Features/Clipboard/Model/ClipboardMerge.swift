import Foundation

/// What a batch paste or copy writes: the selected entries as lines of one text.
enum ClipboardMerge {
    static let separator = "\n"

    /// Text as it is, a file as its path, an image as its blob's path; an entry with none is skipped.
    static func text(of items: [ClipboardItem]) -> String {
        items.compactMap { $0.kind == .image ? $0.imagePath : $0.text }
            .joined(separator: separator)
    }
}

import Foundation

extension Int64 {
    /// Decimal sizes ("1.2 MB" = 1,200,000 bytes), as Finder shows them.
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false  // "0 KB", not "Zero KB"
        return formatter.string(fromByteCount: self)
    }
}

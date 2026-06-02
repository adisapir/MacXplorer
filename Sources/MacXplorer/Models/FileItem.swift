import Foundation

struct FileItem: Identifiable, Hashable, Sendable {
    var id: URL { url }

    let url: URL
    let name: String
    let typeDescription: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let size: Int64?
    let modifiedAt: Date?
}

extension FileItem {
    var displayKind: String {
        if isPackage {
            return typeDescription.isEmpty ? "Package" : typeDescription
        }

        if isDirectory {
            return "Folder"
        }

        return typeDescription.isEmpty ? "File" : typeDescription
    }

    var displaySize: String {
        guard !isDirectory, let size else {
            return ""
        }

        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

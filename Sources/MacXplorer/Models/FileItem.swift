import Foundation

struct FileItem: Identifiable, Hashable, Sendable {
    var id: URL { url }

    let url: URL
    let name: String
    let typeDescription: String
    let isDirectory: Bool
    let isPackage: Bool
    let isAlias: Bool
    let aliasTargetURL: URL?
    let isAliasTargetDirectory: Bool
    let isAliasTargetPackage: Bool
    let isHidden: Bool
    let size: Int64?
    let modifiedAt: Date?
}

extension FileItem {
    var opensInApp: Bool {
        (isDirectory && !isPackage) || (isAlias && isAliasTargetDirectory && !isAliasTargetPackage && aliasTargetURL != nil)
    }

    var navigationURL: URL? {
        if isDirectory && !isPackage {
            return url
        }

        if isAlias && isAliasTargetDirectory && !isAliasTargetPackage {
            return aliasTargetURL
        }

        return nil
    }

    var displayKind: String {
        if isAlias && isAliasTargetDirectory && !isAliasTargetPackage {
            return "Folder Alias"
        }

        if isAlias {
            return typeDescription.isEmpty ? "Alias" : typeDescription
        }

        if isPackage {
            return typeDescription.isEmpty ? "Package" : typeDescription
        }

        if isDirectory {
            return "Folder"
        }

        return typeDescription.isEmpty ? "File" : typeDescription
    }

    var displaySize: String {
        guard !opensInApp, let size else {
            return ""
        }

        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

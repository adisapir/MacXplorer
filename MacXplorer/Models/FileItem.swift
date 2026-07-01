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
    let isNetworkLocation: Bool

    init(
        url: URL,
        name: String,
        typeDescription: String,
        isDirectory: Bool,
        isPackage: Bool,
        isAlias: Bool,
        aliasTargetURL: URL?,
        isAliasTargetDirectory: Bool,
        isAliasTargetPackage: Bool,
        isHidden: Bool,
        size: Int64?,
        modifiedAt: Date?,
        isNetworkLocation: Bool = false
    ) {
        self.url = url
        self.name = name
        self.typeDescription = typeDescription
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isAlias = isAlias
        self.aliasTargetURL = aliasTargetURL
        self.isAliasTargetDirectory = isAliasTargetDirectory
        self.isAliasTargetPackage = isAliasTargetPackage
        self.isHidden = isHidden
        self.size = size
        self.modifiedAt = modifiedAt
        self.isNetworkLocation = isNetworkLocation
    }
}

extension FileItem {
    var opensInApp: Bool {
        guard !isNetworkLocation else {
            return false
        }

        return (isDirectory && !isPackage) || (isAlias && isAliasTargetDirectory && !isAliasTargetPackage && aliasTargetURL != nil)
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
        if isNetworkLocation {
            return typeDescription.isEmpty ? "Network Location" : typeDescription
        }

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

    var sortSize: Int64 {
        guard !opensInApp, let size else {
            return -1
        }

        return size
    }

    var sortModifiedAt: Date {
        modifiedAt ?? .distantPast
    }
}

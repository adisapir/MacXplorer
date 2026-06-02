import Foundation

protocol FileSystemService: Sendable {
    func listDirectory(at url: URL, showHiddenFiles: Bool) async throws -> [FileItem]
    func createFolder(named name: String, in directory: URL) async throws -> URL
    func renameItem(at url: URL, to newName: String) async throws -> URL
    func moveItems(_ urls: [URL], to directory: URL) async throws -> [URL]
    func moveToTrash(_ url: URL) async throws
}

struct LocalFileSystemService: FileSystemService {
    private let keys: [URLResourceKey] = [
        .contentModificationDateKey,
        .fileSizeKey,
        .isAliasFileKey,
        .isDirectoryKey,
        .isHiddenKey,
        .isPackageKey,
        .localizedTypeDescriptionKey
    ]

    func listDirectory(at url: URL, showHiddenFiles: Bool) async throws -> [FileItem] {
        try await Task.detached(priority: .userInitiated) {
            let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
            let urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: options
            )

            let items = try urls.map { itemURL in
                let values = try itemURL.resourceValues(forKeys: Set(keys))
                let isDirectory = values.isDirectory ?? false
                let aliasTargetURL = values.isAliasFile == true ? Self.aliasTargetURL(for: itemURL) : nil
                let aliasTargetValues = aliasTargetURL.flatMap(Self.fileTypeValues)
                let isAliasTargetDirectory = aliasTargetValues?.isDirectory ?? false
                let isAliasTargetPackage = aliasTargetValues?.isPackage ?? false

                return FileItem(
                    url: itemURL,
                    name: itemURL.lastPathComponent,
                    typeDescription: values.localizedTypeDescription ?? "",
                    isDirectory: isDirectory,
                    isPackage: values.isPackage ?? false,
                    isAlias: values.isAliasFile ?? false,
                    aliasTargetURL: aliasTargetURL,
                    isAliasTargetDirectory: isAliasTargetDirectory,
                    isAliasTargetPackage: isAliasTargetPackage,
                    isHidden: values.isHidden ?? false,
                    size: values.fileSize.map(Int64.init),
                    modifiedAt: values.contentModificationDate
                )
            }

            return items.sorted { lhs, rhs in
                if lhs.opensInApp != rhs.opensInApp {
                    return lhs.opensInApp && !rhs.opensInApp
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }.value
    }

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let target = try uniqueURL(forFolderNamed: name, in: directory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            return target
        }.value
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw FileSystemError.invalidName
            }

            let destination = url.deletingLastPathComponent().appendingPathComponent(trimmedName)
            guard destination != url else {
                return url
            }

            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw FileSystemError.itemAlreadyExists(trimmedName)
            }

            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }.value
    }

    func moveItems(_ urls: [URL], to directory: URL) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            let destinationDirectory = directory.standardizedFileURL
            var moves: [(source: URL, destination: URL)] = []

            for url in urls {
                let source = url.standardizedFileURL
                let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)

                guard source.deletingLastPathComponent() != destinationDirectory else {
                    continue
                }

                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    throw FileSystemError.itemAlreadyExists(destination.lastPathComponent)
                }

                moves.append((source, destination))
            }

            for move in moves {
                try FileManager.default.moveItem(at: move.source, to: move.destination)
            }

            return moves.map(\.destination)
        }.value
    }

    func moveToTrash(_ url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }.value
    }

    private static func aliasTargetURL(for url: URL) -> URL? {
        try? URL(resolvingAliasFileAt: url, options: [.withoutUI]).standardizedFileURL
    }

    private static func fileTypeValues(for url: URL) -> URLResourceValues? {
        try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    }
}

enum FileSystemError: LocalizedError {
    case invalidName
    case itemAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a valid name."
        case .itemAlreadyExists(let name):
            return "An item named \"\(name)\" already exists."
        }
    }
}

private func uniqueURL(forFolderNamed name: String, in directory: URL) throws -> URL {
    var candidate = directory.appendingPathComponent(name)
    var suffix = 2

    while FileManager.default.fileExists(atPath: candidate.path) {
        candidate = directory.appendingPathComponent("\(name) \(suffix)")
        suffix += 1
    }

    return candidate
}

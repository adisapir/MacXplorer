import Foundation

protocol FileSystemService: Sendable {
    func listDirectory(at url: URL, showHiddenFiles: Bool) async throws -> [FileItem]
    func createFolder(named name: String, in directory: URL) async throws -> URL
    func renameItem(at url: URL, to newName: String) async throws -> URL
    func moveItems(_ urls: [URL], to directory: URL) async throws -> [URL]
    func moveToTrash(_ url: URL) async throws
    func quickViewContent(for url: URL, maximumBytes: Int) async throws -> QuickViewContent
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

    func quickViewContent(for url: URL, maximumBytes: Int) async throws -> QuickViewContent {
        try await Task.detached(priority: .userInitiated) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isPackageKey])
            let typeDescription = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription) ?? "File"
            guard values.isDirectory != true, values.isPackage != true else {
                throw FileSystemError.previewUnavailable("Quick View is available for files, not folders or packages.")
            }

            let fileSize = values.fileSize ?? 0
            guard fileSize <= maximumBytes else {
                let limit = ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file)
                let size = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                return QuickViewContent(
                    url: url,
                    title: url.lastPathComponent,
                    detail: "\(typeDescription) • \(size)",
                    text: "Preview skipped because this file is larger than \(limit)."
                )
            }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let text = Self.displayableText(from: data)
            return QuickViewContent(
                url: url,
                title: url.lastPathComponent,
                detail: "\(typeDescription) • \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))",
                text: text.isEmpty ? "No displayable characters found." : text
            )
        }.value
    }

    private static func aliasTargetURL(for url: URL) -> URL? {
        try? URL(resolvingAliasFileAt: url, options: [.withoutUI]).standardizedFileURL
    }

    private static func fileTypeValues(for url: URL) -> URLResourceValues? {
        try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    }

    private static func displayableText(from data: Data) -> String {
        if let text = String(data: data, encoding: .utf8), !containsControlCharacters(in: text) {
            return text
        }

        let scalars = data.compactMap { byte -> UnicodeScalar? in
            switch byte {
            case 9, 10, 13:
                return UnicodeScalar(byte)
            case 32...126:
                return UnicodeScalar(byte)
            default:
                return nil
            }
        }

        return String(String.UnicodeScalarView(scalars))
    }

    private static func containsControlCharacters(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value < 32 && scalar != "\n" && scalar != "\r" && scalar != "\t"
        }
    }
}

enum FileSystemError: LocalizedError {
    case invalidName
    case itemAlreadyExists(String)
    case previewUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a valid name."
        case .itemAlreadyExists(let name):
            return "An item named \"\(name)\" already exists."
        case .previewUnavailable(let message):
            return message
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

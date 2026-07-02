import Foundation
import Combine

enum CopyConflictResolution {
    case overwrite
    case skip
    case cancel
}

enum CopyQueueItemState: Equatable {
    case pending
    case running
    case completed
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .pending, .running:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }
}

struct CopyQueueItem: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL
    let name: String
    let shouldOverwrite: Bool
    var state: CopyQueueItemState
    var totalBytes: Int64
    var copiedBytes: Int64
    var bytesPerSecond: Double
    var startedAt: Date?

    var progress: Double {
        guard totalBytes > 0 else {
            return state == .completed ? 1 : 0
        }

        return min(1, Double(copiedBytes) / Double(totalBytes))
    }

    var estimatedSecondsRemaining: TimeInterval? {
        guard state == .running, bytesPerSecond > 0, totalBytes > copiedBytes else {
            return nil
        }

        return Double(totalBytes - copiedBytes) / bytesPerSecond
    }
}

@MainActor
final class CopyQueueViewModel: ObservableObject {
    @Published private(set) var items: [CopyQueueItem] = []

    var onItemCompleted: ((URL) -> Void)?

    var maximumConcurrentCopies = 3 {
        didSet {
            maximumConcurrentCopies = min(max(maximumConcurrentCopies, 1), 5)
            startAvailableCopies()
        }
    }

    private var tasks: [CopyQueueItem.ID: Task<Void, Never>] = [:]

    var hasItems: Bool {
        !items.isEmpty
    }

    var activeCopyCount: Int {
        items.filter { $0.state.isActive }.count
    }

    func enqueue(_ sources: [URL], to destinationDirectory: URL, conflictResolution: CopyConflictResolution) {
        guard conflictResolution != .cancel else {
            return
        }

        let destinationDirectory = destinationDirectory.standardizedFileURL
        let newItems = sources.compactMap { sourceURL -> CopyQueueItem? in
            let source = sourceURL.standardizedFileURL
            guard source.deletingLastPathComponent() != destinationDirectory else {
                return nil
            }

            let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            let destinationExists = FileManager.default.fileExists(atPath: destination.path)
            if destinationExists, conflictResolution == .skip {
                return nil
            }

            return CopyQueueItem(
                id: UUID(),
                sourceURL: source,
                destinationURL: destination,
                name: source.lastPathComponent,
                shouldOverwrite: destinationExists && conflictResolution == .overwrite,
                state: .pending,
                totalBytes: 0,
                copiedBytes: 0,
                bytesPerSecond: 0,
                startedAt: nil
            )
        }

        guard !newItems.isEmpty else {
            return
        }

        items.append(contentsOf: newItems)
        startAvailableCopies()
    }

    func cancel(_ itemID: CopyQueueItem.ID) {
        tasks[itemID]?.cancel()
        tasks[itemID] = nil

        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        items[index].state = .cancelled
        startAvailableCopies()
    }

    private func startAvailableCopies() {
        let runningCount = items.filter { $0.state == .running }.count
        let availableSlots = max(0, maximumConcurrentCopies - runningCount)
        guard availableSlots > 0 else {
            return
        }

        let pendingIDs = items
            .filter { $0.state == .pending }
            .prefix(availableSlots)
            .map(\.id)

        for itemID in pendingIDs {
            startCopy(itemID)
        }
    }

    private func startCopy(_ itemID: CopyQueueItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        items[index].state = .running
        items[index].startedAt = Date()
        let sourceURL = items[index].sourceURL
        let destinationURL = items[index].destinationURL
        let shouldOverwrite = items[index].shouldOverwrite

        tasks[itemID] = Task {
            do {
                let totalBytes = try await CopyWorker.totalByteCount(for: sourceURL)
                updateTotalBytes(totalBytes, for: itemID)

                try await CopyWorker.copy(
                    sourceURL,
                    to: destinationURL,
                    overwrite: shouldOverwrite
                ) { [weak self] copiedBytes in
                    Task { @MainActor [weak self] in
                        self?.updateCopiedBytes(copiedBytes, for: itemID)
                    }
                }

                complete(itemID)
            } catch is CancellationError {
                markCancelled(itemID)
            } catch {
                fail(itemID, message: error.localizedDescription)
            }
        }
    }

    private func updateTotalBytes(_ totalBytes: Int64, for itemID: CopyQueueItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        items[index].totalBytes = totalBytes
    }

    private func updateCopiedBytes(_ copiedBytes: Int64, for itemID: CopyQueueItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        items[index].copiedBytes = copiedBytes
        if let startedAt = items[index].startedAt {
            let elapsed = max(Date().timeIntervalSince(startedAt), 0.1)
            items[index].bytesPerSecond = Double(copiedBytes) / elapsed
        }
    }

    private func complete(_ itemID: CopyQueueItem.ID) {
        tasks[itemID] = nil
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            startAvailableCopies()
            return
        }

        let destinationURL = items[index].destinationURL
        items.remove(at: index)
        onItemCompleted?(destinationURL)
        startAvailableCopies()
    }

    private func markCancelled(_ itemID: CopyQueueItem.ID) {
        tasks[itemID] = nil
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            startAvailableCopies()
            return
        }

        items[index].state = .cancelled
        startAvailableCopies()
    }

    private func fail(_ itemID: CopyQueueItem.ID, message: String) {
        tasks[itemID] = nil
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            startAvailableCopies()
            return
        }

        items[index].state = .failed(message)
        startAvailableCopies()
    }
}

private enum CopyWorker {
    static func totalByteCount(for url: URL) async throws -> Int64 {
        try await Task.detached(priority: .utility) {
            try byteCount(for: url)
        }.value
    }

    static func copy(
        _ sourceURL: URL,
        to destinationURL: URL,
        overwrite: Bool,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await Task.detached(priority: .utility) {
            var copiedBytes: Int64 = 0
            try copyItem(
                sourceURL,
                to: destinationURL,
                overwrite: overwrite,
                copiedBytes: &copiedBytes,
                progress: progress
            )
        }.value
    }

    nonisolated private static func byteCount(for url: URL) throws -> Int64 {
        try Task.checkCancellation()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if isDirectory.boolValue {
            let urls = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )?.compactMap { $0 as? URL } ?? []

            return try urls.reduce(Int64(0)) { partialResult, childURL in
                try Task.checkCancellation()
                let values = try childURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                guard values.isDirectory != true else {
                    return partialResult
                }

                return partialResult + Int64(values.fileSize ?? 0)
            }
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    nonisolated private static func copyItem(
        _ sourceURL: URL,
        to destinationURL: URL,
        overwrite: Bool,
        copiedBytes: inout Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws {
        try Task.checkCancellation()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if isDirectory.boolValue {
            if FileManager.default.fileExists(atPath: destinationURL.path), overwrite {
                try FileManager.default.removeItem(at: destinationURL)
            }

            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            }

            let children = try FileManager.default.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: []
            )

            for child in children {
                try copyItem(
                    child,
                    to: destinationURL.appendingPathComponent(child.lastPathComponent),
                    overwrite: overwrite,
                    copiedBytes: &copiedBytes,
                    progress: progress
                )
            }
            return
        }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if overwrite {
                try FileManager.default.removeItem(at: destinationURL)
            } else {
                throw CocoaError(.fileWriteFileExists)
            }
        }

        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? sourceHandle.close()
        }

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let destinationHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? destinationHandle.close()
        }

        while true {
            try Task.checkCancellation()
            let data = try sourceHandle.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else {
                break
            }

            try destinationHandle.write(contentsOf: data)
            copiedBytes += Int64(data.count)
            progress(copiedBytes)
        }
    }
}

import Combine
import Foundation

@MainActor
final class SpaceAnalyzerViewModel: ObservableObject {
    enum ScanState {
        case idle
        case scanning(scannedCount: Int)
        case ready(root: SpaceNode)
        case failed(String)
    }

    @Published private(set) var scanState: ScanState = .idle
    @Published var rootPath: String
    let categories = FileCategoryService()
    private var scanTask: Task<Void, Never>?

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        rootPath = rootURL.path(percentEncoded: false)
    }

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    func startScan(url: URL) {
        rootPath = url.path(percentEncoded: false)
        beginScan()
    }

    func refresh() {
        beginScan()
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanState = .idle
    }

    var volumeStats: (total: UInt64, free: UInt64)? {
        let url = URL(fileURLWithPath: rootPath)
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let total = values?.volumeTotalCapacity,
              let free = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return (UInt64(max(0, total)), UInt64(max(0, free)))
    }

    private func beginScan() {
        scanTask?.cancel()
        let url = URL(fileURLWithPath: rootPath)
        scanState = .scanning(scannedCount: 0)
        scanTask = Task {
            do {
                let root = try await SpaceScanner.scan(url: url) { [weak self] count in
                    await MainActor.run {
                        if case .scanning = self?.scanState {
                            self?.scanState = .scanning(scannedCount: count)
                        }
                    }
                }
                if !Task.isCancelled {
                    scanState = .ready(root: root)
                }
            } catch is CancellationError {
                scanState = .idle
            } catch {
                scanState = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: – Background scanner

// `nonisolated` is essential: this project uses MainActor-default isolation, so
// without it these methods would be @MainActor and run on the main thread even
// inside Task.detached — freezing the UI during a scan.
nonisolated enum SpaceScanner {
    static func scan(url: URL, progressHandler: @escaping @Sendable (Int) async -> Void) async throws -> SpaceNode {
        // Task.detached is unstructured, so cancellation of the caller does not
        // automatically propagate. withTaskCancellationHandler bridges the gap.
        let detached = Task.detached(priority: .utility) {
            var count = 0
            return try scanSync(url: url, count: &count, progressHandler: progressHandler)
        }
        return try await withTaskCancellationHandler {
            try await detached.value
        } onCancel: {
            detached.cancel()
        }
    }

    private static func scanSync(
        url: URL,
        count: inout Int,
        progressHandler: @escaping @Sendable (Int) async -> Void
    ) throws -> SpaceNode {
        try Task.checkCancellation()
        let fm = FileManager.default
        let resKeys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .isPackageKey]
        var children: [SpaceNode] = []
        var total: UInt64 = 0

        let contents = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resKeys),
            options: [.skipsHiddenFiles]
        )) ?? []

        for childURL in contents {
            try Task.checkCancellation()
            let res = try? childURL.resourceValues(forKeys: resKeys)
            let isDir = res?.isDirectory ?? false
            let isPkg = res?.isPackage ?? false

            if isDir && !isPkg {
                let child = try scanSync(url: childURL, count: &count, progressHandler: progressHandler)
                children.append(child)
                total += child.size
            } else {
                let size = UInt64(max(0, res?.fileSize ?? 0))
                children.append(SpaceNode(url: childURL, name: childURL.lastPathComponent, size: size, isDirectory: false))
                total += size
            }

            count += 1
            if count % 300 == 0 {
                let c = count
                Task { await progressHandler(c) }
            }
        }

        children.sort { $0.size > $1.size }
        return SpaceNode(url: url, name: url.lastPathComponent, size: total, isDirectory: true, children: children)
    }
}

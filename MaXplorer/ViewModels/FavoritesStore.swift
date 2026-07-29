import Combine
import Darwin
import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    private struct State: Codable, Equatable {
        var pinnedPaths: [String] = []
        var removedBuiltInPaths: [String] = []
    }

    private static let pinnedFavoritesKey = "PinnedFavoritePaths"
    private static let removedBuiltInFavoritesKey = "RemovedBuiltInFavoritePaths"
    private static let changeNotification = Notification.Name("doccolabs.MaXplorer.favoritesChanged")

    @Published private(set) var pinnedURLs: [URL] = []
    @Published private(set) var removedBuiltInURLs: [URL] = []

    private let fileURL: URL
    private let lockURL: URL
    private var notificationObserver: NSObjectProtocol?

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directoryURL = directoryURL
            ?? applicationSupportURL.appendingPathComponent("MaXplorer", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("favorites.json")
        self.lockURL = directoryURL.appendingPathComponent("favorites.lock")

        let initialState = Self.withLockedState(
            fileURL: fileURL,
            lockURL: lockURL,
            fileManager: fileManager,
            defaults: defaults
        ) { _ in }
        apply(initialState)

        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.changeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
    }

    deinit {
        if let notificationObserver {
            DistributedNotificationCenter.default().removeObserver(notificationObserver)
        }
    }

    func addPinned(_ url: URL) {
        update { state in
            Self.appendUnique(url.standardizedFileURL.path, to: &state.pinnedPaths)
        }
    }

    func removePinned(_ url: URL) {
        update { state in
            let path = url.standardizedFileURL.path
            state.pinnedPaths.removeAll { $0 == path }
        }
    }

    func addRemovedBuiltIn(_ url: URL) {
        update { state in
            Self.appendUnique(url.standardizedFileURL.path, to: &state.removedBuiltInPaths)
        }
    }

    func removeRemovedBuiltIn(_ url: URL) {
        update { state in
            let path = url.standardizedFileURL.path
            state.removedBuiltInPaths.removeAll { $0 == path }
        }
    }

    func movePinned(_ url: URL, before targetURL: URL) {
        update { state in
            let sourcePath = url.standardizedFileURL.path
            let targetPath = targetURL.standardizedFileURL.path
            guard sourcePath != targetPath,
                  let sourceIndex = state.pinnedPaths.firstIndex(of: sourcePath),
                  let targetIndex = state.pinnedPaths.firstIndex(of: targetPath) else {
                return
            }

            let movedPath = state.pinnedPaths.remove(at: sourceIndex)
            let insertionIndex = state.pinnedPaths.firstIndex(of: targetPath) ?? targetIndex
            state.pinnedPaths.insert(movedPath, at: insertionIndex)
        }
    }

    private func reload() {
        apply(Self.loadState(from: fileURL) ?? State())
    }

    private func update(_ mutation: (inout State) -> Void) {
        let state = Self.withLockedState(
            fileURL: fileURL,
            lockURL: lockURL,
            fileManager: .default,
            defaults: .standard,
            mutation: mutation
        )
        apply(state)
        DistributedNotificationCenter.default().postNotificationName(
            Self.changeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func apply(_ state: State) {
        pinnedURLs = Self.uniqueURLs(from: state.pinnedPaths)
        removedBuiltInURLs = Self.uniqueURLs(from: state.removedBuiltInPaths)
    }

    private static func withLockedState(
        fileURL: URL,
        lockURL: URL,
        fileManager: FileManager,
        defaults: UserDefaults,
        mutation: (inout State) -> Void
    ) -> State {
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            var state = loadState(from: fileURL) ?? legacyState(from: defaults)
            mutation(&state)
            return state
        }

        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        flock(descriptor, LOCK_EX)
        let fileExists = fileManager.fileExists(atPath: fileURL.path)
        let persistedState = loadState(from: fileURL)
        var state = persistedState ?? legacyState(from: defaults)
        mutation(&state)

        if !fileExists || persistedState != state {
            save(state, to: fileURL)
        }
        return state
    }

    private static func loadState(from fileURL: URL) -> State? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private static func save(_ state: State, to fileURL: URL) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func legacyState(from defaults: UserDefaults) -> State {
        State(
            pinnedPaths: defaults.stringArray(forKey: pinnedFavoritesKey) ?? [],
            removedBuiltInPaths: defaults.stringArray(forKey: removedBuiltInFavoritesKey) ?? []
        )
    }

    private static func uniqueURLs(from paths: [String]) -> [URL] {
        var seen = Set<String>()
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return seen.insert(url.path).inserted ? url : nil
        }
    }

    private static func appendUnique(_ path: String, to paths: inout [String]) {
        guard !paths.contains(path) else {
            return
        }
        paths.append(path)
    }
}

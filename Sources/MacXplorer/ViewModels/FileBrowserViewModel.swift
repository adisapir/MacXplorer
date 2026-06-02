import Foundation

@MainActor
final class FileBrowserViewModel: ObservableObject {
    private static let pinnedFavoritesKey = "PinnedFavoritePaths"
    private static let removedBuiltInFavoritesKey = "RemovedBuiltInFavoritePaths"

    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pinnedFavoriteURLs: [URL] = []
    @Published private(set) var removedBuiltInFavoriteURLs: [URL] = []
    @Published var pathText: String
    @Published var filterText = ""
    @Published var selectedItemID: FileItem.ID?
    @Published var renameRequest: FileItem?
    @Published var trashRequest: FileItem?
    @Published var showHiddenFiles = false {
        didSet {
            reload()
        }
    }

    let fileSystem: any FileSystemService
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var loadGeneration = 0

    init(fileSystem: FileSystemService) {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        self.fileSystem = fileSystem
        self.currentURL = homeURL
        self.pathText = homeURL.path
        self.pinnedFavoriteURLs = Self.loadPinnedFavorites()
        self.removedBuiltInFavoriteURLs = Self.loadRemovedBuiltInFavorites()
        reload()
    }

    var filteredItems: [FileItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedItem: FileItem? {
        guard let selectedItemID else {
            return nil
        }

        return items.first { $0.id == selectedItemID }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentURL.path != "/" }

    var sidebarLocations: [SidebarLocation] {
        let builtInFavorites = builtInFavoriteLocations()
        let removedBuiltInURLs = Set(removedBuiltInFavoriteURLs.map(\.standardizedFileURL))
        var locations = builtInFavorites.filter { !removedBuiltInURLs.contains($0.url.standardizedFileURL) }
        let builtInFavoriteURLs = Set(builtInFavorites.map { $0.url.standardizedFileURL })

        for url in pinnedFavoriteURLs where !builtInFavoriteURLs.contains(url.standardizedFileURL) {
            locations.append(
                SidebarLocation(
                    name: sidebarName(for: url),
                    url: url,
                    group: .favorites,
                    systemImage: "folder.fill",
                    canRemoveFromFavorites: true
                )
            )
        }

        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []

        for volume in volumes where volume.path != "/" {
            let values = try? volume.resourceValues(forKeys: [.volumeNameKey])
            locations.append(
                SidebarLocation(
                    name: values?.volumeName ?? volume.lastPathComponent,
                    url: volume,
                    group: .devices,
                    systemImage: "externaldrive.fill"
                )
            )
        }

        return locations
    }

    private func builtInFavoriteLocations() -> [SidebarLocation] {
        [
            SidebarLocation(name: "Home", url: FileManager.default.homeDirectoryForCurrentUser, group: .favorites, systemImage: "house.fill", canRemoveFromFavorites: true),
            SidebarLocation(name: "Desktop", url: homeSubfolder("Desktop"), group: .favorites, systemImage: "desktopcomputer", canRemoveFromFavorites: true),
            SidebarLocation(name: "Documents", url: homeSubfolder("Documents"), group: .favorites, systemImage: "folder.fill", canRemoveFromFavorites: true),
            SidebarLocation(name: "Downloads", url: homeSubfolder("Downloads"), group: .favorites, systemImage: "arrow.down.circle.fill", canRemoveFromFavorites: true)
        ]
    }

    func reload() {
        reload(selecting: nil)
    }

    private func reload(selecting itemID: FileItem.ID?) {
        let target = currentURL
        let showHiddenFiles = showHiddenFiles
        let fileSystem = fileSystem
        loadGeneration += 1
        let generation = loadGeneration

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let loadedItems = try await fileSystem.listDirectory(at: target, showHiddenFiles: showHiddenFiles)
                guard generation == loadGeneration else {
                    return
                }

                items = loadedItems
                if let itemID, loadedItems.contains(where: { $0.id == itemID }) {
                    selectedItemID = itemID
                } else {
                    selectedItemID = nil
                }
                isLoading = false
            } catch {
                guard generation == loadGeneration else {
                    return
                }

                items = []
                selectedItemID = nil
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func navigate(to url: URL, recordHistory: Bool = true) {
        guard url != currentURL else {
            reload()
            return
        }

        if recordHistory {
            backStack.append(currentURL)
            forwardStack.removeAll()
        }

        currentURL = url
        pathText = url.path
        filterText = ""
        reload()
    }

    func goBack() {
        guard let previous = backStack.popLast() else {
            return
        }

        forwardStack.append(currentURL)
        navigate(to: previous, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else {
            return
        }

        backStack.append(currentURL)
        navigate(to: next, recordHistory: false)
    }

    func goUp() {
        guard canGoUp else {
            return
        }

        navigate(to: currentURL.deletingLastPathComponent())
    }

    func submitPath() {
        let expandedPath = NSString(string: pathText).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            errorMessage = "The path does not exist or is not a folder."
            pathText = currentURL.path
            return
        }

        navigate(to: url)
    }

    func openSelected() {
        guard let selectedItem else {
            return
        }

        if let navigationURL = selectedItem.navigationURL {
            navigate(to: navigationURL)
        } else {
            SystemActions.open(selectedItem.url)
        }
    }

    func requestRenameSelected() {
        guard let selectedItem else {
            return
        }

        renameRequest = selectedItem
    }

    func requestTrashSelected() {
        guard let selectedItem else {
            return
        }

        trashRequest = selectedItem
    }

    func pinSelectedFolderToFavorites() {
        guard let selectedItem, selectedItem.opensInApp else {
            return
        }

        pinFavorite(selectedItem.navigationURL ?? selectedItem.url)
    }

    func pinDroppedFavorites(_ urls: [URL]) -> Bool {
        var didPin = false

        for url in urls where isDirectory(url) {
            let beforeCount = pinnedFavoriteURLs.count
            pinFavorite(url)
            didPin = didPin || pinnedFavoriteURLs.count > beforeCount
        }

        return didPin
    }

    func pinFavorite(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard isDirectory(standardizedURL) else {
            errorMessage = "Only folders can be added to Favorites."
            return
        }

        if isBuiltInFavorite(standardizedURL) {
            removedBuiltInFavoriteURLs.removeAll { $0.standardizedFileURL == standardizedURL }
            saveRemovedBuiltInFavorites()
            return
        }

        guard !pinnedFavoriteURLs.contains(standardizedURL) else {
            return
        }

        pinnedFavoriteURLs.append(standardizedURL)
        savePinnedFavorites()
    }

    func removeFavorite(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        if isBuiltInFavorite(standardizedURL) {
            guard !removedBuiltInFavoriteURLs.contains(standardizedURL) else {
                return
            }

            removedBuiltInFavoriteURLs.append(standardizedURL)
            saveRemovedBuiltInFavorites()
        } else {
            pinnedFavoriteURLs.removeAll { $0.standardizedFileURL == standardizedURL }
            savePinnedFavorites()
        }
    }

    func unpinFavorite(_ url: URL) {
        removeFavorite(url)
    }

    func canPinFolder(_ item: FileItem) -> Bool {
        guard item.opensInApp, let navigationURL = item.navigationURL else {
            return false
        }

        let url = navigationURL.standardizedFileURL
        if isBuiltInFavorite(url) {
            return removedBuiltInFavoriteURLs.contains(url)
        }

        return !pinnedFavoriteURLs.contains(url)
    }

    func createFolder() async {
        do {
            let createdURL = try await fileSystem.createFolder(named: "New Folder", in: currentURL)
            reload(selecting: createdURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameSelected(to newName: String) async {
        guard let selectedItem else {
            return
        }

        do {
            let renamedURL = try await fileSystem.renameItem(at: selectedItem.url, to: newName)
            reload(selecting: renamedURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveSelectedToTrash() async {
        guard let selectedItem else {
            return
        }

        await moveItemToTrash(selectedItem)
    }

    func moveItemToTrash(_ item: FileItem) async {
        do {
            try await fileSystem.moveToTrash(item.url)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealSelectedInFinder() {
        SystemActions.revealInFinder(selectedItem?.url ?? currentURL)
    }

    func openCurrentFolderInTerminal() {
        SystemActions.openInTerminal(currentURL)
    }

    func openSelectedInTerminal() {
        SystemActions.openInTerminal(selectedItem?.url ?? currentURL)
    }

    func copySelectedPath() {
        SystemActions.copyPath(selectedItem?.url ?? currentURL)
    }

    func clearError() {
        errorMessage = nil
    }

    func clearRenameRequest() {
        renameRequest = nil
    }

    func clearTrashRequest() {
        trashRequest = nil
    }

    private func homeSubfolder(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
    }

    private func sidebarName(for url: URL) -> String {
        if url.lastPathComponent.isEmpty {
            return url.path
        }

        return url.lastPathComponent
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isBuiltInFavorite(_ url: URL) -> Bool {
        let builtInURLs = builtInFavoriteLocations().map { $0.url.standardizedFileURL }

        return builtInURLs.contains(url.standardizedFileURL)
    }

    private func savePinnedFavorites() {
        UserDefaults.standard.set(pinnedFavoriteURLs.map(\.path), forKey: Self.pinnedFavoritesKey)
    }

    private func saveRemovedBuiltInFavorites() {
        UserDefaults.standard.set(removedBuiltInFavoriteURLs.map(\.path), forKey: Self.removedBuiltInFavoritesKey)
    }

    private static func loadPinnedFavorites() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: pinnedFavoritesKey) ?? []
        var seen = Set<String>()

        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard !seen.contains(url.path) else {
                return nil
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }

            seen.insert(url.path)
            return url
        }
    }

    private static func loadRemovedBuiltInFavorites() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: removedBuiltInFavoritesKey) ?? []
        var seen = Set<String>()

        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard !seen.contains(url.path) else {
                return nil
            }

            seen.insert(url.path)
            return url
        }
    }
}

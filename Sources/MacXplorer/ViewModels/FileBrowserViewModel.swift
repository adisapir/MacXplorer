import Foundation

enum SelectionMode {
    case single
    case toggle
    case range
}

struct CopyConflictRequest: Identifiable, Equatable {
    let id = UUID()
    let sources: [URL]
    let destinationDirectory: URL
    let conflictingNames: [String]
}

@MainActor
final class FileBrowserViewModel: ObservableObject {
    private static let pinnedFavoritesKey = "PinnedFavoritePaths"
    private static let removedBuiltInFavoritesKey = "RemovedBuiltInFavoritePaths"
    private static let networkRootURL = URL(string: "macxplorer://network")!

    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pinnedFavoriteURLs: [URL] = []
    @Published private(set) var removedBuiltInFavoriteURLs: [URL] = []
    @Published private(set) var cutItemURLs: [URL] = []
    @Published private(set) var copiedItemURLs: [URL] = []
    @Published var isConnectToServerPresented = false
    @Published var isGoToFolderPresented = false
    @Published var isCopyQueueVisible = false
    @Published var copyConflictRequest: CopyConflictRequest?
    @Published var pathText: String
    @Published var filterText = ""
    @Published var selectedItemIDs: Set<FileItem.ID> = []
    @Published var sortOrder = [KeyPathComparator(\FileItem.name)]
    @Published var renameRequest: FileItem?
    @Published var trashRequest: FileItem?
    @Published var showHiddenFiles = false {
        didSet {
            reload()
        }
    }

    let fileSystem: any FileSystemService
    let copyQueue = CopyQueueViewModel()
    private let networkBrowser = NetworkBrowserService()
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var loadGeneration = 0
    private var selectionAnchorID: FileItem.ID?

    init(fileSystem: FileSystemService) {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        self.fileSystem = fileSystem
        self.currentURL = homeURL
        self.pathText = homeURL.path
        self.pinnedFavoriteURLs = Self.loadPinnedFavorites()
        self.removedBuiltInFavoriteURLs = Self.loadRemovedBuiltInFavorites()
        self.copyQueue.onItemCompleted = { [weak self] destinationURL in
            guard let self, destinationURL.deletingLastPathComponent().standardizedFileURL == self.currentURL.standardizedFileURL else {
                return
            }

            self.reload(selecting: destinationURL)
        }
        reload()
    }

    var displayedItems: [FileItem] {
        filteredItems.sorted(using: sortOrder)
    }

    private var filteredItems: [FileItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedItem: FileItem? {
        items.first { selectedItemIDs.contains($0.id) }
    }

    var selectedItems: [FileItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentURL.isFileURL && currentURL.path != "/" }
    var canCreateFolder: Bool { currentURL.isFileURL }
    var canCutSelectedItem: Bool { selectedItems.contains { !$0.isNetworkLocation } }
    var canCopySelectedItem: Bool { selectedItems.contains { !$0.isNetworkLocation } }
    var canPasteItems: Bool { currentURL.isFileURL && (!cutItemURLs.isEmpty || !copiedItemURLs.isEmpty || !SystemActions.fileURLsFromPasteboard().isEmpty) }
    var canPasteCutItems: Bool { currentURL.isFileURL && !cutItemURLs.isEmpty }
    var isBrowsingNetwork: Bool { currentURL == Self.networkRootURL }
    var currentLocationText: String {
        if currentURL == Self.networkRootURL {
            return "Network"
        }

        return currentURL.isFileURL ? currentURL.path : currentURL.absoluteString
    }
    var tabTitle: String {
        if currentURL == Self.networkRootURL {
            return "Network"
        }

        if currentURL.isFileURL {
            if currentURL.path == "/" {
                return "/"
            }

            return currentURL.lastPathComponent.isEmpty ? currentURL.path : currentURL.lastPathComponent
        }

        return currentURL.host() ?? currentURL.absoluteString
    }

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

        locations.append(
            SidebarLocation(
                name: "Browse Network",
                url: Self.networkRootURL,
                group: .network,
                systemImage: "network"
            )
        )

        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsLocalKey, .volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []

        for volume in volumes where volume.path != "/" {
            let values = try? volume.resourceValues(forKeys: [.volumeIsLocalKey, .volumeNameKey])
            let isLocal = values?.volumeIsLocal ?? true
            locations.append(
                SidebarLocation(
                    name: values?.volumeName ?? volume.lastPathComponent,
                    url: volume,
                    group: isLocal ? .devices : .network,
                    systemImage: isLocal ? "externaldrive.fill" : "server.rack"
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
                let loadedItems: [FileItem]
                if target == Self.networkRootURL {
                    loadedItems = await networkItems()
                } else {
                    loadedItems = try await fileSystem.listDirectory(at: target, showHiddenFiles: showHiddenFiles)
                }

                guard generation == loadGeneration else {
                    return
                }

                applyLoadedItems(loadedItems, selecting: itemID)
                isLoading = false
            } catch {
                guard generation == loadGeneration else {
                    return
                }

                items = []
                selectedItemIDs = []
                selectionAnchorID = nil
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func navigate(to url: URL, recordHistory: Bool = true) {
        isCopyQueueVisible = false
        guard url != currentURL else {
            reload()
            return
        }

        if recordHistory {
            backStack.append(currentURL)
            forwardStack.removeAll()
        }

        currentURL = url
        pathText = url == Self.networkRootURL ? "Network" : url.path
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
        if expandedPath.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Network") == .orderedSame {
            navigate(to: Self.networkRootURL)
            return
        }

        if let networkURL = Self.serverURL(from: expandedPath) {
            connectToServer(networkURL)
            return
        }

        let url = URL(fileURLWithPath: expandedPath)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            errorMessage = "The path does not exist or is not a folder."
            pathText = currentURL.path
            return
        }

        navigate(to: url)
    }

    func showGoToFolder() {
        isGoToFolderPresented = true
    }

    func navigateToManualFolder(_ input: String) -> URL? {
        guard let url = manualFolderURL(from: input), isDirectory(url) else {
            errorMessage = "Path not found"
            return nil
        }

        navigate(to: url.standardizedFileURL)
        return url.standardizedFileURL
    }

    func showConnectToServer() {
        isConnectToServerPresented = true
    }

    func connectToServer(_ address: String) {
        guard let serverURL = Self.serverURL(from: address) else {
            errorMessage = "Enter a valid server address, such as smb://server/share."
            return
        }

        connectToServer(serverURL)
    }

    func openSelected() {
        guard let selectedItem else {
            return
        }

        if selectedItem.isNetworkLocation {
            SystemActions.connectToServer(selectedItem.url)
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
            clearCutItems(containing: [item.url])
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cutSelectedItem() {
        cutSelectedItems()
    }

    func cutSelectedItems() {
        cutItemURLs = selectedItems
            .filter { !$0.isNetworkLocation }
            .map { $0.url.standardizedFileURL }
        copiedItemURLs = []
    }

    func copySelectedItem() {
        copySelectedItems()
    }

    func copySelectedItems() {
        let copiedURLs = selectedItems
            .filter { !$0.isNetworkLocation }
            .map { $0.url.standardizedFileURL }

        guard !copiedURLs.isEmpty else {
            return
        }

        copiedItemURLs = copiedURLs
        cutItemURLs = []
        SystemActions.copyFileURLs(copiedURLs)
    }

    func pasteItems(maximumConcurrentCopies: Int) async {
        if !cutItemURLs.isEmpty {
            await pasteCutItems()
            return
        }

        pasteCopiedItems(maximumConcurrentCopies: maximumConcurrentCopies, conflictResolution: .cancel)
    }

    func pasteCutItems() async {
        guard !cutItemURLs.isEmpty else {
            return
        }

        do {
            let movedURLs = try await fileSystem.moveItems(cutItemURLs, to: currentURL)
            clearCutItems(containing: cutItemURLs)
            reload(selecting: movedURLs.first)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pasteCopiedItems(maximumConcurrentCopies: Int, conflictResolution: CopyConflictResolution) {
        guard currentURL.isFileURL else {
            return
        }

        let copiedSources = copiedItemURLs.isEmpty ? SystemActions.fileURLsFromPasteboard() : copiedItemURLs
        guard !copiedSources.isEmpty else {
            return
        }

        let destinationDirectory = currentURL.standardizedFileURL
        let sources = copiedSources.filter { source in
            source.standardizedFileURL.deletingLastPathComponent() != destinationDirectory
        }

        guard !sources.isEmpty else {
            return
        }

        let conflicts = sources.compactMap { source -> String? in
            let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            return FileManager.default.fileExists(atPath: destination.path) ? destination.lastPathComponent : nil
        }

        if !conflicts.isEmpty, conflictResolution == .cancel {
            copyConflictRequest = CopyConflictRequest(
                sources: sources,
                destinationDirectory: destinationDirectory,
                conflictingNames: conflicts
            )
            return
        }

        copyConflictRequest = nil
        let enqueueResolution: CopyConflictResolution = conflictResolution == .cancel ? .skip : conflictResolution
        copyQueue.maximumConcurrentCopies = maximumConcurrentCopies
        copyQueue.enqueue(sources, to: destinationDirectory, conflictResolution: enqueueResolution)
        if copyQueue.hasItems {
            isCopyQueueVisible = true
        }
    }

    func resolveCopyConflict(_ resolution: CopyConflictResolution, maximumConcurrentCopies: Int) {
        guard let request = copyConflictRequest else {
            return
        }

        copyConflictRequest = nil
        guard resolution != .cancel else {
            return
        }

        copyQueue.maximumConcurrentCopies = maximumConcurrentCopies
        copyQueue.enqueue(request.sources, to: request.destinationDirectory, conflictResolution: resolution)
        if copyQueue.hasItems {
            isCopyQueueVisible = true
        }
    }

    func showCopyQueue() {
        isCopyQueueVisible = true
    }

    func isCut(_ item: FileItem) -> Bool {
        cutItemURLs.contains(item.url.standardizedFileURL)
    }

    func select(_ item: FileItem, mode: SelectionMode) {
        switch mode {
        case .single:
            selectedItemIDs = [item.id]
            selectionAnchorID = item.id
        case .toggle:
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
            selectionAnchorID = item.id
        case .range:
            selectRange(through: item)
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

    private func connectToServer(_ url: URL) {
        isConnectToServerPresented = false

        if url.isFileURL {
            navigate(to: url)
        } else {
            SystemActions.connectToServer(url)
        }
    }

    private func networkItems() async -> [FileItem] {
        let mountedRemoteVolumes = mountedRemoteVolumeItems()
        let discoveredLocations = await networkBrowser.browse()
        let mountedURLs = Set(mountedRemoteVolumes.map(\.url))
        let discoveredItems = discoveredLocations
            .filter { !mountedURLs.contains($0.url) }
            .map { location in
                FileItem(
                    url: location.url,
                    name: location.name,
                    typeDescription: location.kind,
                    isDirectory: false,
                    isPackage: false,
                    isAlias: false,
                    aliasTargetURL: nil,
                    isAliasTargetDirectory: false,
                    isAliasTargetPackage: false,
                    isHidden: false,
                    size: nil,
                    modifiedAt: nil,
                    isNetworkLocation: true
                )
            }

        return (mountedRemoteVolumes + discoveredItems).sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func mountedRemoteVolumeItems() -> [FileItem] {
        remoteMountedVolumes().map { volume in
            let values = try? volume.resourceValues(forKeys: [.contentModificationDateKey, .volumeNameKey])
            return FileItem(
                url: volume,
                name: values?.volumeName ?? volume.lastPathComponent,
                typeDescription: "Mounted Network Volume",
                isDirectory: true,
                isPackage: false,
                isAlias: false,
                aliasTargetURL: nil,
                isAliasTargetDirectory: false,
                isAliasTargetPackage: false,
                isHidden: false,
                size: nil,
                modifiedAt: values?.contentModificationDate
            )
        }
    }

    private func remoteMountedVolumes() -> [URL] {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsLocalKey, .volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumes.filter { volume in
            guard volume.path != "/" else {
                return false
            }

            let values = try? volume.resourceValues(forKeys: [.volumeIsLocalKey])
            return values?.volumeIsLocal == false
        }
    }

    private func applyLoadedItems(_ loadedItems: [FileItem], selecting itemID: FileItem.ID?) {
        items = loadedItems
        if let itemID, loadedItems.contains(where: { $0.id == itemID }) {
            selectedItemIDs = [itemID]
            selectionAnchorID = itemID
        } else {
            selectedItemIDs = selectedItemIDs.filter { selectedID in
                loadedItems.contains { $0.id == selectedID }
            }
            if let selectionAnchorID, !selectedItemIDs.contains(selectionAnchorID) {
                self.selectionAnchorID = selectedItemIDs.first
            }
        }
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

    private func manualFolderURL(from input: String) -> URL? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        let expandedPath = NSString(string: trimmedInput).expandingTildeInPath
        if NSString(string: expandedPath).isAbsolutePath {
            return URL(fileURLWithPath: expandedPath)
        }

        let baseURL = currentURL.isFileURL ? currentURL : FileManager.default.homeDirectoryForCurrentUser
        return baseURL.appendingPathComponent(expandedPath)
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

    private func clearCutItems(containing urls: [URL]) {
        let standardizedURLs = Set(urls.map(\.standardizedFileURL))
        cutItemURLs.removeAll { standardizedURLs.contains($0.standardizedFileURL) }
    }

    private func selectRange(through item: FileItem) {
        guard
            let anchorID = selectionAnchorID ?? selectedItemIDs.first,
            let anchorIndex = displayedItems.firstIndex(where: { $0.id == anchorID }),
            let targetIndex = displayedItems.firstIndex(where: { $0.id == item.id })
        else {
            selectedItemIDs = [item.id]
            selectionAnchorID = item.id
            return
        }

        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedItemIDs = Set(bounds.map { displayedItems[$0].id })
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

    private static func serverURL(from input: String) -> URL? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        if trimmedInput.hasPrefix("/") || trimmedInput.hasPrefix("~") {
            return nil
        }

        let address: String
        if trimmedInput.contains("://") {
            address = trimmedInput
        } else {
            address = "smb://\(trimmedInput)"
        }

        guard
            let url = URL(string: address),
            let scheme = url.scheme?.lowercased(),
            ["smb", "afp", "nfs", "ftp", "file"].contains(scheme)
        else {
            return nil
        }

        return url
    }
}

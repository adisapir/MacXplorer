import Foundation

@MainActor
final class FileBrowserViewModel: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var pathText: String
    @Published var filterText = ""
    @Published var selectedItemID: FileItem.ID?
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
        var locations: [SidebarLocation] = [
            SidebarLocation(name: "Home", url: FileManager.default.homeDirectoryForCurrentUser, group: .favorites, systemImage: "house"),
            SidebarLocation(name: "Desktop", url: homeSubfolder("Desktop"), group: .favorites, systemImage: "desktopcomputer"),
            SidebarLocation(name: "Documents", url: homeSubfolder("Documents"), group: .favorites, systemImage: "doc.text"),
            SidebarLocation(name: "Downloads", url: homeSubfolder("Downloads"), group: .favorites, systemImage: "arrow.down.circle")
        ]

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
                    systemImage: "externaldrive"
                )
            )
        }

        return locations
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

        if selectedItem.isDirectory && !selectedItem.isPackage {
            navigate(to: selectedItem.url)
        } else {
            SystemActions.open(selectedItem.url)
        }
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

        do {
            try await fileSystem.moveToTrash(selectedItem.url)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealSelectedInFinder() {
        SystemActions.revealInFinder(selectedItem?.url ?? currentURL)
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

    private func homeSubfolder(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
    }
}

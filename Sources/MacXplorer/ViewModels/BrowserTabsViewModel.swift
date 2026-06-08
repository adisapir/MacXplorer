import Foundation

@MainActor
final class BrowserTabsViewModel: ObservableObject {
    struct BrowserTab: Identifiable {
        let id: UUID
        let model: FileBrowserViewModel
    }

    @Published private(set) var tabs: [BrowserTab]
    @Published var selectedTabID: BrowserTab.ID
    @Published private(set) var maximumConcurrentTabs: Int

    init(maximumConcurrentTabs: Int = 20) {
        let initialTab = Self.makeTab()
        self.tabs = [initialTab]
        self.selectedTabID = initialTab.id
        self.maximumConcurrentTabs = Self.clampedTabLimit(maximumConcurrentTabs)
    }

    var activeTab: BrowserTab {
        tabs.first { $0.id == selectedTabID } ?? tabs[0]
    }

    var activeModel: FileBrowserViewModel {
        activeTab.model
    }

    var canAddTab: Bool {
        tabs.count < maximumConcurrentTabs
    }

    func addTab() {
        guard canAddTab else {
            return
        }

        let tab = Self.makeTab()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func updateMaximumConcurrentTabs(_ maximumConcurrentTabs: Int) {
        self.maximumConcurrentTabs = Self.clampedTabLimit(maximumConcurrentTabs)
    }

    func selectTab(_ tabID: BrowserTab.ID) {
        guard tabs.contains(where: { $0.id == tabID }) else {
            return
        }

        selectedTabID = tabID
    }

    private static func makeTab() -> BrowserTab {
        BrowserTab(
            id: UUID(),
            model: FileBrowserViewModel(fileSystem: LocalFileSystemService())
        )
    }

    private static func clampedTabLimit(_ value: Int) -> Int {
        min(max(value, AppSettings.maximumConcurrentTabsRange.lowerBound), AppSettings.maximumConcurrentTabsRange.upperBound)
    }
}

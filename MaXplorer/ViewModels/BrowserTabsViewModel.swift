import Foundation
import Combine

@MainActor
final class BrowserTabsViewModel: ObservableObject {
    struct BrowserTab: Identifiable {
        let id: UUID
        let model: FileBrowserViewModel
    }

    @Published private(set) var tabs: [BrowserTab]
    @Published var selectedTabID: BrowserTab.ID {
        didSet {
            observeActiveModel()
        }
    }
    @Published private(set) var maximumConcurrentTabs: Int

    // Forwards the active tab's model changes so that anything observing this
    // object (notably the App scene's `.commands`, which cannot observe the
    // per-tab model directly) re-evaluates when selection or contents change.
    // Without this, menu items whose `.disabled` state depends on the model
    // stay stuck at their launch-time value and their keyboard shortcuts never
    // fire once enabled.
    private var activeModelObservation: AnyCancellable?

    init(maximumConcurrentTabs: Int = 20) {
        let initialTab = Self.makeTab()
        self.tabs = [initialTab]
        self.selectedTabID = initialTab.id
        self.maximumConcurrentTabs = Self.clampedTabLimit(maximumConcurrentTabs)
        observeActiveModel()
    }

    private func observeActiveModel() {
        activeModelObservation = activeModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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

    var canCycleTabs: Bool {
        tabs.count > 1
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
        activeModel.showCurrentFolder()
    }

    func selectNextTab() {
        selectTab(offset: 1)
    }

    func selectPreviousTab() {
        selectTab(offset: -1)
    }

    private func selectTab(offset: Int) {
        guard
            tabs.count > 1,
            let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID })
        else {
            return
        }

        let nextIndex = (selectedIndex + offset + tabs.count) % tabs.count
        selectedTabID = tabs[nextIndex].id
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

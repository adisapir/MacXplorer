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

    func closeTab(_ tabID: BrowserTab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        let wasSelected = selectedTabID == tabID
        tabs.remove(at: index)

        if wasSelected {
            let neighbor = tabs[min(index, tabs.count - 1)]
            selectedTabID = neighbor.id
        }
    }

    /// Moves the dragged tab so that it lands ahead of `targetID` (used by the
    /// tab strip's drag-to-reorder).
    func moveTab(_ tabID: BrowserTab.ID, before targetID: BrowserTab.ID) {
        guard tabID != targetID,
              let fromIndex = tabs.firstIndex(where: { $0.id == tabID }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let moved = tabs.remove(at: fromIndex)
        let insertionIndex = tabs.firstIndex(where: { $0.id == targetID }) ?? targetIndex
        tabs.insert(moved, at: insertionIndex)
    }

    func sortTabsByName() {
        tabs.sort { lhs, rhs in
            lhs.model.tabTitle.localizedStandardCompare(rhs.model.tabTitle) == .orderedAscending
        }
    }

    /// Keeps the first tab pointing at each location and closes the rest.
    func closeDuplicateTabs() {
        var seenLocations = Set<String>()
        var survivors: [BrowserTab] = []

        for tab in tabs {
            let key = tab.model.currentURL.standardizedFileURL.absoluteString
            if seenLocations.insert(key).inserted {
                survivors.append(tab)
            }
        }

        guard survivors.count != tabs.count else {
            return
        }

        tabs = survivors
        if !survivors.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = survivors[0].id
        }
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

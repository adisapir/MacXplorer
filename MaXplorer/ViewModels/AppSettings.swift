import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private static let appearanceKey = "AppAppearance"
    private static let maximumConcurrentTabsKey = "MaximumConcurrentTabs"
    private static let manualFolderHistoryLimitKey = "ManualFolderHistoryLimit"
    private static let manualFolderHistoryKey = "ManualFolderHistory"
    private static let maximumConcurrentCopiedFilesKey = "MaximumConcurrentCopiedFiles"
    private static let visibleColumnsKey = "VisibleFileColumns"
    static let maximumConcurrentTabsRange = 5...50
    static let manualFolderHistoryLimitRange = 0...20
    static let maximumConcurrentCopiedFilesRange = 1...5

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    @Published var maximumConcurrentTabs: Int {
        didSet {
            let clampedValue = Self.clampedTabLimit(maximumConcurrentTabs)
            guard maximumConcurrentTabs == clampedValue else {
                maximumConcurrentTabs = clampedValue
                return
            }

            UserDefaults.standard.set(maximumConcurrentTabs, forKey: Self.maximumConcurrentTabsKey)
        }
    }

    @Published var manualFolderHistoryLimit: Int {
        didSet {
            let clampedValue = Self.clampedManualFolderHistoryLimit(manualFolderHistoryLimit)
            guard manualFolderHistoryLimit == clampedValue else {
                manualFolderHistoryLimit = clampedValue
                return
            }

            UserDefaults.standard.set(manualFolderHistoryLimit, forKey: Self.manualFolderHistoryLimitKey)
            trimManualFolderHistory()
        }
    }

    @Published var maximumConcurrentCopiedFiles: Int {
        didSet {
            let clampedValue = Self.clampedMaximumConcurrentCopiedFiles(maximumConcurrentCopiedFiles)
            guard maximumConcurrentCopiedFiles == clampedValue else {
                maximumConcurrentCopiedFiles = clampedValue
                return
            }

            UserDefaults.standard.set(maximumConcurrentCopiedFiles, forKey: Self.maximumConcurrentCopiedFilesKey)
        }
    }

    @Published var visibleColumns: Set<FileColumn> {
        didSet {
            // "Name" can never be turned off, so at least one column always remains.
            guard visibleColumns.contains(.name) else {
                visibleColumns.insert(.name)
                return
            }

            UserDefaults.standard.set(visibleColumns.map(\.rawValue), forKey: Self.visibleColumnsKey)
        }
    }

    @Published private(set) var manualFolderHistory: [String]

    init(defaults: UserDefaults = .standard) {
        let rawValue = defaults.string(forKey: Self.appearanceKey)
        self.appearance = rawValue.flatMap(AppAppearance.init(rawValue:)) ?? .system

        let savedTabLimit = defaults.integer(forKey: Self.maximumConcurrentTabsKey)
        self.maximumConcurrentTabs = savedTabLimit == 0 ? 20 : Self.clampedTabLimit(savedTabLimit)

        let savedManualFolderHistoryLimit = defaults.object(forKey: Self.manualFolderHistoryLimitKey) as? Int
        self.manualFolderHistoryLimit = savedManualFolderHistoryLimit.map(Self.clampedManualFolderHistoryLimit) ?? 5
        self.manualFolderHistory = defaults.stringArray(forKey: Self.manualFolderHistoryKey) ?? []

        let savedMaximumConcurrentCopiedFiles = defaults.object(forKey: Self.maximumConcurrentCopiedFilesKey) as? Int
        self.maximumConcurrentCopiedFiles = savedMaximumConcurrentCopiedFiles.map(Self.clampedMaximumConcurrentCopiedFiles) ?? 3

        if let savedColumns = defaults.stringArray(forKey: Self.visibleColumnsKey) {
            var columns = Set(savedColumns.compactMap(FileColumn.init(rawValue:)))
            columns.insert(.name)
            self.visibleColumns = columns
        } else {
            self.visibleColumns = FileColumn.defaultVisible
        }

        trimManualFolderHistory()
    }

    func toggleColumn(_ column: FileColumn) {
        guard !column.isRequired else {
            return
        }

        if visibleColumns.contains(column) {
            visibleColumns.remove(column)
        } else {
            visibleColumns.insert(column)
        }
    }

    func addManualFolderToHistory(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        guard manualFolderHistoryLimit > 0 else {
            manualFolderHistory = []
            UserDefaults.standard.set(manualFolderHistory, forKey: Self.manualFolderHistoryKey)
            return
        }

        let path = url.standardizedFileURL.path
        manualFolderHistory.removeAll { $0 == path }
        manualFolderHistory.insert(path, at: 0)
        trimManualFolderHistory()
    }

    private static func clampedTabLimit(_ value: Int) -> Int {
        min(max(value, maximumConcurrentTabsRange.lowerBound), maximumConcurrentTabsRange.upperBound)
    }

    private static func clampedManualFolderHistoryLimit(_ value: Int) -> Int {
        min(max(value, manualFolderHistoryLimitRange.lowerBound), manualFolderHistoryLimitRange.upperBound)
    }

    private static func clampedMaximumConcurrentCopiedFiles(_ value: Int) -> Int {
        min(max(value, maximumConcurrentCopiedFilesRange.lowerBound), maximumConcurrentCopiedFilesRange.upperBound)
    }

    private func trimManualFolderHistory() {
        var seenPaths = Set<String>()
        manualFolderHistory = manualFolderHistory.compactMap { path in
            guard !seenPaths.contains(path) else {
                return nil
            }

            seenPaths.insert(path)
            return path
        }
        manualFolderHistory = Array(manualFolderHistory.prefix(manualFolderHistoryLimit))
        UserDefaults.standard.set(manualFolderHistory, forKey: Self.manualFolderHistoryKey)
    }
}

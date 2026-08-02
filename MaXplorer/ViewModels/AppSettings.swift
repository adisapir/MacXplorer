import AppKit
import Combine
import CoreFoundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private static let appearanceKey = "AppAppearance"
    private static let maximumConcurrentTabsKey = "MaximumConcurrentTabs"
    private static let manualFolderHistoryLimitKey = "ManualFolderHistoryLimit"
    private static let manualFolderHistoryKey = "ManualFolderHistory"
    private static let serverConnectionHistoryKey = "ServerConnectionHistory"
    private static let maximumConcurrentCopiedFilesKey = "MaximumConcurrentCopiedFiles"
    private static let visibleColumnsKey = "VisibleFileColumns"
    private static let bandedFileRowsKey = "BandedFileRows"
    static let maximumConcurrentTabsRange = 5...50
    static let manualFolderHistoryLimitRange = 0...20
    static let maximumConcurrentCopiedFilesRange = 1...5

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }
    @Published private(set) var systemColorScheme: ColorScheme

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

    @Published var showsBandedFileRows: Bool {
        didSet {
            UserDefaults.standard.set(showsBandedFileRows, forKey: Self.bandedFileRowsKey)
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
    @Published private(set) var serverConnectionHistory: [String]
    private var appearanceObservation: NSObjectProtocol?
    private var volumeMountObservation: NSObjectProtocol?
    private var pendingServerConnections: [URL] = []
    var onServerConnectionSucceeded: ((URL) -> Void)?

    init(defaults: UserDefaults = .standard) {
        let rawValue = defaults.string(forKey: Self.appearanceKey)
        self.appearance = rawValue.flatMap(AppAppearance.init(rawValue:)) ?? .system
        self.systemColorScheme = Self.currentSystemColorScheme

        let savedTabLimit = defaults.integer(forKey: Self.maximumConcurrentTabsKey)
        self.maximumConcurrentTabs = savedTabLimit == 0 ? 20 : Self.clampedTabLimit(savedTabLimit)

        let savedManualFolderHistoryLimit = defaults.object(forKey: Self.manualFolderHistoryLimitKey) as? Int
        self.manualFolderHistoryLimit = savedManualFolderHistoryLimit.map(Self.clampedManualFolderHistoryLimit) ?? 5
        self.manualFolderHistory = defaults.stringArray(forKey: Self.manualFolderHistoryKey) ?? []
        self.serverConnectionHistory = defaults.stringArray(forKey: Self.serverConnectionHistoryKey) ?? []

        let savedMaximumConcurrentCopiedFiles = defaults.object(forKey: Self.maximumConcurrentCopiedFilesKey) as? Int
        self.maximumConcurrentCopiedFiles = savedMaximumConcurrentCopiedFiles.map(Self.clampedMaximumConcurrentCopiedFiles) ?? 3
        self.showsBandedFileRows = defaults.object(forKey: Self.bandedFileRowsKey) as? Bool ?? true

        if let savedColumns = defaults.stringArray(forKey: Self.visibleColumnsKey) {
            var columns = Set(savedColumns.compactMap(FileColumn.init(rawValue:)))
            columns.insert(.name)
            self.visibleColumns = columns
        } else {
            self.visibleColumns = FileColumn.defaultVisible
        }

        trimManualFolderHistory()
        trimServerConnectionHistory()
        appearanceObservation = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.systemColorScheme = Self.currentSystemColorScheme
            }
        }
        volumeMountObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mountedVolumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
                return
            }

            Task { @MainActor [weak self] in
                self?.recordPendingConnection(mountedAt: mountedVolumeURL)
            }
        }
    }

    var preferredColorScheme: ColorScheme {
        appearance.colorScheme ?? systemColorScheme
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

    func expectServerConnection(to url: URL) {
        let sanitizedURL = Self.sanitizedServerURL(url)
        pendingServerConnections.removeAll { Self.serverURLsReferToSameShare($0, sanitizedURL) }
        pendingServerConnections.append(sanitizedURL)

        for mountedVolumeURL in FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeURLForRemountingKey],
            options: [.skipHiddenVolumes]
        ) ?? [] {
            if recordPendingConnection(mountedAt: mountedVolumeURL) {
                break
            }
        }
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

    private static var currentSystemColorScheme: ColorScheme {
        let interfaceStyle = CFPreferencesCopyValue(
            "AppleInterfaceStyle" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String
        return interfaceStyle == "Dark" ? .dark : .light
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

    @discardableResult
    private func recordPendingConnection(mountedAt mountedVolumeURL: URL) -> Bool {
        guard
            let values = try? mountedVolumeURL.resourceValues(forKeys: [.volumeURLForRemountingKey]),
            let remountURL = values.volumeURLForRemounting,
            let pendingIndex = pendingServerConnections.firstIndex(where: {
                Self.serverURLsReferToSameShare($0, remountURL)
            })
        else {
            return false
        }

        let connectedURL = pendingServerConnections.remove(at: pendingIndex)
        let address = connectedURL.absoluteString
        serverConnectionHistory.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
        serverConnectionHistory.insert(address, at: 0)
        trimServerConnectionHistory()
        onServerConnectionSucceeded?(mountedVolumeURL)
        return true
    }

    private func trimServerConnectionHistory() {
        var seenAddresses = Set<String>()
        serverConnectionHistory = serverConnectionHistory.compactMap { address in
            let comparisonAddress = address.lowercased()
            guard seenAddresses.insert(comparisonAddress).inserted else {
                return nil
            }
            return address
        }
        serverConnectionHistory = Array(serverConnectionHistory.prefix(20))
        UserDefaults.standard.set(serverConnectionHistory, forKey: Self.serverConnectionHistoryKey)
    }

    private static func sanitizedServerURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.password = nil
        return components.url ?? url
    }

    private static func serverURLsReferToSameShare(_ lhs: URL, _ rhs: URL) -> Bool {
        guard
            let lhsComponents = URLComponents(url: lhs, resolvingAgainstBaseURL: false),
            let rhsComponents = URLComponents(url: rhs, resolvingAgainstBaseURL: false),
            lhsComponents.scheme?.caseInsensitiveCompare(rhsComponents.scheme ?? "") == .orderedSame,
            lhsComponents.host?.caseInsensitiveCompare(rhsComponents.host ?? "") == .orderedSame
        else {
            return false
        }

        let lhsShare = firstPathComponent(of: lhsComponents.path)
        let rhsShare = firstPathComponent(of: rhsComponents.path)
        return lhsShare.isEmpty
            || rhsShare.isEmpty
            || lhsShare.caseInsensitiveCompare(rhsShare) == .orderedSame
    }

    private static func firstPathComponent(of path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }
}

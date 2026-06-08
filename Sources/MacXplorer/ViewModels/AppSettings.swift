import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private static let appearanceKey = "AppAppearance"
    private static let maximumConcurrentTabsKey = "MaximumConcurrentTabs"
    static let maximumConcurrentTabsRange = 5...50

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

    init(defaults: UserDefaults = .standard) {
        let rawValue = defaults.string(forKey: Self.appearanceKey)
        self.appearance = rawValue.flatMap(AppAppearance.init(rawValue:)) ?? .system

        let savedTabLimit = defaults.integer(forKey: Self.maximumConcurrentTabsKey)
        self.maximumConcurrentTabs = savedTabLimit == 0 ? 20 : Self.clampedTabLimit(savedTabLimit)
    }

    private static func clampedTabLimit(_ value: Int) -> Int {
        min(max(value, maximumConcurrentTabsRange.lowerBound), maximumConcurrentTabsRange.upperBound)
    }
}

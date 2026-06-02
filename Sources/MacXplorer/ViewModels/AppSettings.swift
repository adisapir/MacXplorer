import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private static let appearanceKey = "AppAppearance"

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        let rawValue = defaults.string(forKey: Self.appearanceKey)
        self.appearance = rawValue.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}

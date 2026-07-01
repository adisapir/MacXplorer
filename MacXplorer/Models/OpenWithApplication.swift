import Foundation

struct OpenWithApplication: Identifiable, Hashable {
    var id: URL { url }

    let url: URL
    let name: String
    let bundleIdentifier: String?
}

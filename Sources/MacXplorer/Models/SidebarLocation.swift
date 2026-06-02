import Foundation
import SwiftUI

struct SidebarLocation: Identifiable, Hashable {
    enum Group: String {
        case favorites = "Favorites"
        case devices = "Devices"
    }

    var id: URL { url }

    let name: String
    let url: URL
    let group: Group
    let systemImage: String
    let isPinned: Bool

    init(name: String, url: URL, group: Group, systemImage: String, isPinned: Bool = false) {
        self.name = name
        self.url = url
        self.group = group
        self.systemImage = systemImage
        self.isPinned = isPinned
    }
}

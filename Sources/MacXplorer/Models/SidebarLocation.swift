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
}

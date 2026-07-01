import Foundation

struct QuickViewContent: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let detail: String
    let text: String
}

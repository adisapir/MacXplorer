import Foundation
import CoreGraphics

final class SpaceNode: Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let name: String
    var size: UInt64        // bytes; for dirs = sum of subtree
    var children: [SpaceNode]
    let isDirectory: Bool
    var layoutFrame: CGRect = .zero

    init(url: URL, name: String, size: UInt64, isDirectory: Bool, children: [SpaceNode] = []) {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
    }
}

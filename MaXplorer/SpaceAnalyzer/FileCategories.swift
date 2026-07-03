import Foundation
import SwiftUI

// MARK: – Models

struct FileCategory: Decodable {
    let name: String
    let color: String
    let extensions: [String]
}

struct FileCategoryConfig: Decodable {
    let categories: [FileCategory]
    let uncategorizedColor: String
}

// MARK: – Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

// MARK: – Service

final class FileCategoryService {
    private let config: FileCategoryConfig
    /// Extension string (lowercased) → Color
    private let extensionToColor: [String: Color]
    private let _uncategorizedColor: Color
    private let _directoryColor: Color = Color(red: 0.5, green: 0.55, blue: 0.62).opacity(0.4)

    init() {
        let loaded: FileCategoryConfig?
        if let url = Bundle.main.url(forResource: "file-categories", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(FileCategoryConfig.self, from: data) {
            loaded = decoded
        } else {
            loaded = nil
        }

        let cfg = loaded ?? FileCategoryConfig(categories: [], uncategorizedColor: "#7F8C8D")
        self.config = cfg
        self._uncategorizedColor = Color(hex: cfg.uncategorizedColor)

        var map: [String: Color] = [:]
        for category in cfg.categories {
            let color = Color(hex: category.color)
            for ext in category.extensions {
                map[ext.lowercased()] = color
            }
        }
        self.extensionToColor = map
    }

    func color(for url: URL) -> Color {
        let ext = url.pathExtension.lowercased()
        return extensionToColor[ext] ?? _uncategorizedColor
    }

    var directoryColor: Color {
        _directoryColor
    }

    var uncategorizedColor: Color {
        _uncategorizedColor
    }
}

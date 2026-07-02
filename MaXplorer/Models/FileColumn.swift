import Foundation

/// A selectable column in the file table. `name` is always shown and cannot be
/// hidden; the rest can be toggled from the column chooser and are persisted.
/// Declaration order here is the canonical left-to-right display order.
enum FileColumn: String, CaseIterable, Identifiable, Codable {
    case name
    case kind
    case size
    case dateModified
    case dateCreated
    case dateTaken
    case owner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .kind: return "Kind"
        case .size: return "Size"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        case .dateTaken: return "Date Taken"
        case .owner: return "Owner"
        }
    }

    /// Required columns are always visible and cannot be unchecked.
    var isRequired: Bool {
        self == .name
    }

    static let defaultVisible: Set<FileColumn> = [.name, .kind, .size, .dateModified]
}

extension DirectoryListingOptions {
    /// Only fetch the slow per-file metadata when its column is visible.
    init(columns: Set<FileColumn>) {
        self.init(
            includeOwner: columns.contains(.owner),
            includeDateTaken: columns.contains(.dateTaken)
        )
    }
}

import Foundation

/// Remembers the sort the user picked in each folder, falling back to the
/// app-wide default from Settings. A folder whose choice matches the default
/// is not stored, so it keeps following the default if that changes later.
@MainActor
final class FolderSortStore {
    static let shared = FolderSortStore()

    private static let folderSortsKey = "FolderSortOrders"
    private static let defaultSortKey = "DefaultSortOrder"
    /// Oldest choices are dropped beyond this many folders.
    private static let maximumRememberedFolders = 500

    private struct Entry: Codable {
        let key: String
        let sort: FileSortDescriptor
    }

    private let defaults: UserDefaults
    /// Most recently used first.
    private var entries: [Entry]

    var defaultSort: FileSortDescriptor {
        didSet {
            guard defaultSort != oldValue else {
                return
            }

            Self.save(defaultSort, forKey: Self.defaultSortKey, in: defaults)
            // Choices equal to the new default are redundant now.
            entries.removeAll { $0.sort == defaultSort }
            saveEntries()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaultSort = Self.load(FileSortDescriptor.self, forKey: Self.defaultSortKey, in: defaults) ?? .fallback
        self.entries = Self.load([Entry].self, forKey: Self.folderSortsKey, in: defaults) ?? []
    }

    func sort(for folderURL: URL) -> FileSortDescriptor {
        let key = Self.key(for: folderURL)
        return entries.first { $0.key == key }?.sort ?? defaultSort
    }

    func remember(_ sort: FileSortDescriptor, for folderURL: URL) {
        let key = Self.key(for: folderURL)
        let existing = entries.first { $0.key == key }
        if let existing, existing.sort == sort {
            return
        }
        if existing == nil && sort == defaultSort {
            return
        }

        entries.removeAll { $0.key == key }
        if sort != defaultSort {
            entries.insert(Entry(key: key, sort: sort), at: 0)
            if entries.count > Self.maximumRememberedFolders {
                entries.removeLast(entries.count - Self.maximumRememberedFolders)
            }
        }
        saveEntries()
    }

    func forgetAllFolders() {
        entries = []
        saveEntries()
    }

    private func saveEntries() {
        Self.save(entries, forKey: Self.folderSortsKey, in: defaults)
    }

    private static func key(for folderURL: URL) -> String {
        folderURL.isFileURL ? folderURL.standardizedFileURL.path : folderURL.absoluteString
    }

    private static func load<Value: Decodable>(_ type: Value.Type, forKey key: String, in defaults: UserDefaults) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<Value: Encodable>(_ value: Value, forKey key: String, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

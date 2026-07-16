import Foundation

final class DownloadHistoryStore {
    private let defaults: UserDefaults
    private let key: String
    private let maximumCount: Int

    init(
        defaults: UserDefaults = .standard,
        key: String = "history.downloads",
        maximumCount: Int = 30
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumCount = maximumCount
    }

    func load() -> [DownloadRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ records: [DownloadRecord]) {
        let trimmed = Array(records.prefix(maximumCount))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

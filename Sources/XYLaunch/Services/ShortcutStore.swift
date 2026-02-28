import Foundation

struct ShortcutStore {
    private let defaults: UserDefaults
    private let key = "xylaunch.pinned.shortcuts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [LaunchItem] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([LaunchItem].self, from: data)
        } catch {
            return []
        }
    }

    func save(_ items: [LaunchItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            defaults.set(data, forKey: key)
        } catch {
            defaults.removeObject(forKey: key)
        }
    }
}

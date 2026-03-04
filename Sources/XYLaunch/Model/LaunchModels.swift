import Foundation

enum LaunchItemKind: String, Codable, CaseIterable, Sendable {
    case app
    case folder
    case file
    case url

    var title: String {
        switch self {
        case .app:
            return "应用"
        case .folder:
            return "文件夹"
        case .file:
            return "文件"
        case .url:
            return "网址"
        }
    }
}

struct LaunchItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rawValue: String
    var kind: LaunchItemKind
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        rawValue: String,
        kind: LaunchItemKind,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.rawValue = rawValue
        self.kind = kind
        self.createdAt = createdAt
    }

    var targetURL: URL? {
        switch kind {
        case .url:
            return URL(string: rawValue)
        case .app, .folder, .file:
            return URL(fileURLWithPath: rawValue)
        }
    }
}

struct ApplicationEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let path: String
    let bundleIdentifier: String?

    init(name: String, path: String, bundleIdentifier: String? = nil) {
        self.id = path
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }
}

struct AppFolder: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var appPaths: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        appPaths: [String],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.appPaths = appPaths
        self.createdAt = createdAt
    }
}

struct LauncherPreferences: Hashable, Codable, Sendable {
    var columnCount: Int
    var maxRows: Int
    var iconScale: Double

    static let `default` = LauncherPreferences(
        columnCount: 5,
        maxRows: 7,
        iconScale: 1.0
    )
}

enum LauncherTab: String, CaseIterable, Identifiable {
    case all
    case applications
    case pinned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .applications:
            return "应用"
        case .pinned:
            return "固定"
        }
    }
}

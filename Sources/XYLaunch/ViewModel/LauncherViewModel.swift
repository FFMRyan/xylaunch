import AppKit
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedTab: LauncherTab = .all
    @Published private(set) var applications: [ApplicationEntry] = []
    @Published var pinnedItems: [LaunchItem]
    @Published var isScanning = false
    @Published var errorMessage: String?

    var closePanelAction: (() -> Void)?

    private let store = ShortcutStore()
    private let iconProvider = IconProvider.shared
    private let defaults: UserDefaults
    private let appOrderKey = "xylaunch.app.order.paths"
    private let appCacheKey = "xylaunch.app.cache.entries"
    private let promotedAppleAppPathsKey = "xylaunch.promoted.apple.app.paths"
    private var appOrderPaths: [String]
    private var promotedAppleAppPaths: Set<String>

    init() {
        defaults = .standard
        appOrderPaths = defaults.stringArray(forKey: appOrderKey) ?? []
        promotedAppleAppPaths = Set(defaults.stringArray(forKey: promotedAppleAppPathsKey) ?? [])

        let loadedItems = store.load()
        if loadedItems.isEmpty {
            let defaults = Self.defaultPinnedItems()
            pinnedItems = defaults
            store.save(defaults)
        } else {
            pinnedItems = loadedItems
        }

        let cached = loadCachedApplications()
        applications = applyCustomApplicationOrder(cached)
    }

    var filteredApplications: [ApplicationEntry] {
        let query = searchTokens
        guard !query.isEmpty else {
            return applications
        }
        return applications.filter { app in
            matches(queryTokens: query, in: [app.name, app.path])
        }
    }

    var filteredPinnedItems: [LaunchItem] {
        let query = searchTokens
        guard !query.isEmpty else {
            return pinnedItems
        }
        return pinnedItems.filter { item in
            matches(queryTokens: query, in: [item.name, item.rawValue])
        }
    }

    private var searchTokens: [String] {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private func matches(queryTokens: [String], in fields: [String]) -> Bool {
        let normalizedFields = fields.map { $0.lowercased() }
        return queryTokens.allSatisfy { token in
            normalizedFields.contains { $0.contains(token) }
        }
    }

    func refreshApplications() {
        guard !isScanning else {
            return
        }

        isScanning = true
        errorMessage = nil

        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                AppScanner.scanInstalledApplications()
            }.value

            let ordered = self.applyCustomApplicationOrder(scanned)
            self.prunePromotedAppleAppPaths(using: ordered)
            self.applications = ordered
            self.appOrderPaths = ordered.map(\.path)
            self.persistApplicationOrder()
            self.persistApplicationCache(ordered)
            self.iconProvider.clear()
            self.isScanning = false
        }
    }

    func isPromotedAppleApplication(path: String) -> Bool {
        promotedAppleAppPaths.contains(path)
    }

    func promoteAppleApplicationToTopLevel(path: String) {
        guard let sourceIndex = applications.firstIndex(where: { $0.path == path }) else {
            return
        }
        guard isAppleApplication(applications[sourceIndex]) else {
            return
        }

        if promotedAppleAppPaths.insert(path).inserted {
            persistPromotedAppleAppPaths()
        }

        var updated = applications
        let app = updated.remove(at: sourceIndex)
        updated.insert(app, at: 0)
        applications = updated
        appOrderPaths = updated.map(\.path)
        persistApplicationOrder()
        persistApplicationCache(updated)
    }

    func icon(for application: ApplicationEntry) -> NSImage {
        iconProvider.icon(for: application)
    }

    func icon(for item: LaunchItem) -> NSImage {
        iconProvider.icon(for: item)
    }

    func open(_ application: ApplicationEntry) {
        NSWorkspace.shared.open(application.url)
        closePanelAction?()
    }

    func open(_ item: LaunchItem) {
        guard let targetURL = item.targetURL else {
            errorMessage = "无效的目标地址：\(item.name)"
            return
        }
        NSWorkspace.shared.open(targetURL)
        closePanelAction?()
    }

    func addPinnedByOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要固定的项目"
        panel.prompt = "添加到启动台"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false

        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            self?.insertPinned(urls: panel.urls)
        }
    }

    func addPinnedURL(from input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "网址不能为空"
            return
        }

        let normalized: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            normalized = trimmed
        } else {
            normalized = "https://\(trimmed)"
        }

        guard let url = URL(string: normalized), let host = url.host, !host.isEmpty else {
            errorMessage = "网址格式不正确"
            return
        }

        let existing = pinnedItems.contains {
            $0.kind == .url && $0.rawValue.caseInsensitiveCompare(url.absoluteString) == .orderedSame
        }
        guard !existing else {
            errorMessage = "该网址已存在"
            return
        }

        pinnedItems.insert(
            LaunchItem(name: host, rawValue: url.absoluteString, kind: .url),
            at: 0
        )
        persistPinnedItems()
        errorMessage = nil
    }

    func removePinned(_ item: LaunchItem) {
        pinnedItems.removeAll { $0.id == item.id }
        persistPinnedItems()
    }

    func removePinned(at offsets: IndexSet) {
        pinnedItems.remove(atOffsets: offsets)
        persistPinnedItems()
    }

    func movePinned(from source: IndexSet, to destination: Int) {
        pinnedItems.move(fromOffsets: source, toOffset: destination)
        persistPinnedItems()
    }

    func movePinnedUp(_ item: LaunchItem) {
        movePinned(item, by: -1)
    }

    func movePinnedDown(_ item: LaunchItem) {
        movePinned(item, by: 1)
    }

    func movePinnedItem(withId movingID: UUID, before targetID: UUID) {
        guard
            let sourceIndex = pinnedItems.firstIndex(where: { $0.id == movingID }),
            let targetIndex = pinnedItems.firstIndex(where: { $0.id == targetID }),
            sourceIndex != targetIndex
        else {
            return
        }

        // `move(toOffset:)` uses the index after removing the source item.
        // To place before target, we need to shift destination left when moving downward.
        let destination = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        pinnedItems.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        persistPinnedItems()
    }

    func moveApplication(path movingPath: String, before targetPath: String) {
        guard
            let sourceIndex = applications.firstIndex(where: { $0.path == movingPath }),
            let targetIndex = applications.firstIndex(where: { $0.path == targetPath }),
            sourceIndex != targetIndex
        else {
            return
        }

        var updated = applications
        // `move(toOffset:)` uses the index after removing the source item.
        // To place before target, we need to shift destination left when moving downward.
        let destination = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        updated.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        applications = updated
        appOrderPaths = updated.map(\.path)
        persistApplicationOrder()
    }

    func requestClosePanel() {
        closePanelAction?()
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    private func insertPinned(urls: [URL]) {
        var hasNewItems = false

        for url in urls {
            let kind = classifyKind(for: url)
            let rawValue = url.path
            let duplicate = pinnedItems.contains { item in
                item.kind == kind && item.rawValue == rawValue
            }
            guard !duplicate else {
                continue
            }

            pinnedItems.insert(
                LaunchItem(
                    name: displayName(for: url, kind: kind),
                    rawValue: rawValue,
                    kind: kind
                ),
                at: 0
            )
            hasNewItems = true
        }

        if hasNewItems {
            persistPinnedItems()
            errorMessage = nil
        }
    }

    private func classifyKind(for url: URL) -> LaunchItemKind {
        if url.pathExtension.lowercased() == "app" {
            return .app
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
        if values?.isApplication == true {
            return .app
        }
        if values?.isDirectory == true {
            return .folder
        }
        return .file
    }

    private func displayName(for url: URL, kind: LaunchItemKind) -> String {
        if kind == .app, let bundle = Bundle(url: url) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.isEmpty {
                return displayName
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !name.isEmpty {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func persistPinnedItems() {
        store.save(pinnedItems)
    }

    private func persistApplicationOrder() {
        defaults.set(appOrderPaths, forKey: appOrderKey)
    }

    private func persistApplicationCache(_ apps: [ApplicationEntry]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(apps) else {
            return
        }
        defaults.set(data, forKey: appCacheKey)
    }

    private func persistPromotedAppleAppPaths() {
        defaults.set(Array(promotedAppleAppPaths), forKey: promotedAppleAppPathsKey)
    }

    private func loadCachedApplications() -> [ApplicationEntry] {
        guard let data = defaults.data(forKey: appCacheKey) else {
            return []
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode([ApplicationEntry].self, from: data)) ?? []
    }

    private func applyCustomApplicationOrder(_ scanned: [ApplicationEntry]) -> [ApplicationEntry] {
        guard !appOrderPaths.isEmpty else {
            return scanned
        }

        let rankMap = Dictionary(uniqueKeysWithValues: appOrderPaths.enumerated().map { ($1, $0) })
        return scanned.sorted { lhs, rhs in
            let lhsRank = rankMap[lhs.path] ?? Int.max
            let rhsRank = rankMap[rhs.path] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func prunePromotedAppleAppPaths(using apps: [ApplicationEntry]) {
        let appByPath = Dictionary(uniqueKeysWithValues: apps.map { ($0.path, $0) })
        let validPaths = promotedAppleAppPaths.filter { path in
            guard let app = appByPath[path] else {
                return false
            }
            return isAppleApplication(app)
        }
        if validPaths == promotedAppleAppPaths {
            return
        }
        promotedAppleAppPaths = validPaths
        persistPromotedAppleAppPaths()
    }

    private func isAppleApplication(_ app: ApplicationEntry) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier?.lowercased() else {
            return false
        }
        return bundleIdentifier.hasPrefix("com.apple.")
    }

    private func movePinned(_ item: LaunchItem, by offset: Int) {
        guard let currentIndex = pinnedItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let newIndex = max(0, min(pinnedItems.count - 1, currentIndex + offset))
        guard newIndex != currentIndex else {
            return
        }

        let destination = offset > 0 ? newIndex + 1 : newIndex
        pinnedItems.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: destination)
        persistPinnedItems()
    }

    private static func defaultPinnedItems() -> [LaunchItem] {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [(String, URL)] = [
            ("应用程序", URL(fileURLWithPath: "/Applications", isDirectory: true)),
            ("下载", homeURL.appendingPathComponent("Downloads", isDirectory: true)),
            ("文稿", homeURL.appendingPathComponent("Documents", isDirectory: true)),
            ("桌面", homeURL.appendingPathComponent("Desktop", isDirectory: true)),
        ]

        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.1.path) }
            .map { name, url in
                LaunchItem(name: name, rawValue: url.path, kind: .folder)
            }
    }
}

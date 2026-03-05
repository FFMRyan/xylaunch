import AppKit
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedTab: LauncherTab = .all
    @Published private(set) var applications: [ApplicationEntry] = []
    @Published var pinnedItems: [LaunchItem]
    @Published var folders: [AppFolder]
    @Published var preferences: LauncherPreferences
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published private(set) var settingsRequestToken = 0

    var closePanelAction: (() -> Void)?

    private let store = ShortcutStore()
    private let iconProvider = IconProvider.shared
    private let defaults: UserDefaults
    private let appOrderKey = "xylaunch.app.order.paths"
    private let appCacheKey = "xylaunch.app.cache.entries"
    private let promotedAppleAppPathsKey = "xylaunch.promoted.apple.app.paths"
    private let foldersKey = "xylaunch.folders.v1"
    private let preferencesKey = "xylaunch.preferences.v1"
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

        folders = []
        preferences = .default

        let cached = loadCachedApplications()
        applications = applyCustomApplicationOrder(cached)
        folders = loadFolders()
        preferences = loadPreferences()
        normalizeCachedApplicationNames()
        normalizePinnedAppNames()
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
            self.normalizePinnedAppNames(using: ordered)
            self.iconProvider.clear()
            self.isScanning = false
        }
    }

    func forceRebuildApplicationCache() {
        defaults.removeObject(forKey: appCacheKey)
        iconProvider.clear()
        refreshApplications()
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

    func requestOpenSettings() {
        settingsRequestToken &+= 1
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    func setGridColumns(_ columns: Int) {
        preferences.columnCount = max(3, min(8, columns))
        persistPreferences()
    }

    func setGridRows(_ rows: Int) {
        preferences.maxRows = max(3, min(8, rows))
        persistPreferences()
    }

    func setIconScale(_ scale: Double) {
        preferences.iconScale = max(0.7, min(1.4, scale))
        persistPreferences()
    }

    func createFolder(name: String, appPaths: [String]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = trimmed.isEmpty ? "新建文件夹" : trimmed
        let uniquePaths = Array(Set(appPaths)).sorted()
        guard !uniquePaths.isEmpty else {
            return
        }
        folders.append(AppFolder(name: folderName, appPaths: uniquePaths))
        persistFolders()
    }

    @discardableResult
    func createFolderFromApps(_ appPaths: [String], preferredName: String = "新建文件夹") -> UUID? {
        let uniquePaths = Array(Set(appPaths)).filter { path in
            applications.contains(where: { $0.path == path })
        }
        guard uniquePaths.count >= 2 else {
            return nil
        }

        for path in uniquePaths {
            removePathFromAllFolders(path)
        }
        let folder = AppFolder(name: preferredName, appPaths: uniquePaths)
        folders.append(folder)
        persistFolders()
        return folder.id
    }

    func renameFolder(id: UUID, name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        folders[index].name = trimmed
        persistFolders()
    }

    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        persistFolders()
    }

    func reorderFolder(id movingID: UUID, before targetID: UUID) {
        guard
            let sourceIndex = folders.firstIndex(where: { $0.id == movingID }),
            let targetIndex = folders.firstIndex(where: { $0.id == targetID }),
            sourceIndex != targetIndex
        else {
            return
        }

        let destination = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        folders.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        persistFolders()
    }

    func moveApps(_ appPaths: [String], toFolder folderID: UUID) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }
        var existing = Set(folders[folderIndex].appPaths)
        for path in appPaths where applications.contains(where: { $0.path == path }) {
            removePathFromAllFolders(path, excluding: folderID)
            existing.insert(path)
        }
        folders[folderIndex].appPaths = Array(existing)
        persistFolders()
    }

    func removeApp(_ appPath: String, fromFolder folderID: UUID) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }
        folders[folderIndex].appPaths.removeAll { $0 == appPath }
        persistFolders()
    }

    func moveAppInFolder(folderID: UUID, appPath movingPath: String, before targetPath: String) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }
        guard
            let sourceIndex = folders[folderIndex].appPaths.firstIndex(of: movingPath),
            let targetIndex = folders[folderIndex].appPaths.firstIndex(of: targetPath),
            sourceIndex != targetIndex
        else {
            return
        }

        let destination = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        folders[folderIndex].appPaths.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: destination
        )
        persistFolders()
    }

    func moveAppToTopLevel(_ appPath: String) {
        removePathFromAllFolders(appPath)
        persistFolders()
    }

    func folderContaining(appPath: String) -> AppFolder? {
        folders.first(where: { $0.appPaths.contains(appPath) })
    }

    private func removePathFromAllFolders(_ appPath: String, excluding folderID: UUID? = nil) {
        var hasChanges = false
        for index in folders.indices {
            if let folderID, folders[index].id == folderID {
                continue
            }
            let originalCount = folders[index].appPaths.count
            folders[index].appPaths.removeAll { $0 == appPath }
            if folders[index].appPaths.count != originalCount {
                hasChanges = true
            }
        }

        if hasChanges {
            folders.removeAll { $0.appPaths.isEmpty }
        }
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
        if kind == .app {
            return AppNameResolver.localizedName(forAppURL: url)
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func persistPinnedItems() {
        store.save(pinnedItems)
    }

    private func normalizeCachedApplicationNames() {
        var hasChanges = false
        let normalizedApps = applications.map { app -> ApplicationEntry in
            let localizedName = AppNameResolver.localizedName(forAppURL: app.url)
            guard localizedName != app.name else {
                return app
            }
            hasChanges = true
            return ApplicationEntry(
                name: localizedName,
                path: app.path,
                bundleIdentifier: app.bundleIdentifier
            )
        }

        guard hasChanges else {
            return
        }
        applications = normalizedApps
        persistApplicationCache(normalizedApps)
    }

    private func normalizePinnedAppNames(using applications: [ApplicationEntry]? = nil) {
        let appNameByPath: [String: String]
        if let applications {
            appNameByPath = Dictionary(uniqueKeysWithValues: applications.map { ($0.path, $0.name) })
        } else {
            appNameByPath = [:]
        }

        var hasChanges = false
        for index in pinnedItems.indices {
            guard pinnedItems[index].kind == .app else {
                continue
            }
            let path = pinnedItems[index].rawValue
            let resolvedName = appNameByPath[path]
                ?? AppNameResolver.localizedName(forAppURL: URL(fileURLWithPath: path))
            guard !resolvedName.isEmpty, pinnedItems[index].name != resolvedName else {
                continue
            }
            pinnedItems[index].name = resolvedName
            hasChanges = true
        }

        if hasChanges {
            persistPinnedItems()
        }
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

    private func persistFolders() {
        guard let data = try? JSONEncoder().encode(folders) else {
            return
        }
        defaults.set(data, forKey: foldersKey)
    }

    private func loadFolders() -> [AppFolder] {
        guard let data = defaults.data(forKey: foldersKey) else {
            return []
        }
        return (try? JSONDecoder().decode([AppFolder].self, from: data)) ?? []
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        defaults.set(data, forKey: preferencesKey)
    }

    private func loadPreferences() -> LauncherPreferences {
        guard let data = defaults.data(forKey: preferencesKey) else {
            return .default
        }
        return (try? JSONDecoder().decode(LauncherPreferences.self, from: data)) ?? .default
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

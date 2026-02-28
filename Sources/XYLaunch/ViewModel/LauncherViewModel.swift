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

    init() {
        let loadedItems = store.load()
        if loadedItems.isEmpty {
            let defaults = Self.defaultPinnedItems()
            pinnedItems = defaults
            store.save(defaults)
        } else {
            pinnedItems = loadedItems
        }
    }

    var filteredApplications: [ApplicationEntry] {
        guard !searchText.isEmpty else {
            return applications
        }
        return applications.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText)
                || app.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredPinnedItems: [LaunchItem] {
        guard !searchText.isEmpty else {
            return pinnedItems
        }
        return pinnedItems.filter { item in
            item.name.localizedCaseInsensitiveContains(searchText)
                || item.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    func refreshApplications() {
        isScanning = true
        errorMessage = nil

        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                AppScanner.scanInstalledApplications()
            }.value

            self.applications = scanned
            self.iconProvider.clear()
            self.isScanning = false
        }
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

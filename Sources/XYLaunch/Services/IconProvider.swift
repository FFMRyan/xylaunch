import AppKit

@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private var cache: [String: NSImage] = [:]

    private init() {}

    func icon(for application: ApplicationEntry) -> NSImage {
        icon(forPath: application.path, fallbackSymbol: "app.dashed")
    }

    func icon(for item: LaunchItem) -> NSImage {
        switch item.kind {
        case .url:
            return symbolImage(named: "network")
        case .app, .folder, .file:
            return icon(forPath: item.rawValue, fallbackSymbol: "doc")
        }
    }

    func clear() {
        cache.removeAll()
    }

    private func icon(forPath path: String, fallbackSymbol: String) -> NSImage {
        if let cached = cache[path] {
            return cached
        }

        let image: NSImage
        if FileManager.default.fileExists(atPath: path) {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = symbolImage(named: fallbackSymbol)
        }
        image.size = NSSize(width: 56, height: 56)
        cache[path] = image
        return image
    }

    private func symbolImage(named symbol: String) -> NSImage {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
    }
}

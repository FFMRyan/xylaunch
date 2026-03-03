import Foundation

enum AppScanner {
    static func scanInstalledApplications() -> [ApplicationEntry] {
        let manager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        var seenPaths = Set<String>()
        var discoveredApps: [ApplicationEntry] = []

        for root in roots where manager.fileExists(atPath: root.path) {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let appURL as URL in enumerator where appURL.pathExtension.lowercased() == "app" {
                let appPath = appURL.path
                guard seenPaths.insert(appPath).inserted else {
                    continue
                }

                discoveredApps.append(
                    ApplicationEntry(
                        name: displayName(for: appURL),
                        path: appPath,
                        bundleIdentifier: Bundle(url: appURL)?.bundleIdentifier
                    )
                )
            }
        }

        return discoveredApps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func displayName(for appURL: URL) -> String {
        let localizedFileName = FileManager.default.displayName(atPath: appURL.path)
        if !localizedFileName.isEmpty, localizedFileName != appURL.lastPathComponent {
            return localizedFileName
        }

        if let bundle = Bundle(url: appURL) {
            if let localizedDisplayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
               !localizedDisplayName.isEmpty {
                return localizedDisplayName
            }
            if let localizedName = bundle.localizedInfoDictionary?["CFBundleName"] as? String,
               !localizedName.isEmpty {
                return localizedName
            }
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.isEmpty {
                return displayName
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !name.isEmpty {
                return name
            }
        }
        return appURL.deletingPathExtension().lastPathComponent
    }
}

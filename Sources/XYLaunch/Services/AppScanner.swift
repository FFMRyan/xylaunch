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
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .localizedNameKey],
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
                        name: AppNameResolver.localizedName(forAppURL: appURL),
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

}

import Foundation
import CoreServices

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
                        name: launchServicesDisplayName(for: appURL)
                            ?? AppNameResolver.localizedName(forAppURL: appURL),
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

    private static func launchServicesDisplayName(for appURL: URL) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        let status = LSCopyDisplayNameForURL(appURL as CFURL, &unmanagedName)
        guard status == noErr, let unmanagedName else {
            return nil
        }
        let value = (unmanagedName.takeRetainedValue() as String)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

}

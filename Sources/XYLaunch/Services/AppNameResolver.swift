import Foundation

enum AppNameResolver {
    static func localizedName(forAppURL appURL: URL) -> String {
        if let localizedFileName = localizedFileName(for: appURL) {
            return localizedFileName
        }

        if let bundle = Bundle(url: appURL) {
            if let localizedBundleName = localizedBundleName(from: bundle) {
                return localizedBundleName
            }
        }

        return appURL.deletingPathExtension().lastPathComponent
    }

    private static func localizedFileName(for appURL: URL) -> String? {
        if let values = try? appURL.resourceValues(forKeys: [.localizedNameKey]),
           let localizedName = values.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localizedName.isEmpty {
            return localizedName
        }

        let displayName = FileManager.default.displayName(atPath: appURL.path)
        if !displayName.isEmpty, displayName != appURL.lastPathComponent {
            return displayName
        }
        return nil
    }

    private static func localizedBundleName(from bundle: Bundle) -> String? {
        if let localizedDisplayName = normalized(bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String) {
            return localizedDisplayName
        }
        if let localizedName = normalized(bundle.localizedInfoDictionary?["CFBundleName"] as? String) {
            return localizedName
        }

        for localization in localizationCandidates(for: bundle) {
            guard
                let path = bundle.path(
                    forResource: "InfoPlist",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: localization
                ),
                let dictionary = NSDictionary(contentsOfFile: path) as? [String: Any]
            else {
                continue
            }

            if let value = normalized(dictionary["CFBundleDisplayName"] as? String) {
                return value
            }
            if let value = normalized(dictionary["CFBundleName"] as? String) {
                return value
            }
        }

        if let displayName = normalized(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) {
            return displayName
        }
        if let name = normalized(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) {
            return name
        }
        return nil
    }

    private static func localizationCandidates(for bundle: Bundle) -> [String] {
        var candidates: [String] = []

        // Always prioritize Chinese localizations first for the launcher's target UX.
        let preferredChinese = ["zh-Hans", "zh-Hant", "zh_CN", "zh_TW", "zh-HK", "zh"]
        candidates.append(contentsOf: preferredChinese)

        let systemPreferred = Locale.preferredLanguages
        candidates.append(contentsOf: systemPreferred)
        candidates.append(contentsOf: bundle.preferredLocalizations)
        candidates.append(contentsOf: bundle.localizations)
        candidates.append("Base")
        candidates.append("en")

        var normalizedCandidates: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if !normalizedCandidates.contains(trimmed) {
                normalizedCandidates.append(trimmed)
            }
            let underscored = trimmed.replacingOccurrences(of: "-", with: "_")
            if !normalizedCandidates.contains(underscored) {
                normalizedCandidates.append(underscored)
            }
        }
        return normalizedCandidates
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        // Skip unresolved placeholders like "$(PRODUCT_NAME)".
        if trimmed.hasPrefix("$("), trimmed.hasSuffix(")") {
            return nil
        }
        return trimmed
    }
}

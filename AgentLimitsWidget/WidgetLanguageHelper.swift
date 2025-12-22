import Foundation

/// Language helper for widget that reads settings from App Group
enum WidgetLanguageHelper {
    private static let languageKey = AppGroupConfig.appLanguageKey
    private static let groupId = AppGroupConfig.groupId

    private static var cachedBundle: Bundle?
    private static var cachedLanguageCode: String?

    /// Returns the localized bundle based on user's language preference
    static var localizedBundle: Bundle {
        let languageCode = effectiveLanguageCode
        if let cached = cachedBundle, cachedLanguageCode == languageCode {
            return cached
        }

        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            cachedBundle = bundle
            cachedLanguageCode = languageCode
            return bundle
        }

        cachedBundle = .main
        cachedLanguageCode = languageCode
        return .main
    }

    /// Returns the effective language code
    private static var effectiveLanguageCode: String {
        let sharedDefaults = UserDefaults(suiteName: groupId)
        let rawValue = sharedDefaults?.string(forKey: languageKey)
        return LanguageCodeResolver.effectiveLanguageCode(for: rawValue)
    }

    /// Returns localized string for the given key
    static func localizedString(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Returns localized string with format arguments
    static func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedString(key)
        return String(format: format, arguments: arguments)
    }
}

// MARK: - Convenience Extensions for Widget

extension String {
    /// Returns localized string using WidgetLanguageHelper
    func widgetLocalized() -> String {
        WidgetLanguageHelper.localizedString(self)
    }

    /// Returns localized string with format arguments
    func widgetLocalized(_ arguments: CVarArg...) -> String {
        let format = WidgetLanguageHelper.localizedString(self)
        return String(format: format, arguments: arguments)
    }
}

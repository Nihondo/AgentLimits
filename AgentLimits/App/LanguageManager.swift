// MARK: - LanguageManager.swift
// Manages language preference shared via App Group for app + widgets.

import Foundation
import SwiftUI
import Combine
import WidgetKit

/// Represents a language option for the app menu.
struct AppLanguageOption: Identifiable, Hashable {
    let rawValue: String

    static var system: AppLanguageOption {
        AppLanguageOption(rawValue: LocalizationConfig.systemLanguageCode)
    }

    var id: String { rawValue }

    var isSystem: Bool {
        rawValue == LocalizationConfig.systemLanguageCode
    }

    var displayName: String {
        if isSystem {
            return String(localized: "menu.language.system")
        }
        return Locale.current.localizedString(forIdentifier: rawValue) ?? rawValue
    }

    /// Returns the effective language code, resolving "system" to actual system language.
    var effectiveLanguageCode: String {
        LanguageCodeResolver.effectiveLanguageCode(for: rawValue)
    }
}

/// Manages app language settings shared via App Group
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private static let languageKey = AppGroupConfig.appLanguageKey
    private let sharedDefaults: UserDefaults?

    @Published private(set) var currentLanguage: AppLanguageOption {
        didSet {
            saveLanguage(currentLanguage)
            updateBundle()
        }
    }

    private(set) var localizedBundle: Bundle = .main

    private init() {
        self.sharedDefaults = AppGroupDefaults.shared
        self.currentLanguage = Self.loadLanguage(from: sharedDefaults)
        updateBundle()
    }

    /// Sets the current language and reloads widget timelines
    func setLanguage(_ language: AppLanguageOption) {
        currentLanguage = language
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Returns the available language options for the menu.
    var availableLanguages: [AppLanguageOption] {
        let supportedLanguageCodes = LanguageCodeResolver.supportedLanguageCodes()
        let options = supportedLanguageCodes.map { AppLanguageOption(rawValue: $0) }
        let sortedOptions = options.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        return [AppLanguageOption.system] + sortedOptions
    }

    /// Returns localized string for the given key
    func localizedString(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Returns localized string with format arguments
    func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedString(key)
        return String(format: format, arguments: arguments)
    }

    private func saveLanguage(_ language: AppLanguageOption) {
        sharedDefaults?.set(language.rawValue, forKey: Self.languageKey)
    }

    private static func loadLanguage(from defaults: UserDefaults?) -> AppLanguageOption {
        guard let rawValue = defaults?.string(forKey: languageKey),
              !rawValue.isEmpty else {
            return .system
        }
        if rawValue == LocalizationConfig.systemLanguageCode {
            return .system
        }
        if let resolvedLanguageCode = LanguageCodeResolver.resolveSupportedLanguageCode(for: rawValue) {
            if resolvedLanguageCode != rawValue {
                defaults?.set(resolvedLanguageCode, forKey: languageKey)
            }
            return AppLanguageOption(rawValue: resolvedLanguageCode)
        }
        defaults?.set(LocalizationConfig.systemLanguageCode, forKey: languageKey)
        return .system
    }

    private func updateBundle() {
        let languageCode = currentLanguage.effectiveLanguageCode
        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            localizedBundle = bundle
        } else {
            localizedBundle = .main
        }
    }
}

// MARK: - Convenience Extensions

extension String {
    /// Returns localized string using LanguageManager
    func localized() -> String {
        LanguageManager.shared.localizedString(self)
    }

    /// Returns localized string with format arguments using LanguageManager
    func localized(_ arguments: CVarArg...) -> String {
        let format = LanguageManager.shared.localizedString(self)
        return String(format: format, arguments: arguments)
    }
}

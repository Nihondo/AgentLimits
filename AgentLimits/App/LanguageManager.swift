// MARK: - LanguageManager.swift
// Manages language preference shared via App Group for app + widgets.

import Foundation
import SwiftUI
import Combine
import WidgetKit

/// Supported app languages
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case japanese = "ja"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "menu.language.system")
        case .japanese:
            return "日本語"
        case .english:
            return "English"
        }
    }

    /// Returns the effective language code, resolving "system" to actual system language
    var effectiveLanguageCode: String {
        switch self {
        case .system:
            return LanguageCodeResolver.systemLanguageCode()
        case .japanese:
            return LocalizationConfig.japaneseLanguageCode
        case .english:
            return LocalizationConfig.englishLanguageCode
        }
    }
}

/// Manages app language settings shared via App Group
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private static let languageKey = AppGroupConfig.appLanguageKey
    private let sharedDefaults: UserDefaults?

    @Published private(set) var currentLanguage: AppLanguage {
        didSet {
            saveLanguage(currentLanguage)
            updateBundle()
        }
    }

    private(set) var localizedBundle: Bundle = .main

    private init() {
        self.sharedDefaults = UserDefaults(suiteName: AppGroupConfig.groupId)
        self.currentLanguage = Self.loadLanguage(from: sharedDefaults)
        updateBundle()
    }

    /// Sets the current language and reloads widget timelines
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        WidgetCenter.shared.reloadAllTimelines()
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

    private func saveLanguage(_ language: AppLanguage) {
        sharedDefaults?.set(language.rawValue, forKey: Self.languageKey)
    }

    private static func loadLanguage(from defaults: UserDefaults?) -> AppLanguage {
        guard let rawValue = defaults?.string(forKey: languageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
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

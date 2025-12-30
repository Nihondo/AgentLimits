// MARK: - UsageWebViewPool.swift
// Manages a pool of WebViewStore instances for each provider.
// Handles data clearing and WebView lifecycle management.

import Combine
import WebKit

// MARK: - WebView Pool

/// Manages WebViewStore instances for each provider.
/// Provides shared access and handles data clearing.
@MainActor
final class UsageWebViewPool: ObservableObject {
    private var webViewStoreByProvider: [UsageProvider: WebViewStore]

    init(providers: [UsageProvider] = UsageProvider.allCases) {
        var stores: [UsageProvider: WebViewStore] = [:]
        for provider in providers {
            stores[provider] = WebViewStore(initialProvider: provider)
        }
        self.webViewStoreByProvider = stores
    }

    /// Returns the WebViewStore for the specified provider, creating if needed
    func getWebViewStore(for provider: UsageProvider) -> WebViewStore {
        if let existingStore = webViewStoreByProvider[provider] {
            return existingStore
        }
        // Lazily create a WebViewStore when requested.
        let newStore = WebViewStore(initialProvider: provider)
        webViewStoreByProvider[provider] = newStore
        return newStore
    }

    /// Clears all website data (cookies, cache) and reloads all WebViews
    func clearWebsiteData() async {
        // Remove cookies/cache and refresh all web views.
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) {
                continuation.resume()
            }
        }
        await clearHttpCookies(in: dataStore)
        reloadAllWebViews()
    }

    private func clearHttpCookies(in dataStore: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                // Explicitly delete cookies after data removal.
                for cookie in cookies {
                    dataStore.httpCookieStore.delete(cookie)
                }
                continuation.resume()
            }
        }
    }

    private func reloadAllWebViews() {
        for store in webViewStoreByProvider.values {
            store.reloadFromOrigin()
        }
    }
}

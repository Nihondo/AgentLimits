// MARK: - WebViewStore.swift
// Manages WKWebView lifecycle and page-ready state detection.
// Handles popup windows for OAuth login flows.

import SwiftUI
import Combine
import WebKit

// MARK: - WebView Store

/// Manages a WKWebView instance for a specific provider.
/// Tracks page-ready state and handles popup windows for OAuth.
@MainActor
final class WebViewStore: ObservableObject {
    let webView: WKWebView
    let usageURL: URL
    @Published var isPageReady = false
    @Published var popupWebView: WKWebView?
    @Published var cookieChangeToken = UUID()
    let targetHost: String
    private var coordinator: WebViewCoordinator?
    private let cookieStore: WKHTTPCookieStore
    private var cookieObserver: CookieObserver?

    init(initialProvider: UsageProvider = .chatgptCodex) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let cookieStore = configuration.websiteDataStore.httpCookieStore
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.usageURL = initialProvider.usageURL
        self.targetHost = initialProvider.usageHost
        self.cookieStore = cookieStore
        let coordinator = WebViewCoordinator(store: self)
        self.coordinator = coordinator
        self.webView.navigationDelegate = coordinator
        self.webView.uiDelegate = coordinator
        let observer = CookieObserver(store: self)
        self.cookieObserver = observer
        cookieStore.add(observer)
        loadIfNeeded()
    }

    deinit {
        if let observer = cookieObserver {
            MainActor.assumeIsolated {
                cookieStore.remove(observer)
            }
        }
    }

    /// Loads the usage URL if not already loaded
    func loadIfNeeded() {
        if webView.url == nil {
            // Initial navigation to provider usage page.
            webView.load(URLRequest(url: usageURL))
        }
    }

    /// Reloads the usage URL, ignoring cache
    func reloadFromOrigin() {
        // Reset readiness and force a fresh load.
        isPageReady = false
        let request = URLRequest(
            url: usageURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        webView.load(request)
    }

    /// Closes any open popup WebView
    func closePopupWebView() {
        // Stop any popup loading and release the reference.
        popupWebView?.stopLoading()
        popupWebView = nil
    }

    private final class CookieObserver: NSObject, WKHTTPCookieStoreObserver {
        private weak var store: WebViewStore?

        init(store: WebViewStore) {
            self.store = store
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                // Bump token to signal cookie changes to observers.
                store?.cookieChangeToken = UUID()
            }
        }
    }
}

// MARK: - SwiftUI Integration

/// NSViewRepresentable for embedding WebViewStore's WKWebView in SwiftUI
struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var store: WebViewStore

    func makeNSView(context: Context) -> WKWebView {
        store.loadIfNeeded()
        return store.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        store.loadIfNeeded()
    }
}

// MARK: - WebView Coordinator

/// Handles WKWebView navigation events and updates page-ready state
final class WebViewCoordinator: NSObject, WKNavigationDelegate {
    private weak var store: WebViewStore?

    init(store: WebViewStore) {
        self.store = store
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        store?.isPageReady = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let store else { return }
        if webView === store.webView {
            store.isPageReady = webView.url?.host == store.targetHost
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        store?.isPageReady = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        store?.isPageReady = false
    }
}

// MARK: - UI Delegate (Popup Handling)

extension WebViewCoordinator: WKUIDelegate {
    /// Creates a popup WebView for OAuth login flows
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let store else { return nil }
        guard navigationAction.targetFrame == nil else { return nil }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        store.popupWebView = popup
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let store else { return }
        if webView === store.popupWebView {
            store.closePopupWebView()
        }
    }
}

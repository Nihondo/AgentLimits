// MARK: - AppUpdateController.swift
// Sparkle アップデータのシングルトンラッパー。
// 起動時/24時間ごとの自動チェックは Info.plist の設定に従い Sparkle が自動実行する。

import Combine
import Sparkle

/// Sparkle の SPUStandardUpdaterController をラップし、SwiftUI へ状態を公開するコントローラ。
@MainActor
final class AppUpdateController: ObservableObject {

    static let shared = AppUpdateController()

    let updater: SPUUpdater

    private let controller: SPUStandardUpdaterController

    /// アップデートチェックが現在実行可能か（Sparkle KVO）
    @Published var canCheckForUpdates: Bool

    /// 最終チェック日時（Sparkle KVO）
    @Published var lastUpdateCheckDate: Date?

    /// 起動時/定期チェックの有効フラグ
    @Published var automaticChecksEnabled: Bool

    private var cancellables = Set<AnyCancellable>()

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        automaticChecksEnabled = updater.automaticallyChecksForUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastUpdateCheckDate)
    }

    /// 手動アップデートチェックを開始する。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 起動時/定期チェックの有効/無効を切り替える。
    func setAutomaticChecksEnabled(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        automaticChecksEnabled = enabled
    }
}

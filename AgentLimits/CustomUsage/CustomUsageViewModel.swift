// MARK: - CustomUsageViewModel.swift
// Coordinates custom service execution, validation, persistence, and refresh state.

import Combine
import Foundation
import WidgetKit

/// カスタム使用量サービスの取得と表示状態を管理します。
@MainActor
final class CustomUsageViewModel: ObservableObject {
    static let widgetKind = CustomUsageWidgetConfig.kind

    @Published private(set) var snapshots: [String: CustomUsageSnapshot] = [:]
    @Published private(set) var runningProviderIDs: Set<String> = []

    let serviceStore: CustomUsageServiceStore
    private let snapshotStore: CustomUsageSnapshotStore
    private let runner: any CustomUsageScriptRunning
    private var autoRefreshCoordinator: AutoRefreshCoordinator?
    private var cancellable: AnyCancellable?

    init(
        serviceStore: CustomUsageServiceStore? = nil,
        snapshotStore: CustomUsageSnapshotStore? = nil,
        runner: (any CustomUsageScriptRunning)? = nil
    ) {
        self.serviceStore = serviceStore ?? .shared
        self.snapshotStore = snapshotStore ?? .shared
        self.runner = runner ?? CustomUsageScriptRunner()
        reloadSnapshots()
        cancellable = self.serviceStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// 登録済みサービスの保存済みスナップショットを読み直します。
    func reloadSnapshots() {
        snapshots = Dictionary(uniqueKeysWithValues: serviceStore.services.compactMap { service in
            snapshotStore.loadSnapshot(providerID: service.providerID).map { (service.providerID, $0) }
        })
    }

    /// 共通Usage間隔による自動更新を開始します。
    func startAutoRefresh() {
        guard autoRefreshCoordinator == nil else { return }
        autoRefreshCoordinator = AutoRefreshCoordinator(
            intervalProvider: { UsageRefreshConfig.refreshIntervalDuration },
            refreshHandler: { [weak self] in
                await self?.refreshEnabledServices()
            }
        )
        autoRefreshCoordinator?.start()
    }

    /// 自動更新を停止します。
    func stopAutoRefresh() {
        autoRefreshCoordinator?.stop()
        autoRefreshCoordinator = nil
    }

    /// 更新間隔変更後に自動更新を再開します。
    func restartAutoRefresh() {
        stopAutoRefresh()
        startAutoRefresh()
    }

    /// 自動更新が有効なサービスを並列で取得します。
    func refreshEnabledServices() async {
        let services = serviceStore.services.filter(\.isAutoRefreshEnabled)
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { await self.refresh(providerID: service.providerID) }
            }
        }
    }

    /// 指定サービスを重複なしで即時更新します。
    func refresh(providerID: String) async {
        guard !runningProviderIDs.contains(providerID),
              let service = serviceStore.service(providerID: providerID) else { return }
        runningProviderIDs.insert(providerID)
        defer { runningProviderIDs.remove(providerID) }

        let attemptedAt = Date()
        var status = serviceStore.runStatuses[providerID] ?? .initial
        status.lastAttemptAt = attemptedAt
        do {
            let output = try await runner.run(scriptPath: service.scriptPath)
            let snapshot = try CustomUsageSnapshotValidator.decodeAndValidate(
                output,
                expectedProviderID: providerID
            )
            try snapshotStore.saveValidatedRawData(output, providerID: providerID)
            snapshots[providerID] = snapshot
            status.lastSuccessAt = Date()
            status.lastError = nil
            serviceStore.updateRunStatus(status, providerID: providerID)
            WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
            let presentation = UsagePresentationSnapshot(custom: snapshot, displayName: service.displayName)
            ThresholdNotificationManager.shared.registerSnapshot(presentation)
            await ThresholdNotificationManager.shared.checkThresholdsIfNeeded(for: presentation)
        } catch {
            status.lastError = error.localizedDescription
            serviceStore.updateRunStatus(status, providerID: providerID)
        }
    }

    /// サービスと関連データを削除します。
    func deleteService(providerID: String) {
        serviceStore.deleteService(providerID: providerID)
        snapshots.removeValue(forKey: providerID)
        try? snapshotStore.deleteSnapshot(providerID: providerID)
        ThresholdNotificationManager.shared.deleteSettings(for: .custom(providerID))
        ProviderOrderStore.removeService(.custom(providerID))
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }

    /// メニュー・通知で使用するカスタム共通表示スナップショットを返します。
    var presentationSnapshots: [UsageServiceKey: UsagePresentationSnapshot] {
        Dictionary(uniqueKeysWithValues: serviceStore.services.compactMap { service in
            guard let snapshot = snapshots[service.providerID] else { return nil }
            let presentation = UsagePresentationSnapshot(custom: snapshot, displayName: service.displayName)
            return (presentation.serviceKey, presentation)
        })
    }
}

// MARK: - CustomUsageServiceStore.swift
// Persists custom service execution settings and mirrors widget-visible descriptors.

import Combine
import Foundation

/// ユーザーが登録したカスタム使用量サービスの設定です。
struct CustomUsageService: Codable, Equatable, Identifiable {
    let providerID: String
    var displayName: String
    var scriptPath: String
    var websiteURLString: String
    var isAutoRefreshEnabled: Bool
    var isMenuBarEnabled: Bool
    var isDashboardEnabled: Bool

    var id: String { providerID }

    var websiteURL: URL? {
        guard let url = URL(string: websiteURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

/// カスタムサービスの実行結果を保持する状態です。
struct CustomUsageRunStatus: Codable, Equatable {
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?

    static let initial = CustomUsageRunStatus()
}

/// カスタムサービス設定と実行状態をUserDefaultsへ保存します。
@MainActor
final class CustomUsageServiceStore: ObservableObject {
    static let shared = CustomUsageServiceStore()

    @Published private(set) var services: [CustomUsageService]
    @Published private(set) var runStatuses: [String: CustomUsageRunStatus]

    private let userDefaults: UserDefaults
    private let widgetDefaults: UserDefaults?
    private static let servicesKey = "custom_usage_services"
    private static let statusesKey = "custom_usage_run_statuses"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        widgetDefaults: UserDefaults? = nil
    ) {
        self.userDefaults = userDefaults
        self.widgetDefaults = widgetDefaults ?? AppGroupDefaults.shared
        DateCodec.configureEncoder(encoder)
        DateCodec.configureDecoder(decoder)
        services = Self.decode([CustomUsageService].self, key: Self.servicesKey, defaults: userDefaults) ?? []
        runStatuses = Self.decode(
            [String: CustomUsageRunStatus].self,
            key: Self.statusesKey,
            defaults: userDefaults,
            configureDates: true
        ) ?? [:]
        syncWidgetDescriptors()
    }

    /// Provider IDに対応するサービス設定を返します。
    func service(providerID: String) -> CustomUsageService? {
        services.first { $0.providerID == providerID }
    }

    /// 新しいサービスを末尾へ追加します。
    func addService(_ service: CustomUsageService) throws {
        guard CustomUsageSnapshotValidator.isProviderIDValid(service.providerID) else {
            throw CustomUsageSnapshotValidationError.invalidProviderID
        }
        guard self.service(providerID: service.providerID) == nil else {
            throw CustomUsageServiceStoreError.duplicateProviderID
        }
        services.append(service)
        saveServices()
    }

    /// Provider IDを維持したままサービス設定を更新します。
    func updateService(_ service: CustomUsageService) {
        guard let index = services.firstIndex(where: { $0.providerID == service.providerID }) else { return }
        services[index] = service
        saveServices()
    }

    /// サービス設定と実行状態を削除します。
    func deleteService(providerID: String) {
        services.removeAll { $0.providerID == providerID }
        runStatuses.removeValue(forKey: providerID)
        saveServices()
        saveStatuses()
    }

    /// 実行結果を更新して永続化します。
    func updateRunStatus(_ status: CustomUsageRunStatus, providerID: String) {
        runStatuses[providerID] = status
        saveStatuses()
    }

    private func saveServices() {
        if let data = try? encoder.encode(services) {
            userDefaults.set(data, forKey: Self.servicesKey)
        }
        syncWidgetDescriptors()
    }

    private func saveStatuses() {
        if let data = try? encoder.encode(runStatuses) {
            userDefaults.set(data, forKey: Self.statusesKey)
        }
    }

    /// 共通表示順に合わせてWidget編集候補の最小索引を同期します。
    func syncWidgetDescriptors() {
        let storedOrder = UserDefaults.standard.stringArray(
            forKey: UserDefaultsKeys.serviceDisplayOrder
        ) ?? []
        let orderIndexes = Dictionary(uniqueKeysWithValues: storedOrder.enumerated().map {
            ($0.element, $0.offset)
        })
        let sortedServices = services.enumerated().sorted { lhs, rhs in
            let lhsKey = UsageServiceKey.custom(lhs.element.providerID).rawValue
            let rhsKey = UsageServiceKey.custom(rhs.element.providerID).rawValue
            return (orderIndexes[lhsKey] ?? (storedOrder.count + lhs.offset))
                < (orderIndexes[rhsKey] ?? (storedOrder.count + rhs.offset))
        }.map(\.element)
        let descriptors = sortedServices.map {
            CustomUsageServiceDescriptor(providerID: $0.providerID, displayName: $0.displayName)
        }
        CustomUsageServiceDescriptorStore.saveDescriptors(descriptors, defaults: widgetDefaults)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults,
        configureDates: Bool = false
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        if configureDates {
            DateCodec.configureDecoder(decoder)
        }
        return try? decoder.decode(type, from: data)
    }
}

enum CustomUsageServiceStoreError: Error, LocalizedError {
    case duplicateProviderID

    var errorDescription: String? {
        NSLocalizedString("customUsage.error.duplicateProviderID", comment: "")
    }
}

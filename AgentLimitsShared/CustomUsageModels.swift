// MARK: - CustomUsageModels.swift
// Shared models and storage used by the app and configurable custom widget.

import Foundation

enum CustomUsageWidgetConfig {
    static let kind = "CustomUsageWidget"
}

// MARK: - Service Identity

/// 組み込み・カスタム使用量サービスを共通に識別する安定キーです。
struct UsageServiceKey: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    var id: String { rawValue }

    static func builtIn(_ provider: UsageProvider) -> UsageServiceKey {
        UsageServiceKey(rawValue: "builtIn:\(provider.rawValue)")
    }

    static func custom(_ providerID: String) -> UsageServiceKey {
        UsageServiceKey(rawValue: "custom:\(providerID)")
    }

    var customProviderID: String? {
        guard rawValue.hasPrefix("custom:") else { return nil }
        return String(rawValue.dropFirst("custom:".count))
    }

    var builtInProvider: UsageProvider? {
        guard rawValue.hasPrefix("builtIn:") else { return nil }
        return UsageProvider(rawValue: String(rawValue.dropFirst("builtIn:".count)))
    }
}

/// 表示・通知で使用する意味ベースの利用枠種別です。
enum SemanticUsageWindowKind: String, Codable, CaseIterable, Hashable, Sendable {
    case fiveHours = "5h"
    case oneWeek = "1w"
    case oneMonth = "1month"

    var displayOrder: Int {
        switch self {
        case .fiveHours: return 0
        case .oneWeek: return 1
        case .oneMonth: return 2
        }
    }

    var compactLabel: String { rawValue }
}

/// 共通表示層で扱う単一の利用枠です。
struct SemanticUsageWindow: Hashable, Sendable {
    let kind: SemanticUsageWindowKind
    let usedPercent: Double
    let resetAt: Date
    let durationSeconds: TimeInterval
    let usedCount: Int?
    let limitCount: Int?

    var usageWindow: UsageWindow {
        UsageWindow(
            kind: kind == .oneWeek ? .secondary : .primary,
            usedPercent: usedPercent,
            resetAt: resetAt,
            limitWindowSeconds: durationSeconds,
            usedCount: usedCount,
            limitCount: limitCount
        )
    }
}

/// 組み込み・カスタムスナップショットの共通表示形式です。
struct UsagePresentationSnapshot: Identifiable, Sendable {
    let serviceKey: UsageServiceKey
    let displayName: String
    let fetchedAt: Date
    let windows: [SemanticUsageWindow]

    var id: UsageServiceKey { serviceKey }
}

extension UsagePresentationSnapshot {
    /// 既存の組み込みスナップショットを意味ベースの共通表示形式へ変換します。
    init(builtIn snapshot: UsageSnapshot) {
        var resolvedWindows: [SemanticUsageWindow] = []
        if let primary = snapshot.primaryWindow, let resetAt = primary.resetAt {
            let kind: SemanticUsageWindowKind = snapshot.isSingleMonthlyWindow ? .oneMonth : .fiveHours
            resolvedWindows.append(SemanticUsageWindow(
                kind: kind,
                usedPercent: primary.usedPercent,
                resetAt: resetAt,
                durationSeconds: primary.limitWindowSeconds,
                usedCount: primary.usedCount,
                limitCount: primary.limitCount
            ))
        }
        if let secondary = snapshot.secondaryWindow, let resetAt = secondary.resetAt {
            resolvedWindows.append(SemanticUsageWindow(
                kind: .oneWeek,
                usedPercent: secondary.usedPercent,
                resetAt: resetAt,
                durationSeconds: secondary.limitWindowSeconds,
                usedCount: secondary.usedCount,
                limitCount: secondary.limitCount
            ))
        }
        self.init(
            serviceKey: .builtIn(snapshot.provider),
            displayName: snapshot.provider.displayName,
            fetchedAt: snapshot.fetchedAt,
            windows: resolvedWindows.sorted { $0.kind.displayOrder < $1.kind.displayOrder }
        )
    }

    /// カスタムスナップショットを共通表示形式へ変換します。
    init(custom snapshot: CustomUsageSnapshot, displayName: String) {
        self.init(
            serviceKey: .custom(snapshot.provider),
            displayName: displayName,
            fetchedAt: snapshot.fetchedAt,
            windows: snapshot.windows.map(\.semanticWindow).sorted {
                $0.kind.displayOrder < $1.kind.displayOrder
            }
        )
    }
}

// MARK: - Public Custom Snapshot Contract

/// 外部スクリプトがstdoutへ出力するカスタム使用量スナップショットです。
struct CustomUsageSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let provider: String
    let fetchedAt: Date
    let windows: [CustomUsageWindow]
}

/// カスタムスナップショット内の単一利用枠です。
struct CustomUsageWindow: Codable, Equatable, Sendable {
    let kind: SemanticUsageWindowKind
    let usedPercent: Double
    let resetAt: Date
    let durationSeconds: TimeInterval
    let usedCount: Int?
    let limitCount: Int?

    var semanticWindow: SemanticUsageWindow {
        SemanticUsageWindow(
            kind: kind,
            usedPercent: usedPercent,
            resetAt: resetAt,
            durationSeconds: durationSeconds,
            usedCount: usedCount,
            limitCount: limitCount
        )
    }
}

/// カスタムスナップショット契約の検証エラーです。
enum CustomUsageSnapshotValidationError: Error, LocalizedError, Equatable {
    case invalidProviderID
    case unsupportedSchemaVersion(Int)
    case providerMismatch(expected: String, actual: String)
    case invalidWindowCount
    case duplicateWindowKind(SemanticUsageWindowKind)
    case invalidUsedPercent(SemanticUsageWindowKind)
    case invalidDuration(SemanticUsageWindowKind)
    case invalidCounts(SemanticUsageWindowKind)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidProviderID:
            return NSLocalizedString("customUsage.validation.invalidProviderID", comment: "")
        case .unsupportedSchemaVersion(let version):
            return String(
                format: NSLocalizedString("customUsage.validation.unsupportedSchemaVersion", comment: ""),
                version
            )
        case .providerMismatch(let expected, let actual):
            return String(
                format: NSLocalizedString("customUsage.validation.providerMismatch", comment: ""),
                actual,
                expected
            )
        case .invalidWindowCount:
            return NSLocalizedString("customUsage.validation.invalidWindowCount", comment: "")
        case .duplicateWindowKind(let kind):
            return String(
                format: NSLocalizedString("customUsage.validation.duplicateWindowKind", comment: ""),
                kind.rawValue
            )
        case .invalidUsedPercent(let kind):
            return String(
                format: NSLocalizedString("customUsage.validation.invalidUsedPercent", comment: ""),
                kind.rawValue
            )
        case .invalidDuration(let kind):
            return String(
                format: NSLocalizedString("customUsage.validation.invalidDuration", comment: ""),
                kind.rawValue
            )
        case .invalidCounts(let kind):
            return String(
                format: NSLocalizedString("customUsage.validation.invalidCounts", comment: ""),
                kind.rawValue
            )
        case .invalidJSON(let message):
            return String(
                format: NSLocalizedString("customUsage.validation.invalidJSON", comment: ""),
                message
            )
        }
    }
}

/// Provider IDとカスタムスナップショットJSONを検証します。
enum CustomUsageSnapshotValidator {
    static let supportedSchemaVersion = 1

    /// Provider IDがファイル名として安全なslug形式かを返します。
    static func isProviderIDValid(_ providerID: String) -> Bool {
        providerID.range(
            of: "^[a-z0-9][a-z0-9_-]{0,62}$",
            options: .regularExpression
        ) != nil
    }

    /// stdoutのJSONをデコードし、設定済みProvider IDとの整合性を検証します。
    static func decodeAndValidate(_ data: Data, expectedProviderID: String) throws -> CustomUsageSnapshot {
        guard isProviderIDValid(expectedProviderID) else {
            throw CustomUsageSnapshotValidationError.invalidProviderID
        }
        let decoder = JSONDecoder()
        DateCodec.configureDecoder(decoder)
        let snapshot: CustomUsageSnapshot
        do {
            snapshot = try decoder.decode(CustomUsageSnapshot.self, from: data)
        } catch {
            throw CustomUsageSnapshotValidationError.invalidJSON(error.localizedDescription)
        }
        try validate(snapshot, expectedProviderID: expectedProviderID)
        return snapshot
    }

    /// デコード済みスナップショットの既知フィールドを厳格に検証します。
    static func validate(_ snapshot: CustomUsageSnapshot, expectedProviderID: String) throws {
        guard snapshot.schemaVersion == supportedSchemaVersion else {
            throw CustomUsageSnapshotValidationError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        guard snapshot.provider == expectedProviderID else {
            throw CustomUsageSnapshotValidationError.providerMismatch(
                expected: expectedProviderID,
                actual: snapshot.provider
            )
        }
        guard (1...2).contains(snapshot.windows.count) else {
            throw CustomUsageSnapshotValidationError.invalidWindowCount
        }
        var seenKinds: Set<SemanticUsageWindowKind> = []
        for window in snapshot.windows {
            guard seenKinds.insert(window.kind).inserted else {
                throw CustomUsageSnapshotValidationError.duplicateWindowKind(window.kind)
            }
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else {
                throw CustomUsageSnapshotValidationError.invalidUsedPercent(window.kind)
            }
            guard window.durationSeconds.isFinite, window.durationSeconds > 0 else {
                throw CustomUsageSnapshotValidationError.invalidDuration(window.kind)
            }
            let hasUsedCount = window.usedCount != nil
            let hasLimitCount = window.limitCount != nil
            guard hasUsedCount == hasLimitCount else {
                throw CustomUsageSnapshotValidationError.invalidCounts(window.kind)
            }
            if let usedCount = window.usedCount, let limitCount = window.limitCount {
                guard usedCount >= 0, limitCount > 0 else {
                    throw CustomUsageSnapshotValidationError.invalidCounts(window.kind)
                }
            }
        }
    }
}

// MARK: - Widget-visible Registry

/// Widget編集画面へ公開する最小限のカスタムサービス情報です。
struct CustomUsageServiceDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    let providerID: String
    let displayName: String

    var id: String { providerID }
}

/// App Groupを介してカスタムWidget候補を共有します。
enum CustomUsageServiceDescriptorStore {
    static let defaultsKey = "custom_usage_widget_services"

    static func loadDescriptors(defaults: UserDefaults? = AppGroupDefaults.shared) -> [CustomUsageServiceDescriptor] {
        guard let data = defaults?.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([CustomUsageServiceDescriptor].self, from: data)) ?? []
    }

    static func saveDescriptors(
        _ descriptors: [CustomUsageServiceDescriptor],
        defaults: UserDefaults? = AppGroupDefaults.shared
    ) {
        guard let data = try? JSONEncoder().encode(descriptors) else { return }
        defaults?.set(data, forKey: defaultsKey)
    }
}

// MARK: - Raw Snapshot Storage

/// カスタムスナップショットのraw JSONをApp Groupへ原子的に保存します。
struct CustomUsageSnapshotStore {
    static let shared = CustomUsageSnapshotStore()

    private let fileManager: FileManager
    private let customContainerURL: URL?

    init(fileManager: FileManager = .default, customContainerURL: URL? = nil) {
        self.fileManager = fileManager
        self.customContainerURL = customContainerURL
    }

    func loadSnapshot(providerID: String) -> CustomUsageSnapshot? {
        guard let data = try? loadRawData(providerID: providerID) else { return nil }
        return try? CustomUsageSnapshotValidator.decodeAndValidate(data, expectedProviderID: providerID)
    }

    func loadRawData(providerID: String) throws -> Data {
        let url = try snapshotURL(providerID: providerID, createDirectory: false)
        return try Data(contentsOf: url)
    }

    /// 検証済みstdoutを内容変更せず原子的に保存します。
    func saveValidatedRawData(_ data: Data, providerID: String) throws {
        _ = try CustomUsageSnapshotValidator.decodeAndValidate(data, expectedProviderID: providerID)
        let url = try snapshotURL(providerID: providerID, createDirectory: true)
        try data.write(to: url, options: .atomic)
    }

    func deleteSnapshot(providerID: String) throws {
        let url = try snapshotURL(providerID: providerID, createDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func snapshotURL(providerID: String, createDirectory: Bool) throws -> URL {
        guard CustomUsageSnapshotValidator.isProviderIDValid(providerID) else {
            throw CustomUsageSnapshotValidationError.invalidProviderID
        }
        guard let containerURL = customContainerURL ?? fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId
        ) else {
            throw UsageSnapshotStoreError.appGroupUnavailable
        }
        let directoryURL = containerURL.appendingPathComponent(
            AppGroupConfig.snapshotDirectory,
            isDirectory: true
        )
        if createDirectory {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent("usage_snapshot_custom_\(providerID).json")
    }
}

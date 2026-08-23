import XCTest
@testable import AgentLimits

final class ThresholdNotificationStoreMigrationTests: XCTestCase {
    func testLegacySettingsMigrateToSemanticWindowsAndPreserveResetDates() throws {
        let suiteName = "ThresholdNotificationStoreMigrationTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let resetAt = Date(timeIntervalSince1970: 1_777_777_777)
        var codex = ProviderThresholdSettings.defaultSettings(for: .chatgptCodex)
        codex.primaryWindow.warning.thresholdPercent = 73
        codex.secondaryWindow.danger.lastNotifiedResetAt = resetAt
        var copilot = ProviderThresholdSettings.defaultSettings(for: .githubCopilot)
        copilot.primaryWindow.danger.thresholdPercent = 94

        let store = ThresholdNotificationStore(userDefaults: defaults)
        store.saveSettings([
            .chatgptCodex: codex,
            .githubCopilot: copilot,
        ])

        let migrated = store.loadServiceSettings()
        let codexV2 = try XCTUnwrap(migrated[.builtIn(.chatgptCodex)])
        XCTAssertEqual(codexV2.settings(for: .fiveHours).warning.thresholdPercent, 73)
        XCTAssertEqual(codexV2.settings(for: .oneWeek).danger.lastNotifiedResetAt, resetAt)
        XCTAssertNil(codexV2.windows[.oneMonth])

        let copilotV2 = try XCTUnwrap(migrated[.builtIn(.githubCopilot)])
        XCTAssertEqual(copilotV2.settings(for: .oneMonth).danger.thresholdPercent, 94)
        XCTAssertNil(copilotV2.windows[.fiveHours])
        XCTAssertNil(copilotV2.windows[.oneWeek])
    }

    func testCustomResetDatePersistsForDuplicatePrevention() throws {
        let suiteName = "ThresholdNotificationStoreDuplicateTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ThresholdNotificationStore(userDefaults: defaults)
        let resetAt = Date(timeIntervalSince1970: 1_888_888_888)

        store.updateLastNotifiedResetAt(
            for: .custom("cursor"),
            windowKind: .fiveHours,
            level: .warning,
            resetAt: resetAt
        )

        let settings = store.loadServiceSettings()[.custom("cursor")]
        XCTAssertEqual(settings?.settings(for: .fiveHours).warning.lastNotifiedResetAt, resetAt)
    }
}

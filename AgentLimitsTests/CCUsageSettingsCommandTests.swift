// MARK: - CCUsageSettingsCommandTests.swift
// Verifies CCUsageSettings command template resolution: default generation,
// user customization, placeholder expansion, and backward-compatible decoding
// (including folding the removed `additionalArgs` field into a template).

import XCTest
@testable import AgentLimits

final class CCUsageSettingsCommandTests: XCTestCase {
    private let startDate = "20260901"

    // MARK: - Default template

    func testDefaultTemplateStartsWithBaseCommandAndEndsWithSinceAndJSONFlag() {
        let settings = CCUsageSettings(provider: .codex, isEnabled: true)
        let command = settings.makeCLICommand(startDate: startDate)

        XCTAssertEqual(command, "\(TokenUsageProvider.codex.cliCommandBase) --since \(startDate) -j")
        XCTAssertFalse(settings.isCommandCustomized)
    }

    // MARK: - Custom template

    func testCustomTemplateReplacesBaseCommandAndExpandsSincePlaceholder() {
        var settings = CCUsageSettings(provider: .codex, isEnabled: true)
        settings.commandTemplate = "merged-ccusage codex daily --since {{since}} -j"

        let command = settings.makeCLICommand(startDate: startDate)

        XCTAssertFalse(command.contains(TokenUsageProvider.codex.cliCommandBase))
        XCTAssertEqual(command, "merged-ccusage codex daily --since \(startDate) -j")
        XCTAssertTrue(settings.isCommandCustomized)
    }

    func testCustomTemplateWithoutSincePlaceholderIsUsedVerbatim() {
        var settings = CCUsageSettings(provider: .codex, isEnabled: true)
        settings.commandTemplate = "merged-ccusage --all -j"

        let command = settings.makeCLICommand(startDate: startDate)

        XCTAssertEqual(command, "merged-ccusage --all -j")
    }

    func testWhitespaceOnlyTemplateFallsBackToDefault() {
        var settings = CCUsageSettings(provider: .codex, isEnabled: true)
        settings.commandTemplate = "   "

        XCTAssertFalse(settings.isCommandCustomized)
        XCTAssertEqual(settings.resolvedCommandTemplate, settings.defaultCommandTemplate)
    }

    func testResetToDefaultClearsCommandTemplate() {
        var settings = CCUsageSettings(provider: .codex, isEnabled: true)
        settings.commandTemplate = "merged-ccusage codex daily --since {{since}} -j"
        XCTAssertTrue(settings.isCommandCustomized)

        settings.commandTemplate = ""

        XCTAssertFalse(settings.isCommandCustomized)
        XCTAssertEqual(settings.resolvedCommandTemplate, settings.defaultCommandTemplate)
    }

    // MARK: - Backward-compatible decoding

    func testDecodingJSONWithoutCommandTemplateOrLegacyArgsDefaultsToEmptyString() throws {
        let json = """
        {
          "provider": "codex",
          "isEnabled": true
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let settings = try JSONDecoder().decode(CCUsageSettings.self, from: data)

        XCTAssertEqual(settings.commandTemplate, "")
        XCTAssertFalse(settings.isCommandCustomized)
        XCTAssertEqual(
            settings.makeCLICommand(startDate: startDate),
            "\(TokenUsageProvider.codex.cliCommandBase) --since \(startDate) -j"
        )
    }

    /// Settings saved before `additionalArgs` was removed must keep producing the
    /// same executed command after being folded into an explicit `commandTemplate`.
    func testDecodingLegacyJSONWithAdditionalArgsFoldsIntoCommandTemplate() throws {
        let json = """
        {
          "provider": "codex",
          "isEnabled": true,
          "additionalArgs": "--timezone Asia/Tokyo"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let settings = try JSONDecoder().decode(CCUsageSettings.self, from: data)

        XCTAssertTrue(settings.isCommandCustomized)
        XCTAssertEqual(
            settings.makeCLICommand(startDate: startDate),
            "\(TokenUsageProvider.codex.cliCommandBase) --timezone Asia/Tokyo --since \(startDate) -j"
        )
    }

    func testDecodingLegacyJSONWithEmptyAdditionalArgsDoesNotCustomizeCommand() throws {
        let json = """
        {
          "provider": "claude",
          "isEnabled": true,
          "additionalArgs": ""
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let settings = try JSONDecoder().decode(CCUsageSettings.self, from: data)

        XCTAssertFalse(settings.isCommandCustomized)
        XCTAssertEqual(
            settings.makeCLICommand(startDate: startDate),
            "\(TokenUsageProvider.claude.cliCommandBase) --since \(startDate) -j"
        )
    }

    /// A saved `commandTemplate` takes precedence over legacy `additionalArgs`
    /// even if both keys are present in the same JSON payload.
    func testDecodingJSONWithBothCommandTemplateAndLegacyArgsPrefersCommandTemplate() throws {
        let json = """
        {
          "provider": "codex",
          "isEnabled": true,
          "additionalArgs": "--timezone Asia/Tokyo",
          "commandTemplate": "merged-ccusage codex daily --since {{since}} -j"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let settings = try JSONDecoder().decode(CCUsageSettings.self, from: data)

        XCTAssertEqual(
            settings.makeCLICommand(startDate: startDate),
            "merged-ccusage codex daily --since \(startDate) -j"
        )
    }
}

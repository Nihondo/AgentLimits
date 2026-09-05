import XCTest
@testable import AgentLimits

final class CustomUsageModelsTests: XCTestCase {
    private let validJSON = """
    {
      "schemaVersion": 1,
      "provider": "cursor",
      "fetchedAt": "2026-08-23T12:34:56Z",
      "unknownField": "preserved",
      "windows": [
        {
          "kind": "5h",
          "usedPercent": 42.5,
          "resetAt": "2026-08-23T15:00:00Z",
          "durationSeconds": 18000,
          "usedCount": 425,
          "limitCount": 1000
        },
        {
          "kind": "1w",
          "usedPercent": 68,
          "resetAt": "2026-08-30T00:00:00Z",
          "durationSeconds": 604800
        }
      ]
    }

    """

    func testValidSnapshotDecodesAndSortsForPresentation() throws {
        let data = try XCTUnwrap(validJSON.data(using: .utf8))
        let snapshot = try CustomUsageSnapshotValidator.decodeAndValidate(
            data,
            expectedProviderID: "cursor"
        )
        XCTAssertEqual(snapshot.windows.map(\.kind), [.fiveHours, .oneWeek])
        let presentation = UsagePresentationSnapshot(custom: snapshot, displayName: "Cursor")
        XCTAssertEqual(presentation.serviceKey, .custom("cursor"))
        XCTAssertEqual(presentation.windows.map(\.kind), [.fiveHours, .oneWeek])
        XCTAssertEqual(presentation.windows.map(\.displayLabel), ["5h", "1w"])
        XCTAssertTrue(presentation.windows.allSatisfy(\.canShowPacemaker))
    }

    func testCustomLabelAndNoExpiryDisablePacemakerWithoutBreakingValidation() throws {
        let json = """
        {
          "schemaVersion": 1,
          "provider": "cursor",
          "fetchedAt": "2026-08-23T12:34:56Z",
          "windows": [
            {
              "kind": "5h",
              "label": "  Credits  ",
              "usedPercent": 42.5,
              "isPacemakerEnabled": false
            }
          ]
        }
        """
        let snapshot = try CustomUsageSnapshotValidator.decodeAndValidate(
            try XCTUnwrap(json.data(using: .utf8)),
            expectedProviderID: "cursor"
        )
        let window = try XCTUnwrap(snapshot.windows.first?.semanticWindow)
        XCTAssertEqual(window.displayLabel, "Credits")
        XCTAssertTrue(window.hasCustomLabel)
        XCTAssertFalse(window.canShowPacemaker)
        XCTAssertNil(window.resetAt)
        XCTAssertNil(window.durationSeconds)
    }

    func testPartialExpiryDataAndInvalidProvidedDurationAreHandledCorrectly() throws {
        let partialExpiry = validJSON.replacingOccurrences(
            of: "\"durationSeconds\": 18000,",
            with: ""
        )
        XCTAssertNoThrow(
            try CustomUsageSnapshotValidator.decodeAndValidate(
                try XCTUnwrap(partialExpiry.data(using: .utf8)),
                expectedProviderID: "cursor"
            )
        )

        let invalidDuration = validJSON.replacingOccurrences(of: "18000", with: "0")
        XCTAssertThrowsError(
            try CustomUsageSnapshotValidator.decodeAndValidate(
                try XCTUnwrap(invalidDuration.data(using: .utf8)),
                expectedProviderID: "cursor"
            )
        )
    }

    func testProviderMismatchIsRejected() throws {
        let data = try XCTUnwrap(validJSON.data(using: .utf8))
        XCTAssertThrowsError(
            try CustomUsageSnapshotValidator.decodeAndValidate(data, expectedProviderID: "other")
        ) { error in
            XCTAssertEqual(
                error as? CustomUsageSnapshotValidationError,
                .providerMismatch(expected: "other", actual: "cursor")
            )
        }
    }

    func testDuplicateAndThreeWindowsAreRejected() throws {
        let duplicate = validJSON.replacingOccurrences(
            of: "\"kind\": \"1w\"",
            with: "\"kind\": \"5h\""
        )
        XCTAssertThrowsError(
            try CustomUsageSnapshotValidator.decodeAndValidate(
                try XCTUnwrap(duplicate.data(using: .utf8)),
                expectedProviderID: "cursor"
            )
        )

        let threeWindows = validJSON.replacingOccurrences(
            of: "\n  ]\n}",
            with: """
            ,
                {
                  "kind": "1month",
                  "usedPercent": 10,
                  "resetAt": "2026-09-01T00:00:00Z",
                  "durationSeconds": 2592000
                }
              ]
            }
            """
        )
        XCTAssertThrowsError(
            try CustomUsageSnapshotValidator.decodeAndValidate(
                try XCTUnwrap(threeWindows.data(using: .utf8)),
                expectedProviderID: "cursor"
            )
        )
    }

    func testInvalidKnownFieldsAreRejected() throws {
        let invalidPercent = validJSON.replacingOccurrences(of: "42.5", with: "101")
        XCTAssertThrowsError(
            try CustomUsageSnapshotValidator.decodeAndValidate(
                try XCTUnwrap(invalidPercent.data(using: .utf8)),
                expectedProviderID: "cursor"
            )
        )

        let missingCountPair = validJSON.replacingOccurrences(
            of: "\"limitCount\": 1000",
            with: "\"unknownCount\": 1000"
        )
        XCTAssertThrowsError(
            try CustomUsageSnapshotValidator.decodeAndValidate(
                try XCTUnwrap(missingCountPair.data(using: .utf8)),
                expectedProviderID: "cursor"
            )
        )
    }

    func testRawStorePreservesBytesAndInvalidDataDoesNotOverwrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomUsageStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CustomUsageSnapshotStore(customContainerURL: root)
        let validData = try XCTUnwrap(validJSON.data(using: .utf8))

        try store.saveValidatedRawData(validData, providerID: "cursor")
        XCTAssertEqual(try store.loadRawData(providerID: "cursor"), validData)

        XCTAssertThrowsError(
            try store.saveValidatedRawData(Data("{}".utf8), providerID: "cursor")
        )
        XCTAssertEqual(try store.loadRawData(providerID: "cursor"), validData)
    }

    func testProviderIDValidation() {
        XCTAssertTrue(CustomUsageSnapshotValidator.isProviderIDValid("cursor_2-beta"))
        XCTAssertFalse(CustomUsageSnapshotValidator.isProviderIDValid("Cursor"))
        XCTAssertFalse(CustomUsageSnapshotValidator.isProviderIDValid("../cursor"))
        XCTAssertFalse(CustomUsageSnapshotValidator.isProviderIDValid(String(repeating: "a", count: 64)))
    }
}

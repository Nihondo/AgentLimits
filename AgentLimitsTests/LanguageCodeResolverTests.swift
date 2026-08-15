import XCTest
@testable import AgentLimits

final class LanguageCodeResolverTests: XCTestCase {
    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        let languageCode = LanguageCodeResolver.systemLanguageCode(
            preferredLanguages: ["cs-CZ"],
            supportedLanguageCodes: ["de", "en", "ja"]
        )

        XCTAssertEqual(languageCode, "en")
    }

    func testSupportedSystemLanguageRemainsSelected() {
        let languageCode = LanguageCodeResolver.systemLanguageCode(
            preferredLanguages: ["de-CZ"],
            supportedLanguageCodes: ["de", "en", "ja"]
        )

        XCTAssertEqual(languageCode, "de")
    }

    func testEnglishRegionalLocalizationCanBeTheFallback() {
        let languageCode = LanguageCodeResolver.systemLanguageCode(
            preferredLanguages: ["cs-CZ"],
            supportedLanguageCodes: ["de", "en-GB", "ja"]
        )

        XCTAssertEqual(languageCode, "en-GB")
    }
}

import XCTest
@testable import AgentLimits

final class CustomUsageViewModelTests: XCTestCase {
    func testConcurrentRefreshForSameProviderRunsOnlyOnce() async throws {
        let settingsSuiteName = "CustomUsageViewModelTests.settings"
        let widgetSuiteName = "CustomUsageViewModelTests.widget"
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
        UserDefaults(suiteName: widgetSuiteName)?.removePersistentDomain(forName: widgetSuiteName)
        defer {
            UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
            UserDefaults(suiteName: widgetSuiteName)?.removePersistentDomain(forName: widgetSuiteName)
        }

        let runner = DelayedFailingCustomUsageRunner()
        let viewModel = try await MainActor.run {
            let settingsSuite = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))
            let widgetSuite = try XCTUnwrap(UserDefaults(suiteName: widgetSuiteName))
            let serviceStore = CustomUsageServiceStore(
                userDefaults: settingsSuite,
                widgetDefaults: widgetSuite
            )
            try serviceStore.addService(CustomUsageService(
                providerID: "cursor",
                displayName: "Cursor",
                scriptPath: "/tmp/custom-usage-test",
                websiteURLString: "",
                isAutoRefreshEnabled: true,
                isMenuBarEnabled: true,
                isDashboardEnabled: true
            ))
            return CustomUsageViewModel(
                serviceStore: serviceStore,
                snapshotStore: CustomUsageSnapshotStore(
                    customContainerURL: FileManager.default.temporaryDirectory
                ),
                runner: runner
            )
        }

        let first = Task { @MainActor in await viewModel.refresh(providerID: "cursor") }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task { @MainActor in await viewModel.refresh(providerID: "cursor") }
        await first.value
        await second.value

        let runCount = await runner.runCount
        XCTAssertEqual(runCount, 1)
    }
}

private actor DelayedFailingCustomUsageRunner: CustomUsageScriptRunning {
    private(set) var runCount = 0

    func run(scriptPath: String) async throws -> Data {
        runCount += 1
        try await Task.sleep(for: .milliseconds(150))
        throw CustomUsageScriptRunnerError.executionFailed(exitCode: 1, stderr: "expected")
    }
}

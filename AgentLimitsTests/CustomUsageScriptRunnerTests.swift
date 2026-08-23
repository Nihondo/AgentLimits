import Darwin
import XCTest
@testable import AgentLimits

final class CustomUsageScriptRunnerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomUsageRunnerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSuccessfulScriptReturnsExactStdout() async throws {
        let script = try makeScript(body: "printf '  {\\\"ok\\\":true}\\n'")
        let output = try await CustomUsageScriptRunner().run(scriptPath: script.path)
        XCTAssertEqual(String(data: output, encoding: .utf8), "  {\"ok\":true}\n")
    }

    func testNonZeroExitIncludesStderr() async throws {
        let script = try makeScript(body: "echo 'failure detail' >&2\nexit 7")
        do {
            _ = try await CustomUsageScriptRunner().run(scriptPath: script.path)
            XCTFail("Expected non-zero exit to fail")
        } catch let error as CustomUsageScriptRunnerError {
            guard case .executionFailed(let code, let stderr) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(code, 7)
            XCTAssertTrue(stderr.contains("failure detail"))
        }
    }

    func testTimeoutAndOutputLimit() async throws {
        let slowScript = try makeScript(body: "sleep 1")
        await XCTAssertThrowsErrorAsync {
            _ = try await CustomUsageScriptRunner(timeoutSeconds: 0.05).run(scriptPath: slowScript.path)
        }

        let largeScript = try makeScript(body: "printf '1234567890'")
        await XCTAssertThrowsErrorAsync {
            _ = try await CustomUsageScriptRunner(stdoutLimit: 4).run(scriptPath: largeScript.path)
        }
    }

    func testMissingAndNonExecutableFilesFail() async throws {
        await XCTAssertThrowsErrorAsync {
            _ = try await CustomUsageScriptRunner().run(
                scriptPath: self.temporaryDirectory.appendingPathComponent("missing").path
            )
        }
        let script = temporaryDirectory.appendingPathComponent("not-executable")
        try "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        await XCTAssertThrowsErrorAsync {
            _ = try await CustomUsageScriptRunner().run(scriptPath: script.path)
        }
    }

    private func makeScript(body: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(url.path, 0o700), 0)
        return url
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}

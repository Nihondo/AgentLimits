// MARK: - CustomUsageScriptRunner.swift
// Executes a selected executable file directly and captures bounded output.

import Foundation

protocol CustomUsageScriptRunning: Sendable {
    func run(scriptPath: String) async throws -> Data
}

/// カスタム使用量スクリプト実行時のエラーです。
enum CustomUsageScriptRunnerError: Error, LocalizedError {
    case fileNotFound
    case notExecutable
    case launchFailed(String)
    case timedOut
    case executionFailed(exitCode: Int32, stderr: String)
    case stdoutTooLarge
    case stderrTooLarge

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return NSLocalizedString("customUsage.runner.fileNotFound", comment: "")
        case .notExecutable:
            return NSLocalizedString("customUsage.runner.notExecutable", comment: "")
        case .launchFailed(let message):
            return String(format: NSLocalizedString("customUsage.runner.launchFailed", comment: ""), message)
        case .timedOut:
            return NSLocalizedString("customUsage.runner.timedOut", comment: "")
        case .executionFailed(let code, let stderr):
            return String(
                format: NSLocalizedString("customUsage.runner.executionFailed", comment: ""),
                code,
                stderr
            )
        case .stdoutTooLarge:
            return NSLocalizedString("customUsage.runner.stdoutTooLarge", comment: "")
        case .stderrTooLarge:
            return NSLocalizedString("customUsage.runner.stderrTooLarge", comment: "")
        }
    }
}

/// 実行可能ファイルを直接起動し、stdoutとstderrを取得します。
final class CustomUsageScriptRunner: CustomUsageScriptRunning, @unchecked Sendable {
    static let defaultTimeoutSeconds: TimeInterval = 60
    static let defaultStdoutLimit = 256 * 1024
    static let defaultStderrLimit = 64 * 1024

    private let fileManager: FileManager
    private let timeoutSeconds: TimeInterval
    private let stdoutLimit: Int
    private let stderrLimit: Int

    init(
        fileManager: FileManager = .default,
        timeoutSeconds: TimeInterval = defaultTimeoutSeconds,
        stdoutLimit: Int = defaultStdoutLimit,
        stderrLimit: Int = defaultStderrLimit
    ) {
        self.fileManager = fileManager
        self.timeoutSeconds = timeoutSeconds
        self.stdoutLimit = stdoutLimit
        self.stderrLimit = stderrLimit
    }

    /// 指定スクリプトを実行し、成功時にstdoutのrawデータを返します。
    func run(scriptPath: String) async throws -> Data {
        let scriptURL = URL(fileURLWithPath: scriptPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: scriptURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              (try? scriptURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw CustomUsageScriptRunnerError.fileNotFound
        }
        guard fileManager.isExecutableFile(atPath: scriptURL.path) else {
            throw CustomUsageScriptRunnerError.notExecutable
        }

        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("agentlimits-custom-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let stdoutURL = temporaryDirectory.appendingPathComponent("stdout")
        let stderrURL = temporaryDirectory.appendingPathComponent("stderr")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)

        let process = Process()
        process.executableURL = scriptURL
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.environment = makeEnvironment()

        let didTimeOut = LockedFlag()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try process.run()
            } catch {
                try? stdoutHandle.close()
                try? stderrHandle.close()
                continuation.resume(throwing: CustomUsageScriptRunnerError.launchFailed(error.localizedDescription))
                return
            }

            let timeoutItem = SendableDispatchWorkItem {
                guard process.isRunning else { return }
                didTimeOut.setTrue()
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeoutSeconds,
                execute: timeoutItem.item
            )
            process.terminationHandler = { terminatedProcess in
                timeoutItem.item.cancel()
                try? stdoutHandle.close()
                try? stderrHandle.close()
                if didTimeOut.value {
                    continuation.resume(throwing: CustomUsageScriptRunnerError.timedOut)
                    return
                }
                if terminatedProcess.terminationStatus != 0 {
                    let stderr = (try? Data(contentsOf: stderrURL)) ?? Data()
                    let message = String(data: stderr.prefix(self.stderrLimit), encoding: .utf8) ?? ""
                    continuation.resume(throwing: CustomUsageScriptRunnerError.executionFailed(
                        exitCode: terminatedProcess.terminationStatus,
                        stderr: message
                    ))
                    return
                }
                continuation.resume()
            }
        }

        let stdout = try Data(contentsOf: stdoutURL)
        let stderr = try Data(contentsOf: stderrURL)
        guard stdout.count <= stdoutLimit else {
            throw CustomUsageScriptRunnerError.stdoutTooLarge
        }
        guard stderr.count <= stderrLimit else {
            throw CustomUsageScriptRunnerError.stderrTooLarge
        }
        return stdout
    }

    private func makeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(homePath)/.local/bin",
            currentPath,
        ].filter { !$0.isEmpty }.joined(separator: ":")
        return environment
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var storedValue = false

    nonisolated var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    nonisolated func setTrue() {
        lock.lock()
        storedValue = true
        lock.unlock()
    }
}

private final class SendableDispatchWorkItem: @unchecked Sendable {
    nonisolated(unsafe) let item: DispatchWorkItem

    nonisolated init(action: @escaping @Sendable () -> Void) {
        item = DispatchWorkItem(block: action)
    }
}

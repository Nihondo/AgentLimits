// MARK: - ShellExecutor.swift
// Provides a common interface for executing shell commands with timeout support.
// Used by CLI-based features like ccusage and Wake Up.

import Foundation
import Darwin
@preconcurrency import Dispatch

// MARK: - Execution Result

/// Resolves the user's login shell path for CLI execution.
enum ShellPathResolver {
    /// Returns the login shell path from the system user record.
    /// Falls back to `/bin/zsh` when unavailable or non-executable.
    static func resolveLoginShellPath(fallback: String = "/bin/zsh") -> String {
        guard let shellPath = fetchLoginShellPath(),
              !shellPath.isEmpty,
              FileManager.default.isExecutableFile(atPath: shellPath) else {
            return fallback
        }
        return shellPath
    }

    /// Fetches the login shell path from the current user's passwd entry.
    private static func fetchLoginShellPath() -> String? {
        guard let passwd = getpwuid(getuid()),
              let shellPointer = passwd.pointee.pw_shell else {
            return nil
        }
        return String(cString: shellPointer)
    }
}

/// Adds a PATH prefix to commands to ensure Homebrew binaries are discoverable.
enum ShellCommandPathPrefixer {
    private static let pathPrefix = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH\";"

    /// Returns a command prefixed with PATH export unless it already sets PATH.
    static func prefixIfNeeded(command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("PATH=") || trimmed.hasPrefix("export PATH=") || trimmed.hasPrefix("env PATH=") {
            return command
        }
        return "\(pathPrefix) \(command)"
    }
}

/// Contains the complete result of a shell command execution
struct ShellExecutionResult {
    /// Standard output data from the command
    let stdout: Data
    /// Standard error data from the command
    let stderr: Data
    /// Process exit code (0 = success)
    let exitCode: Int32

    /// Standard output as String (UTF-8 decoded)
    var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    /// Standard error as String (UTF-8 decoded)
    var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }

    /// Whether the command succeeded (exit code 0)
    var isSuccess: Bool {
        exitCode == 0
    }
}

// MARK: - Shell Executor Errors

/// Errors that can occur during shell command execution
enum ShellExecutorError: Error, LocalizedError {
    /// The shell process failed to launch
    case launchFailed(underlying: Error)
    /// The command timed out and was terminated
    case timeout
    /// The command exited with a non-zero status
    case executionFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let error):
            return "Failed to launch shell: \(error.localizedDescription)"
        case .timeout:
            return "Command execution timed out"
        case .executionFailed(let code, let stderr):
            let stderrPreview = stderr.prefix(200)
            return "Command failed (\(code)): \(stderrPreview)"
        }
    }
}

// MARK: - Shell Executor

/// Executes shell commands asynchronously with timeout support.
/// Uses the user's login shell with login mode to ensure environment variables are loaded.
final class ShellExecutor: Sendable {
    /// Default timeout in seconds
    static let defaultTimeout: TimeInterval = 60

    /// Timeout duration for command execution
    private let timeout: TimeInterval

    /// Path to the shell executable
    private let shellPath: String

    /// Working directory for command execution
    private let workingDirectory: URL

    /// Creates a new shell executor with the specified configuration.
    /// - Parameters:
    ///   - timeout: Maximum time to wait for command completion (default: 60 seconds)
    ///   - shellPath: Path to the shell executable (default: user's login shell)
    ///   - workingDirectory: Directory to execute commands in (default: user's home)
    init(
        timeout: TimeInterval = defaultTimeout,
        shellPath: String = ShellPathResolver.resolveLoginShellPath(),
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.timeout = timeout
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
    }

    // MARK: - Public API

    /// Executes a shell command and returns the raw stdout data.
    /// Throws if the command fails or times out.
    /// - Parameter command: The shell command to execute
    /// - Returns: The stdout data from the command
    /// - Throws: `ShellExecutorError` if execution fails
    func execute(command: String) async throws -> Data {
        // Run command and validate exit code.
        let result = try await executeWithResult(command: command)
        if !result.isSuccess {
            throw ShellExecutorError.executionFailed(
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return result.stdout
    }

    /// Executes a shell command and returns stdout as a String.
    /// Throws if the command fails or times out.
    /// - Parameter command: The shell command to execute
    /// - Returns: The stdout output as a UTF-8 string
    /// - Throws: `ShellExecutorError` if execution fails
    func executeString(command: String) async throws -> String {
        // Run command and validate exit code, returning stdout as String.
        let result = try await executeWithResult(command: command)
        if !result.isSuccess {
            throw ShellExecutorError.executionFailed(
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return result.stdoutString
    }

    /// Executes a shell command and returns the full result including exit code.
    /// Does not throw on non-zero exit code - check `result.isSuccess` instead.
    /// - Parameter command: The shell command to execute
    /// - Returns: The complete execution result
    /// - Throws: `ShellExecutorError.launchFailed` or `.timeout` only
    func executeWithResult(command: String) async throws -> ShellExecutionResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let prefixedCommand = ShellCommandPathPrefixer.prefixIfNeeded(command: command)

        // Configure the process to run via login shell
        // Using -l flag ensures PATH and other environment variables are loaded
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l", "-c", prefixedCommand]
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = workingDirectory

        return try await withCheckedThrowingContinuation { continuation in
            // Attempt to start the process
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellExecutorError.launchFailed(underlying: error))
                return
            }

            // Set up timeout handler
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    // Terminate process on timeout.
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWorkItem
            )

            // Handle process termination
            process.terminationHandler = { proc in
                timeoutWorkItem.cancel()

                // Read all output data
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

                // Check if terminated due to timeout (uncaught signal)
                if proc.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: ShellExecutorError.timeout)
                } else {
                    // Return the result - caller decides how to handle exit code
                    let result = ShellExecutionResult(
                        stdout: outputData,
                        stderr: errorData,
                        exitCode: proc.terminationStatus
                    )
                    continuation.resume(returning: result)
                }
            }
        }
    }
}

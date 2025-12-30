// MARK: - WakeUpScheduler.swift
// Manages scheduled CLI invocations via LaunchAgent to wake up Claude Code and Codex sessions.
// Creates plist files in ~/Library/LaunchAgents/ for launchd to execute CLI commands.

import Combine
@preconcurrency import Foundation
import OSLog

// MARK: - Configuration

/// LaunchAgent configuration constants
enum LaunchAgentConfig {
    static let labelPrefix = "com.dmng.agentlimit.wakeup"
    static let launchAgentsPath = "Library/LaunchAgents"
    static let logDirectory = "/tmp"
}

// MARK: - Wake Up Schedule

/// Configuration for wake-up schedule per provider
struct WakeUpSchedule: Codable, Equatable {
    let provider: UsageProvider
    /// Enabled hours (0-23) for wake-up calls
    var enabledHours: Set<Int>
    /// Whether the schedule is active
    var isEnabled: Bool
    /// Additional CLI arguments (e.g., --model="haiku")
    var additionalArgs: String = ""

    /// Creates a default disabled schedule for a provider
    static func defaultSchedule(for provider: UsageProvider) -> WakeUpSchedule {
        WakeUpSchedule(
            provider: provider,
            enabledHours: [],
            isEnabled: false,
            additionalArgs: ""
        )
    }

    /// Returns the LaunchAgent label for this schedule
    var launchAgentLabel: String {
        "\(LaunchAgentConfig.labelPrefix)-\(provider.rawValue)"
    }

    /// Returns the plist filename for this schedule
    var plistFileName: String {
        "\(launchAgentLabel).plist"
    }

    /// Returns the base CLI command (without logging prefix)
    var cliCommand: String {
        let args = additionalArgs.trimmingCharacters(in: .whitespaces)
        let suffix = args.isEmpty ? "" : " \(args)"

        switch provider {
        case .chatgptCodex:
            return "codex exec --skip-git-repo-check \"hello\"\(suffix)"
        case .claudeCode:
            return "claude -p \"hello\"\(suffix)"
        }
    }

    /// Returns the log file path for this schedule
    var logPath: String {
        "\(LaunchAgentConfig.logDirectory)/agentlimit-wakeup-\(provider.rawValue).log"
    }
}

// MARK: - Wake Up Result

/// Result of a CLI wake-up invocation
enum WakeUpResult {
    case success(output: String)
    case failure(error: WakeUpError)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Errors that can occur during wake-up operations
enum WakeUpError: Error, LocalizedError {
    case cliNotFound(command: String)
    case executionFailed(exitCode: Int32, stderr: String)
    case timeout
    case launchAgentWriteFailed(Error)
    case launchAgentLoadFailed(Error)
    case homeDirectoryNotFound

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let command):
            return "CLI not found: \(command)"
        case .executionFailed(let code, let stderr):
            return "CLI failed (\(code)): \(stderr)"
        case .timeout:
            return "CLI execution timed out"
        case .launchAgentWriteFailed(let error):
            return "Failed to write LaunchAgent: \(error.localizedDescription)"
        case .launchAgentLoadFailed(let error):
            return "Failed to load LaunchAgent: \(error.localizedDescription)"
        case .homeDirectoryNotFound:
            return "Home directory not found"
        }
    }
}

// MARK: - LaunchAgent Manager

/// Manages LaunchAgent plist files for scheduled CLI execution
final class LaunchAgentManager {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns the real user home directory (not sandboxed container)
    private var realHomeDirectory: URL {
        // Use POSIX API to get real home directory, bypassing sandbox
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        // Fallback to environment variable
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        // Last resort (may be sandboxed)
        return fileManager.homeDirectoryForCurrentUser
    }

    /// Returns the LaunchAgents directory URL
    private var launchAgentsURL: URL? {
        realHomeDirectory
            .appendingPathComponent(LaunchAgentConfig.launchAgentsPath, isDirectory: true)
    }

    /// Returns the plist file URL for a schedule
    func plistURL(for schedule: WakeUpSchedule) -> URL? {
        launchAgentsURL?.appendingPathComponent(schedule.plistFileName)
    }

    /// Checks if a LaunchAgent is installed for the given schedule
    func isInstalled(for schedule: WakeUpSchedule) -> Bool {
        guard let url = plistURL(for: schedule) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// Installs or updates a LaunchAgent for the given schedule
    func install(schedule: WakeUpSchedule) throws {
        guard let url = plistURL(for: schedule) else {
            Logger.wakeup.error("LaunchAgentManager: homeDirectoryNotFound")
            throw WakeUpError.homeDirectoryNotFound
        }

        Logger.wakeup.info("LaunchAgentManager: Installing plist at \(url.path)")

        // Unload existing agent if present
        if isInstalled(for: schedule) {
            Logger.wakeup.info("LaunchAgentManager: Unloading existing agent")
            unload(schedule: schedule)
        }

        // Generate plist content
        let plistData = try generatePlist(for: schedule)
        Logger.wakeup.info("LaunchAgentManager: Generated plist data (\(plistData.count) bytes)")

        // Ensure directory exists
        if let directory = launchAgentsURL {
            do {
                // Create LaunchAgents directory if needed.
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                Logger.wakeup.info("LaunchAgentManager: Directory ensured at \(directory.path)")
            } catch {
                Logger.wakeup.error("LaunchAgentManager: Failed to create directory: \(error.localizedDescription)")
            }
        }

        // Write plist file
        do {
            // Persist plist atomically to avoid partial writes.
            try plistData.write(to: url, options: .atomic)
            Logger.wakeup.info("LaunchAgentManager: Plist written successfully")
        } catch {
            Logger.wakeup.error("LaunchAgentManager: Failed to write plist: \(error.localizedDescription)")
            throw WakeUpError.launchAgentWriteFailed(error)
        }

        // Load the agent
        try load(schedule: schedule)
    }

    /// Uninstalls a LaunchAgent for the given schedule
    func uninstall(schedule: WakeUpSchedule) {
        guard let url = plistURL(for: schedule) else { return }

        // Unload first
        unload(schedule: schedule)

        // Remove plist file
        try? fileManager.removeItem(at: url)
    }

    /// Loads a LaunchAgent using launchctl bootstrap (modern API)
    private func load(schedule: WakeUpSchedule) throws {
        guard let url = plistURL(for: schedule) else { return }

        // Use bootstrap for modern macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", "gui/\(getuid())", url.path]

        do {
            // Run launchctl and wait for completion.
            try process.run()
            process.waitUntilExit()
            // Exit code 37 means "already loaded", which is fine
            if process.terminationStatus != 0 && process.terminationStatus != 37 {
                Logger.wakeup.warning("LaunchAgent load warning: exit code \(process.terminationStatus)")
            }
        } catch {
            throw WakeUpError.launchAgentLoadFailed(error)
        }
    }

    /// Unloads a LaunchAgent using launchctl bootout (modern API)
    private func unload(schedule: WakeUpSchedule) {
        // Use bootout with label for modern macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(schedule.launchAgentLabel)"]

        // Best-effort unload; ignore errors if not loaded.
        try? process.run()
        process.waitUntilExit()
        // Ignore errors - service may not be loaded
    }

    /// Generates plist data for a schedule
    private func generatePlist(for schedule: WakeUpSchedule) throws -> Data {
        // Build full command with logging prefix
        let fullCommand = "echo \"=== $(date) ===\" && echo \"Command: \(schedule.cliCommand)\" && mkdir -p ~/.agentlimits && cd ~/.agentlimits && \(schedule.cliCommand)"

        // Build StartCalendarInterval array
        var calendarIntervals: [[String: Int]] = []
        for hour in schedule.enabledHours.sorted() {
            calendarIntervals.append([
                "Hour": hour,
                "Minute": 0
            ])
        }

        // Compose LaunchAgent plist payload.
        let plist: [String: Any] = [
            "Label": schedule.launchAgentLabel,
            "ProgramArguments": [
                "/bin/zsh",
                "-l",
                "-c",
                fullCommand
            ],
            "StartCalendarInterval": calendarIntervals,
            "StandardOutPath": schedule.logPath,
            "StandardErrorPath": schedule.logPath,
            "RunAtLoad": false
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
    }
}

// MARK: - CLI Executor

/// Executes CLI commands for manual wake-up testing.
/// Uses ShellExecutor for command execution with timeout support.
final class CLIExecutor {
    private let shellExecutor: ShellExecutor

    /// Creates a new CLI executor with the specified timeout.
    /// - Parameter timeout: Maximum time to wait for command completion (default: 30 seconds)
    init(timeout: TimeInterval = 30) {
        self.shellExecutor = ShellExecutor(timeout: timeout)
    }

    /// Executes a CLI command for the given schedule and returns the output.
    /// Logs execution to the schedule's log file with a [TEST] marker.
    /// - Parameter schedule: The wake-up schedule containing the command to execute
    /// - Returns: The command output as a string
    /// - Throws: `WakeUpError` if execution fails
    func execute(for schedule: WakeUpSchedule) async throws -> String {
        // Build command with logging (same format as LaunchAgent, with [TEST] marker)
        let command = "{ echo \"=== $(date) [TEST] ===\" && echo \"Command: \(schedule.cliCommand)\" && mkdir -p ~/.agentlimits && cd ~/.agentlimits && \(schedule.cliCommand); } 2>&1 | tee -a \"\(schedule.logPath)\""

        do {
            return try await shellExecutor.executeString(command: command)
        } catch let error as ShellExecutorError {
            throw mapShellError(error, schedule: schedule)
        }
    }

    /// Maps ShellExecutorError to WakeUpError for domain-specific error messages.
    /// - Parameters:
    ///   - error: The shell execution error
    ///   - schedule: The schedule that was being executed (for error context)
    /// - Returns: A WakeUpError with appropriate message
    private func mapShellError(_ error: ShellExecutorError, schedule: WakeUpSchedule) -> WakeUpError {
        switch error {
        case .launchFailed:
            return .cliNotFound(command: schedule.cliCommand)
        case .timeout:
            return .timeout
        case .executionFailed(let exitCode, let stderr):
            return .executionFailed(exitCode: exitCode, stderr: stderr)
        }
    }
}

// MARK: - Schedule Store

/// Persists wake-up schedules to UserDefaults
final class WakeUpScheduleStore {
    private let userDefaults: UserDefaults
    private let key = "wake_up_schedules"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Loads all schedules from storage
    func loadSchedules() -> [UsageProvider: WakeUpSchedule] {
        guard let data = userDefaults.data(forKey: key),
              let schedules = try? JSONDecoder().decode([WakeUpSchedule].self, from: data) else {
            return makeDefaultSchedules()
        }
        return Dictionary(uniqueKeysWithValues: schedules.map { ($0.provider, $0) })
    }

    /// Saves all schedules to storage
    func saveSchedules(_ schedules: [UsageProvider: WakeUpSchedule]) {
        let array = Array(schedules.values)
        if let data = try? JSONEncoder().encode(array) {
            userDefaults.set(data, forKey: key)
        }
    }

    /// Creates default schedules for all providers
    private func makeDefaultSchedules() -> [UsageProvider: WakeUpSchedule] {
        Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map {
            ($0, WakeUpSchedule.defaultSchedule(for: $0))
        })
    }
}

// MARK: - Wake Up Scheduler

/// Manages scheduled wake-up calls for AI coding assistants via LaunchAgent
@MainActor
final class WakeUpScheduler: ObservableObject {
    static let shared = WakeUpScheduler()

    @Published private(set) var schedules: [UsageProvider: WakeUpSchedule]
    @Published private(set) var lastWakeUpResults: [UsageProvider: WakeUpResult] = [:]
    @Published private(set) var isTestRunning: [UsageProvider: Bool] = [:]

    private let launchAgentManager: LaunchAgentManager
    private let executor: CLIExecutor
    private let store: WakeUpScheduleStore

    private init() {
        self.launchAgentManager = LaunchAgentManager()
        self.executor = CLIExecutor()
        self.store = WakeUpScheduleStore()
        self.schedules = store.loadSchedules()

        // Initialize isTestRunning
        for provider in UsageProvider.allCases {
            isTestRunning[provider] = false
        }

        // Sync LaunchAgents with saved schedules
        syncLaunchAgents()
    }

    /// Returns whether a LaunchAgent is installed for a provider
    func isLaunchAgentInstalled(for provider: UsageProvider) -> Bool {
        guard let schedule = schedules[provider] else { return false }
        return launchAgentManager.isInstalled(for: schedule)
    }

    /// Updates schedule for a provider and syncs LaunchAgent
    func updateSchedule(_ schedule: WakeUpSchedule) {
        Logger.wakeup.debug("WakeUpScheduler: updateSchedule provider=\(schedule.provider.rawValue) isEnabled=\(schedule.isEnabled) hours=\(schedule.enabledHours.count)")
        schedules[schedule.provider] = schedule
        store.saveSchedules(schedules)

        if schedule.isEnabled && !schedule.enabledHours.isEmpty {
            do {
                try launchAgentManager.install(schedule: schedule)
            } catch {
                Logger.wakeup.error("WakeUpScheduler: Failed to install LaunchAgent: \(error.localizedDescription)")
            }
        } else {
            launchAgentManager.uninstall(schedule: schedule)
        }
    }

    /// Manually triggers a wake-up for testing
    func triggerWakeUp(for provider: UsageProvider) async {
        guard let schedule = schedules[provider] else { return }

        isTestRunning[provider] = true
        defer { isTestRunning[provider] = false }

        do {
            let output = try await executor.execute(for: schedule)
            lastWakeUpResults[provider] = .success(output: output)
            Logger.wakeup.info("WakeUpScheduler: Successfully tested \(provider.displayName)")
        } catch let error as WakeUpError {
            lastWakeUpResults[provider] = .failure(error: error)
            Logger.wakeup.error("WakeUpScheduler: Test failed for \(provider.displayName): \(error.localizedDescription)")
        } catch {
            let wakeUpError = WakeUpError.executionFailed(exitCode: -1, stderr: error.localizedDescription)
            lastWakeUpResults[provider] = .failure(error: wakeUpError)
            Logger.wakeup.error("WakeUpScheduler: Test failed for \(provider.displayName): \(error.localizedDescription)")
        }
    }

    /// Syncs LaunchAgents with saved schedules on startup
    private func syncLaunchAgents() {
        for provider in UsageProvider.allCases {
            guard let schedule = schedules[provider] else { continue }

            if schedule.isEnabled && !schedule.enabledHours.isEmpty {
                do {
                    try launchAgentManager.install(schedule: schedule)
                } catch {
                    Logger.wakeup.error("WakeUpScheduler: Failed to sync LaunchAgent for \(provider.displayName): \(error.localizedDescription)")
                }
            } else {
                launchAgentManager.uninstall(schedule: schedule)
            }
        }
    }

    /// Uninstalls all LaunchAgents (for app cleanup)
    func uninstallAllLaunchAgents() {
        for provider in UsageProvider.allCases {
            guard let schedule = schedules[provider] else { continue }
            launchAgentManager.uninstall(schedule: schedule)
        }
    }
}

// MARK: - AutoRefreshCoordinator.swift
// Manages auto-refresh timer logic for periodic data updates.
// Extracted from UsageViewModel for single responsibility principle.

import Foundation

// MARK: - Auto Refresh Coordinator

/// Coordinates automatic refresh cycles with configurable intervals.
/// Uses async/await for timer management and calls back to perform actual refresh work.
/// Thread-safe and designed to be used from the main actor.
@MainActor
final class AutoRefreshCoordinator {
    /// Callback invoked on each refresh cycle
    typealias RefreshHandler = @MainActor () async -> Void

    /// Provider for the current refresh interval duration
    typealias IntervalProvider = @MainActor () -> Duration

    // MARK: - Properties

    private var refreshTask: Task<Void, Never>?
    private let refreshHandler: RefreshHandler
    private let intervalProvider: IntervalProvider

    /// Whether the coordinator is currently running
    var isRunning: Bool {
        refreshTask != nil
    }

    // MARK: - Initialization

    /// Creates a new auto-refresh coordinator.
    /// - Parameters:
    ///   - intervalProvider: Closure that returns the current refresh interval.
    ///                       Called on each cycle to support dynamic interval changes.
    ///   - refreshHandler: Async closure called to perform the actual refresh work.
    init(
        intervalProvider: @escaping IntervalProvider,
        refreshHandler: @escaping RefreshHandler
    ) {
        self.intervalProvider = intervalProvider
        self.refreshHandler = refreshHandler
    }

    /// Creates a coordinator with a fixed interval.
    /// - Parameters:
    ///   - interval: The fixed refresh interval duration
    ///   - refreshHandler: Async closure called to perform the actual refresh work
    convenience init(
        interval: Duration,
        refreshHandler: @escaping RefreshHandler
    ) {
        self.init(
            intervalProvider: { interval },
            refreshHandler: refreshHandler
        )
    }

    // MARK: - Public API

    /// Starts the auto-refresh timer.
    /// Performs an immediate refresh, then continues at the configured interval.
    /// Does nothing if already running.
    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            // Perform initial refresh immediately
            await refreshHandler()
            // Continue refreshing at interval until cancelled
            while !Task.isCancelled {
                let interval = intervalProvider()
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                await refreshHandler()
            }
        }
    }

    /// Stops the auto-refresh timer.
    /// Safe to call even if not running.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Restarts the auto-refresh timer.
    /// Useful when the refresh interval has changed.
    func restart() {
        stop()
        start()
    }

    deinit {
        refreshTask?.cancel()
    }
}

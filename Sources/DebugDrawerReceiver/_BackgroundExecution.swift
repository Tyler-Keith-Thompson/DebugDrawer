// The system's ways of keeping an app running in the background, one per platform, and only those
// the platform sanctions for it (charter D10): a UIKit background task on iOS, iPadOS, tvOS and
// visionOS, a continued processing task on iOS and iPadOS 26 and later, and a `ProcessInfo`
// activity on macOS and Mac Catalyst, where apps aren't suspended but App Nap slows them. watchOS
// has nothing that fits: `WKExtendedRuntimeSession` runs only for its own session types (self
// care, mindfulness, physical therapy, smart alarm), so there it asks for nothing. No background
// mode (audio, location, VoIP) is claimed anywhere.
//
// BackgroundTasks' module exists in the macOS SDK with every type unavailable, and the continued
// processing task is unavailable on Mac Catalyst, tvOS and visionOS too, so its code builds for
// iOS alone.

import Combine
import Foundation
import os
#if os(iOS) && !targetEnvironment(macCatalyst)
    import BackgroundTasks
#endif
#if canImport(UIKit) && !os(watchOS)
    import UIKit
#endif

/// The system's background execution: what the platform offers, asked of the system.
@MainActor
final class _BackgroundExecution: BackgroundExecution {
    private nonisolated static let logger = Logger(subsystem: "DebugDrawer", category: "BackgroundExecution")

    var shortRequest: DebugDrawerBackgroundRequest {
        #if os(macOS) || targetEnvironment(macCatalyst)
            .activity
        #elseif os(watchOS)
            .none
        #else
            .backgroundTask
        #endif
    }

    var foregroundEntries: AnyPublisher<Void, Never> {
        #if os(macOS) || targetEnvironment(macCatalyst) || os(watchOS)
            // An activity never expires, so there is nothing to make again; watchOS makes
            // nothing.
            Empty().eraseToAnyPublisher()
        #else
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .map { _ in }
                .eraseToAnyPublisher()
        #endif
    }

    func begin(reason: String, expired: @escaping @MainActor () -> Void) -> (any BackgroundExecutionRequest)? {
        #if os(macOS) || targetEnvironment(macCatalyst)
            // Mac Catalyst takes this branch: a Catalyst app runs in a Mac window, isn't
            // suspended, and is slowed by App Nap as a Mac app is.
            ProcessActivity(reason: reason)
        #elseif os(watchOS)
            nil
        #else
            UIKitBackgroundTask(reason: reason, expired: expired).held
        #endif
    }

    func submitContinuedProcessing(
        identifier: String,
        title: String,
        subtitle: String,
        launched: @escaping @MainActor (any ContinuedProcessingTask) -> Void,
        expired: @escaping @MainActor () -> Void
    ) async throws(ContinuedProcessingRefusal) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            guard #available(iOS 26.0, *) else { throw .unsupported }
            // Registered once per identifier, as each submission's is its own; a continued
            // processing task may be registered after launch. The handler runs on the main
            // queue, where the keeper is.
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
                MainActor.assumeIsolated {
                    guard let task = task as? BGContinuedProcessingTask else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    launched(SystemContinuedProcessingTask(task, expired: expired))
                }
            }
            guard registered else {
                Self.logger.notice("\(identifier, privacy: .public) matches no BGTaskSchedulerPermittedIdentifiers entry")
                throw .notPermitted
            }
            try await Self.submit(identifier: identifier, title: title, subtitle: subtitle)
        #else
            throw .unsupported
        #endif
    }

    func cancelContinuedProcessing(identifier: String) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        #endif
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
        /// Builds and submits the request off the main actor: submitting can block while the
        /// scheduler checks it, and Apple asks that it not be done on the main thread. It runs
        /// at once or fails: a debug session queued for later would keep nothing running now.
        @available(iOS 26.0, *)
        @concurrent
        private static func submit(identifier: String, title: String, subtitle: String) async throws(ContinuedProcessingRefusal) {
            let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
            request.strategy = .fail
            do {
                if #available(iOS 27.0, *) {
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } else {
                    try BGTaskScheduler.shared.submit(request)
                }
            } catch {
                logger.notice("The scheduler refused \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw .refused(error.localizedDescription)
            }
        }
    #endif
}

#if os(macOS) || targetEnvironment(macCatalyst)
    /// An activity that keeps App Nap from slowing the app, for as long as it is held. It never
    /// expires.
    @MainActor
    private final class ProcessActivity: BackgroundExecutionRequest {
        private var token: (any NSObjectProtocol)?

        init(reason: String) {
            // Allowing idle sleep: a session left open on a Mac nobody uses shouldn't keep it
            // awake, and the session's expiry still ends it.
            token = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: reason)
        }

        func end() {
            guard let token else { return }
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
#elseif canImport(UIKit) && !os(watchOS)
    /// A UIKit background task, held until it is ended or the system expires it.
    @MainActor
    private final class UIKitBackgroundTask: BackgroundExecutionRequest {
        private var identifier = UIBackgroundTaskIdentifier.invalid

        init(reason: String, expired: @escaping @MainActor () -> Void) {
            identifier = UIApplication.shared.beginBackgroundTask(withName: reason) { [weak self] in
                // UIKit calls the handler on the main thread, and the task must be ended
                // before it returns.
                MainActor.assumeIsolated {
                    guard let self, self.identifier != .invalid else { return }
                    self.end()
                    expired()
                }
            }
        }

        /// The task, or `nil` when UIKit refused it.
        var held: UIKitBackgroundTask? {
            identifier == .invalid ? nil : self
        }

        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
#endif

#if os(iOS) && !targetEnvironment(macCatalyst)
    /// A running `BGContinuedProcessingTask`, whose progress the system shows until it is
    /// completed or expires.
    @available(iOS 26.0, *)
    @MainActor
    private final class SystemContinuedProcessingTask: ContinuedProcessingTask {
        private let task: BGContinuedProcessingTask
        private var isDone = false

        init(_ task: BGContinuedProcessingTask, expired: @escaping @MainActor () -> Void) {
            self.task = task
            // The system calls the handler on a queue of its own, as the person stops the task
            // or the system needs its resources back.
            task.expirationHandler = { [weak self] in
                Task { @MainActor in
                    guard let self, !self.isDone else { return }
                    self.isDone = true
                    self.task.setTaskCompleted(success: false)
                    expired()
                }
            }
        }

        func report(completed: Int64, of total: Int64) {
            task.progress.totalUnitCount = total
            task.progress.completedUnitCount = completed
        }

        func complete() {
            guard !isDone else { return }
            isDone = true
            task.setTaskCompleted(success: true)
        }
    }
#endif

import Combine
import Foundation

/// The platform's ways of keeping the app running in the background, as
/// ``DebugDrawerBackgroundKeeper`` asks for them. `_BackgroundExecution` asks the system; tests
/// pass a fake that records each request and expires or launches it when the test says.
@MainActor
protocol BackgroundExecution: AnyObject {
    /// What ``begin(reason:expired:)`` holds on this platform; `.none` where it holds nothing.
    var shortRequest: DebugDrawerBackgroundRequest { get }

    /// Each time the app comes back to the foreground, where a request the system ended can be
    /// made again.
    var foregroundEntries: AnyPublisher<Void, Never> { get }

    /// Asks to keep running: a background task, or an activity that keeps App Nap away.
    ///
    /// - Parameters:
    ///   - reason: What the system shows in its logs for the request.
    ///   - expired: Called, on the main actor, if the system ends the request before it is
    ///     ended; the request is already ended then.
    /// - Returns: The request, to end; `nil` where the platform has none to make or the system
    ///   refused it.
    func begin(reason: String, expired: @escaping @MainActor () -> Void) -> (any BackgroundExecutionRequest)?

    /// Submits a continued processing task, which the system runs at once, with its progress
    /// shown, or refuses.
    ///
    /// - Parameters:
    ///   - identifier: The task's identifier, unique to this submission, matching a
    ///     `<prefix>.*` entry of the app's `BGTaskSchedulerPermittedIdentifiers`.
    ///   - title: What the system's progress shows as the title.
    ///   - subtitle: What it shows beneath.
    ///   - launched: Called, on the main actor, with the task once the system runs it.
    ///   - expired: Called, on the main actor, if the system or the person ends the task
    ///     before it is completed.
    /// - Throws: Why the task won't run.
    func submitContinuedProcessing(
        identifier: String,
        title: String,
        subtitle: String,
        launched: @escaping @MainActor (any ContinuedProcessingTask) -> Void,
        expired: @escaping @MainActor () -> Void
    ) async throws(ContinuedProcessingRefusal)

    /// Withdraws a submitted continued processing task the system hasn't run yet.
    func cancelContinuedProcessing(identifier: String)
}

/// A request to keep running that ``BackgroundExecution/begin(reason:expired:)`` made.
@MainActor
protocol BackgroundExecutionRequest: AnyObject {
    /// Ends the request; does nothing once it has ended.
    func end()
}

/// A continued processing task the system runs, with its progress shown.
@MainActor
protocol ContinuedProcessingTask: AnyObject {
    /// Shows `completed` of `total` units done in the system's progress.
    func report(completed: Int64, of total: Int64)

    /// Tells the system the task is done, which removes its progress; does nothing once done.
    func complete()
}

/// Why a continued processing task won't run.
enum ContinuedProcessingRefusal: Error, Equatable {
    /// The platform has none: before iOS 26, and on macOS, Mac Catalyst, tvOS, visionOS and
    /// watchOS.
    case unsupported
    /// The identifier matches no `BGTaskSchedulerPermittedIdentifiers` entry.
    case notPermitted
    /// The scheduler refused the request, as it does when it can't run it at once; its
    /// description.
    case refused(String)
}

import Combine
@testable import DebugDrawerReceiver
import Foundation
import Testing

/// A session-scoped capability: a log level a sidecar elevates, which `reset` puts back.
@MainActor
private final class LogLevelModel: DebugDrawerPluginModel {
    struct Snapshot: Codable, Equatable, Sendable {
        var level = "info"
    }

    enum Command: Codable, Equatable, Sendable {
        case set(String)
        case reset
    }

    @Published private(set) var snapshot = Snapshot()

    func perform(_ command: Command) {
        switch command {
        case let .set(level): snapshot.level = level
        case .reset: snapshot.level = "info"
        }
    }
}

/// A wall clock the test moves by hand.
private final class FakeClock: SessionClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// A session timer that fires when the test says.
@MainActor
private final class FakeTimer: SessionTimer {
    private var handler: (@MainActor () -> Void)?

    func schedule(at _: Date, _ fire: @escaping @MainActor () -> Void) {
        handler = fire
    }

    func cancel() {
        handler = nil
    }

    /// Fires the scheduled call, as the run loop would at its date.
    func fire() {
        let handler = handler
        self.handler = nil
        handler?()
    }
}

/// A progress timer that ticks when the test says, and records the interval it was started with.
@MainActor
private final class FakeProgressTimer: ProgressTimer {
    private var handler: (@MainActor () -> Void)?
    private(set) var intervals: [TimeInterval] = []
    private(set) var stops = 0

    var isRunning: Bool { handler != nil }

    func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) {
        intervals.append(interval)
        handler = tick
    }

    func stop() {
        if handler != nil { stops += 1 }
        handler = nil
    }

    /// Calls the tick, as the run loop would at each interval.
    func tick() {
        handler?()
    }
}

/// A short request the fake made: counts how often it is ended, and expires when the test says.
@MainActor
private final class FakeRequest: BackgroundExecutionRequest {
    private(set) var ends = 0
    private let expired: @MainActor () -> Void

    init(expired: @escaping @MainActor () -> Void) {
        self.expired = expired
    }

    func end() {
        ends += 1
    }

    /// Ends the request as the system does at its expiry, then tells the keeper.
    func expire() {
        ends += 1
        expired()
    }
}

/// A continued processing task the fake launched: records each progress report and each
/// completion.
@MainActor
private final class FakeContinuedTask: ContinuedProcessingTask {
    struct Report: Equatable {
        let completed: Int64
        let total: Int64
    }

    private(set) var reports: [Report] = []
    private(set) var completions = 0

    func report(completed: Int64, of total: Int64) {
        reports.append(Report(completed: completed, total: total))
    }

    func complete() {
        completions += 1
    }
}

/// A continued processing submission the fake received.
@MainActor
private struct Submission {
    let identifier: String
    let title: String
    let subtitle: String
    let launched: @MainActor (any ContinuedProcessingTask) -> Void
    let expired: @MainActor () -> Void
}

/// The platform, faked: it records each request and submission, refuses a submission when told
/// to, and launches, expires and brings the app to the foreground when the test says.
@MainActor
private final class FakeBackgroundExecution: BackgroundExecution {
    let shortRequest: DebugDrawerBackgroundRequest
    /// Why the next submissions are refused; `nil` accepts them.
    var refusal: ContinuedProcessingRefusal?
    private(set) var requests: [FakeRequest] = []
    @Published private(set) var submissions: [Submission] = []
    private(set) var cancelled: [String] = []
    private let foreground = PassthroughSubject<Void, Never>()

    init(shortRequest: DebugDrawerBackgroundRequest = .backgroundTask) {
        self.shortRequest = shortRequest
    }

    var foregroundEntries: AnyPublisher<Void, Never> {
        foreground.eraseToAnyPublisher()
    }

    func begin(reason _: String, expired: @escaping @MainActor () -> Void) -> (any BackgroundExecutionRequest)? {
        guard shortRequest != .none else { return nil }
        let request = FakeRequest(expired: expired)
        requests.append(request)
        return request
    }

    func submitContinuedProcessing(
        identifier: String,
        title: String,
        subtitle: String,
        launched: @escaping @MainActor (any ContinuedProcessingTask) -> Void,
        expired: @escaping @MainActor () -> Void
    ) async throws(ContinuedProcessingRefusal) {
        submissions.append(Submission(identifier: identifier, title: title, subtitle: subtitle, launched: launched, expired: expired))
        if let refusal { throw refusal }
    }

    func cancelContinuedProcessing(identifier: String) {
        cancelled.append(identifier)
    }

    /// The app comes back to the foreground.
    func enterForeground() {
        foreground.send()
    }

    /// Waits until the keeper has submitted `count` continued processing tasks, and returns the
    /// last.
    func submission(_ count: Int) async throws -> Submission {
        for await submissions in $submissions.values where submissions.count == count {
            return try #require(submissions.last)
        }
        throw CancellationError()
    }
}

// The keeper of the app in the background, against a fake platform: each request it makes is
// recorded, and the system's part (expiring a request, running or refusing a continued processing
// task, the app returning to the foreground, the person stopping the task) happens when the test
// says. Sessions are the real ones on a fake clock and timer, so ending, expiring and reverting
// are theirs; a sidecar's command reaches them as the receiver's would, through `perform` and
// `apply`. A sidecar disconnecting is a subject the test sends on. The one wait, for a submission
// the keeper makes from a task of its own, is for the submission itself; nothing waits for time.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BackgroundKeeperTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let prefix = "com.example.app.DebugDrawerSession"

    @Test(
        "A session the sidecar opens holds the platform's short request until it ends, by the sidecar, the host or expiry; it ends once",
        arguments: ["sidecar", "host", "expiry"]
    )
    func shortRequestForTheSession(ending: String) {
        let timer = FakeTimer()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: timer)
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )
        let before = sut.request

        sessions.perform(.open(duration: 60))
        let during = sut.request
        switch ending {
        case "sidecar": sessions.perform(.end)
        case "host": sessions.end()
        default: timer.fire()
        }

        #expect(before == .none)
        #expect(during == .backgroundTask)
        #expect(sut.request == .none)
        #expect(execution.requests.count == 1)
        #expect(execution.requests.first?.ends == 1)
        #expect(execution.submissions.isEmpty)
    }

    @Test(
        "The platform's short request shows as the keeper's request: an activity on the Mac, nothing where there is none",
        arguments: [DebugDrawerBackgroundRequest.activity, .backgroundTask, .none]
    )
    func requestKindFollowsThePlatform(platform: DebugDrawerBackgroundRequest) {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: FakeBackgroundExecution(shortRequest: platform), clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )

        sessions.perform(.open(duration: 60))

        #expect(sut.request == platform)
    }

    @Test("When the system expires the short request the keeper holds nothing; back in the foreground it asks again; the end ends that one")
    func shortRequestAgainInTheForeground() throws {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )

        sessions.perform(.open(duration: 60))
        let first = try #require(execution.requests.first)
        first.expire()
        let afterExpiry = sut.request
        execution.enterForeground()
        let afterForeground = sut.request
        sessions.end()

        #expect(afterExpiry == .none)
        #expect(afterForeground == .backgroundTask)
        #expect(sut.request == .none)
        #expect(execution.requests.count == 2)
        #expect(execution.requests.map(\.ends) == [1, 1])
    }

    @Test("Coming back to the foreground with no session open, or with a request still held, asks for nothing")
    func foregroundWithoutNeed() {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )

        execution.enterForeground()
        sessions.perform(.open(duration: 60))
        execution.enterForeground()

        #expect(execution.requests.count == 1)
        #expect(sut.request == .backgroundTask)
    }

    @Test("startSession submits a continued processing task named by prefix and session ID; once it runs, the short request ends and progress shows")
    func continuedProcessingFromAPersonsAction() async throws {
        let clock = FakeClock(Self.start)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: FakeTimer())
        let logLevels = LogLevelModel()
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: clock, progressTimer: FakeProgressTimer()
        )
        let task = FakeContinuedTask()
        let expectedReports = [
            FakeContinuedTask.Report(completed: 0, total: 60), FakeContinuedTask.Report(completed: 15, total: 60)
        ]

        sut.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")
        let session = try #require(sessions.snapshot.session)
        let submission = try await execution.submission(1)
        let whileSubmitted = sut.request
        submission.launched(task)
        let whileRunning = sut.request
        clock.now = Self.start.addingTimeInterval(15)
        sessions.apply(to: "LogLevels", scope: .session(revert: { logLevels.perform(.reset) })) {
            logLevels.perform(.set("debug"))
            return true
        }

        #expect(submission.identifier == "\(Self.prefix).\(session.id.uuidString)")
        #expect(submission.title == "Debug session")
        #expect(submission.subtitle == "Inspector")
        #expect(whileSubmitted == .backgroundTask)
        #expect(whileRunning == .continuedProcessing)
        #expect(execution.requests.map(\.ends) == [1])
        #expect(task.reports == expectedReports)
        #expect(task.completions == 0)
    }

    @Test("While the continued task runs, progress moves every second with no command from the sidecar, so the system never sees it stall")
    func continuedProcessingProgressesWhileIdle() async throws {
        let clock = FakeClock(Self.start)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: FakeTimer())
        let execution = FakeBackgroundExecution()
        let progressTimer = FakeProgressTimer()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: clock, progressTimer: progressTimer
        )
        let task = FakeContinuedTask()
        let expectedIntervals: [TimeInterval] = [1]
        let expectedReports = [
            FakeContinuedTask.Report(completed: 0, total: 60),
            FakeContinuedTask.Report(completed: 1, total: 60),
            FakeContinuedTask.Report(completed: 2, total: 60),
            FakeContinuedTask.Report(completed: 60, total: 60)
        ]

        sut.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")
        let submission = try await execution.submission(1)
        let runningBeforeLaunch = progressTimer.isRunning
        submission.launched(task)
        clock.now = Self.start.addingTimeInterval(1)
        progressTimer.tick()
        clock.now = Self.start.addingTimeInterval(2)
        progressTimer.tick()
        clock.now = Self.start.addingTimeInterval(90)
        progressTimer.tick()

        #expect(!runningBeforeLaunch)
        #expect(progressTimer.intervals == expectedIntervals)
        #expect(task.reports == expectedReports)
        #expect(sut.request == .continuedProcessing)
    }

    @Test("The progress timer stops as the session ends, and as the system expires the task")
    func progressTimerStops() async throws {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let execution = FakeBackgroundExecution()
        let endedTimer = FakeProgressTimer()
        let expiredTimer = FakeProgressTimer()
        let ended = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: endedTimer
        )
        let endedTask = FakeContinuedTask()

        ended.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")
        try await execution.submission(1).launched(endedTask)
        sessions.end()
        let otherSessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let otherExecution = FakeBackgroundExecution()
        let expired = DebugDrawerBackgroundKeeper(
            sessions: otherSessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: otherExecution, clock: FakeClock(Self.start), progressTimer: expiredTimer
        )
        expired.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")
        let submission = try await otherExecution.submission(1)
        submission.launched(FakeContinuedTask())
        submission.expired()

        #expect(!endedTimer.isRunning)
        #expect(endedTimer.stops == 1)
        #expect(endedTask.completions == 1)
        #expect(!expiredTimer.isRunning)
        #expect(expiredTimer.stops == 1)
    }

    @Test(
        "A running continued processing task completes exactly once as the session ends, by the sidecar, the host or expiry",
        arguments: ["sidecar", "host", "expiry"]
    )
    func continuedProcessingEndsWithTheSession(ending: String) async throws {
        let timer = FakeTimer()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: timer)
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )
        let task = FakeContinuedTask()

        sut.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")
        try await execution.submission(1).launched(task)
        switch ending {
        case "sidecar": sessions.perform(.end)
        case "host": sessions.end()
        default: timer.fire()
        }

        #expect(task.completions == 1)
        #expect(sut.request == .none)
        #expect(execution.requests.map(\.ends) == [1])
        #expect(execution.cancelled.isEmpty)
    }

    @Test("A session that ends before the system runs its task withdraws the submission, and a task run after that completes at once")
    func endBeforeLaunch() async throws {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )
        let late = FakeContinuedTask()

        sut.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")
        let submission = try await execution.submission(1)
        sessions.end()
        submission.launched(late)

        #expect(execution.cancelled == [submission.identifier])
        #expect(late.completions == 1)
        #expect(sut.request == .none)
        #expect(execution.requests.map(\.ends) == [1])
    }

    @Test("The person stopping the task in the system's progress, or the system expiring it, ends the session and reverts its changes")
    func continuedProcessingStopped() async throws {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let logLevels = LogLevelModel()
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )
        let task = FakeContinuedTask()

        sut.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")
        let submission = try await execution.submission(1)
        submission.launched(task)
        sessions.apply(to: "LogLevels", scope: .session(revert: { logLevels.perform(.reset) })) {
            logLevels.perform(.set("debug"))
            return true
        }
        submission.expired()

        #expect(sessions.snapshot == .inactive)
        #expect(sessions.auditLog.last?.event == .sessionEnded(.ended))
        #expect(logLevels.snapshot.level == "info")
        #expect(sut.request == .none)
        #expect(task.completions == 0)
    }

    @Test(
        "Where the continued task is unavailable (before iOS 26, off iOS), not permitted or refused, the session keeps the short request",
        arguments: [ContinuedProcessingRefusal.unsupported, .notPermitted, .refused("Immediate run ineligible")]
    )
    func continuedProcessingFallsBack(refusal: ContinuedProcessingRefusal) async throws {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let execution = FakeBackgroundExecution()
        execution.refusal = refusal
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )

        sut.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")
        _ = try await execution.submission(1)
        for await request in sut.$request.values where request == .backgroundTask {
            break
        }
        sessions.end()

        #expect(sut.request == .none)
        #expect(execution.requests.map(\.ends) == [1])
        #expect(execution.cancelled.isEmpty)
    }

    @Test("Without a prefix, startSession opens the session with the short request and submits nothing")
    func noPrefix() {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: nil,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )

        sut.startSession(duration: 60, title: "Debug session", subtitle: "Inspector")

        #expect(sessions.snapshot.isActive)
        #expect(sut.request == .backgroundTask)
        #expect(execution.submissions.isEmpty)
    }

    @Test("startSession while its task is submitted submits no second one, and while a sidecar's session is open uses that session")
    func startSessionOnce() async throws {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: Self.prefix,
            execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )

        sessions.perform(.open(duration: 60))
        let session = try #require(sessions.snapshot.session)
        sut.startSession(duration: 120, title: "Debug session", subtitle: "Inspector")
        sut.startSession(duration: 120, title: "Debug session", subtitle: "Inspector")
        let submission = try await execution.submission(1)

        #expect(sessions.snapshot.session == session)
        #expect(submission.identifier == "\(Self.prefix).\(session.id.uuidString)")
        #expect(execution.submissions.count == 1)
        #expect(execution.requests.count == 1)
    }

    @Test("The last sidecar disconnecting ends the session, reverting its changes, and ends the request once; with no session, nothing")
    func sidecarDisconnects() {
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FakeClock(Self.start), timer: FakeTimer())
        let logLevels = LogLevelModel()
        let disconnections = PassthroughSubject<Void, Never>()
        let execution = FakeBackgroundExecution()
        let sut = DebugDrawerBackgroundKeeper(
            sessions: sessions, sidecarDisconnections: disconnections.eraseToAnyPublisher(),
            continuedProcessingIdentifierPrefix: Self.prefix, execution: execution, clock: FakeClock(Self.start), progressTimer: FakeProgressTimer()
        )

        disconnections.send()
        let entriesBefore = sessions.auditLog.count
        sessions.perform(.open(duration: 60))
        sessions.apply(to: "LogLevels", scope: .session(revert: { logLevels.perform(.reset) })) {
            logLevels.perform(.set("debug"))
            return true
        }
        disconnections.send()

        #expect(entriesBefore == 0)
        #expect(sessions.snapshot == .inactive)
        #expect(sessions.auditLog.last?.event == .sessionEnded(.ended))
        #expect(logLevels.snapshot.level == "info")
        #expect(sut.request == .none)
        #expect(execution.requests.map(\.ends) == [1])
    }

    #if os(macOS)
        @Test("On the Mac the system's keeper holds a ProcessInfo activity while a session is open, and nothing after")
        func macActivity() {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = DebugDrawerBackgroundKeeper(sessions: sessions)

            sessions.perform(.open(duration: 60))
            let during = sut.request
            sessions.end()

            #expect(during == .activity)
            #expect(sut.request == .none)
        }
    #endif
}

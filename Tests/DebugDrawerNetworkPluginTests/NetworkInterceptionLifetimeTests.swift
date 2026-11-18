#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // These requests go through the URL protocol, which reads the process's one set of mock rules,
    // so they are part of the mock interception suite, which is serialized: no other test's rules
    // answer them. The protocol instance URLSession makes for a task holds that task (its `task`),
    // so a task that outlives its session's invalidation shows an instance that was never let go.
    extension NetworkMockInterceptionTests {
        @Test("Once its requests finish and the app's session is invalidated, no task is kept alive by the interception")
        func releasesTasks() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let observer = TaskLifetimeObserver()
            let session = URLSession(configuration: configuration, delegate: observer, delegateQueue: nil)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/lifetime"))
            let requestCount = 4
            for _ in 0 ..< requestCount {
                _ = try await session.data(from: url)
            }

            await observer.invalidate(session)

            let created = observer.createdCount
            let kept = observer.liveTasks
            #expect(created == requestCount)
            #expect(kept == 0)
        }
    }

    /// Counts the tasks a session creates and holds each weakly, and reports when the session has
    /// been invalidated.
    private final class TaskLifetimeObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var tasks: [WeakTask] = []
        private var invalidated: CheckedContinuation<Void, Never>?

        var createdCount: Int {
            lock.withLock { tasks.count }
        }

        var liveTasks: Int {
            lock.withLock { tasks.count { $0.task != nil } }
        }

        func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
            lock.withLock { tasks.append(WeakTask(task: task)) }
        }

        /// Lets `session`'s tasks finish, invalidates it, and returns once the session says it is
        /// invalid, by which time it has let go of every task.
        func invalidate(_ session: URLSession) async {
            await withCheckedContinuation { continuation in
                lock.withLock { invalidated = continuation }
                session.finishTasksAndInvalidate()
            }
        }

        func urlSession(_: URLSession, didBecomeInvalidWithError _: Error?) {
            let continuation = lock.withLock {
                defer { invalidated = nil }
                return invalidated
            }
            continuation?.resume()
        }
    }

    private struct WeakTask {
        weak var task: URLSessionTask?
    }
#endif

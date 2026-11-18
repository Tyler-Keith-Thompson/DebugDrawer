#if DEBUG
    import Foundation
    import os

    /// The app's URL sessions, each paired with the session its intercepted requests are sent on:
    /// one made from a copy of the app session's configuration, so a forwarded request gets the
    /// app's cookie storage, cache, credentials, timeouts, proxy and TLS settings, and an
    /// ephemeral session's requests stay out of the shared stores.
    ///
    /// A URL protocol learns its task but not the task's session, so `install()` notes each session
    /// as the app makes it, and ``forwardingSession(for:)`` finds a task's session by asking each
    /// noted one for its tasks.
    final class NetworkAppSessions: Sendable {
        static let shared = NetworkAppSessions()

        /// The app's sessions, newest first, held weakly: a session the app has let go of is
        /// dropped at the next registration. Behind a lock rather than in an actor: sessions are
        /// made on any thread, and registering one must not wait.
        private let sessions = OSAllocatedUnfairLock<[WeakSession]>(initialState: [])

        /// Sends the requests of a task no noted session holds: the shared session's before
        /// `install()` registered it, or one made before `install()`. Its default configuration
        /// has the shared cookie storage, cache and credentials, as the shared session has.
        private static let fallback = URLSession(configuration: .default, delegate: NetworkForwardingSession.shared, delegateQueue: nil)

        private init() {}

        /// Notes every session made from now on, and the shared session; a second call does
        /// nothing.
        static func install() {
            _ = installation
        }

        private static let installation: Void = {
            URLSession.swizzleSessionFactory()
            shared.register(.shared)
        }()

        /// Notes `session` as one of the app's, unless it is one of the plugin's own forwarding
        /// sessions.
        func register(_ session: URLSession) {
            guard session.delegate !== NetworkForwardingSession.shared else { return }
            sessions.withLock { sessions in
                sessions.removeAll { $0.session == nil }
                sessions.insert(WeakSession(session: session), at: 0)
            }
        }

        /// The session to send `task`'s request on: the forwarding session of the app session that
        /// made the task, made on first use, or the fallback when no noted session holds it.
        ///
        /// - Complexity: O(*s* × *t*) for *s* noted sessions and *t* tasks in flight in each.
        func forwardingSession(for task: URLSessionTask?) async -> URLSession {
            guard let task else { return Self.fallback }
            for session in sessions.withLock({ $0.compactMap(\.session) }) {
                let tasks = await session.allTasks
                if tasks.contains(where: { $0 === task }) {
                    return forwardingSession(of: session)
                }
            }
            return Self.fallback
        }

        /// The forwarding session of `appSession`, made from a copy of its configuration on first
        /// use and kept with it: when the app session goes, its forwarding session is invalidated
        /// once its requests finish.
        private func forwardingSession(of appSession: URLSession) -> URLSession {
            if let kept = NetworkForwardingSessionHolder.kept(by: appSession) {
                return kept.session
            }
            // Made outside any lock: making a session registers it (above), which takes the lock.
            let made = NetworkForwardingSessionHolder(
                session: URLSession(configuration: appSession.configuration, delegate: NetworkForwardingSession.shared, delegateQueue: nil)
            )
            return NetworkForwardingSessionHolder.keep(made, by: appSession).session
        }
    }

    private struct WeakSession {
        weak var session: URLSession?
    }

    /// Holds an app session's forwarding session for as long as the app session lives, as an
    /// object associated with it.
    private final class NetworkForwardingSessionHolder: Sendable {
        let session: URLSession

        /// The association's key: the address of a byte allocated once and never freed. Unsafe only
        /// in name: the address is never written through, and the pointer itself never changes.
        nonisolated(unsafe) private static let key = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
        /// Serializes `keep(_:by:)`, so two requests of a new session agree on one forwarding
        /// session.
        private static let keeping = OSAllocatedUnfairLock()

        init(session: URLSession) {
            self.session = session
        }

        deinit {
            session.finishTasksAndInvalidate()
        }

        static func kept(by appSession: URLSession) -> NetworkForwardingSessionHolder? {
            objc_getAssociatedObject(appSession, key) as? NetworkForwardingSessionHolder
        }

        /// Keeps `holder` with `appSession`, unless another was kept first, which is returned
        /// instead (and `holder` is let go, invalidating its session).
        static func keep(_ holder: NetworkForwardingSessionHolder, by appSession: URLSession) -> NetworkForwardingSessionHolder {
            keeping.withLock {
                if let kept = kept(by: appSession) {
                    return kept
                }
                objc_setAssociatedObject(appSession, key, holder, .OBJC_ASSOCIATION_RETAIN)
                return holder
            }
        }
    }

    // MARK: - URLSession factory swizzle

    extension URLSession {
        /// Swizzles the factory every session is made through
        /// (`+sessionWithConfiguration:delegate:delegateQueue:`, which Swift's initializers call),
        /// so each session made from now on is noted in ``NetworkAppSessions``.
        fileprivate static func swizzleSessionFactory() {
            guard let original = class_getClassMethod(self, NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:")),
                  let swizzled = class_getClassMethod(self, #selector(debugDrawerSession(configuration:delegate:delegateQueue:)))
            else { return }
            method_exchangeImplementations(original, swizzled)
        }

        @objc private class func debugDrawerSession(
            configuration: URLSessionConfiguration,
            delegate: (any URLSessionDelegate)?,
            delegateQueue: OperationQueue?
        ) -> URLSession {
            // After the swizzle, this calls the original factory.
            let session = debugDrawerSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
            NetworkAppSessions.shared.register(session)
            return session
        }
    }
#endif

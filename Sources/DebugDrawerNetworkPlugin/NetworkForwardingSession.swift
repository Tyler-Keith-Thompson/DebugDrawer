#if DEBUG
    import Foundation
    import os

    /// The delegate of every session intercepted requests are sent on (``NetworkAppSessions``),
    /// which hands each task's events to the `DebugNetworkProtocol` that started it, and lets go of
    /// that protocol when the task completes.
    ///
    /// Redirects and authentication challenges are not decided here: they are handed to the
    /// protocol, which asks the app's task, so the app's own session delegate decides them.
    final class NetworkForwardingSession: NSObject, Sendable {
        static let shared = NetworkForwardingSession()

        /// The protocol of each task in flight, by task. Behind a lock rather than in an actor:
        /// tasks start on the loading system's threads and report on their sessions' queues, and
        /// each hop to an actor would cost more than the lookup. Keyed by the task itself, as
        /// task identifiers repeat across sessions.
        private let protocols = OSAllocatedUnfairLock<[ObjectIdentifier: DebugNetworkProtocol]>(initialState: [:])

        override private init() {}

        /// Starts `request` on `session`, for `owner` to hear its events until it completes.
        ///
        /// - Returns: The task, which `owner` cancels when its own loading stops.
        func start(_ request: URLRequest, on session: URLSession, for owner: DebugNetworkProtocol) -> URLSessionDataTask {
            let task = session.dataTask(with: request)
            protocols.withLock { $0[ObjectIdentifier(task)] = owner }
            task.resume()
            return task
        }

        private func owner(of task: URLSessionTask) -> DebugNetworkProtocol? {
            protocols.withLock { $0[ObjectIdentifier(task)] }
        }
    }

    extension NetworkForwardingSession: URLSessionDataDelegate {
        func urlSession(
            _: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            owner(of: dataTask)?.forwardingDidReceive(response)
            completionHandler(.allow)
        }

        func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            owner(of: dataTask)?.forwardingDidLoad(data)
        }

        func urlSession(
            _: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            // Not followed here: the app's task is told of the redirect, and its session follows
            // it with a request of its own, which the protocol intercepts anew, or refuses it and
            // gets this response, which this task goes on to load.
            owner(of: task)?.forwardingWasRedirected(to: request, by: response)
            completionHandler(nil)
        }

        func urlSession(
            _: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard let owner = owner(of: task) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            owner.forwardingDidReceive(challenge, answer: completionHandler)
        }

        func urlSession(_: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void) {
            completionHandler(owner(of: task)?.forwardingNeedsNewBodyStream())
        }

        func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            owner(of: task)?.forwardingDidCollect(metrics)
        }

        func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let owner = protocols.withLock { $0.removeValue(forKey: ObjectIdentifier(task)) }
            owner?.forwardingDidComplete(error: error)
        }
    }
#endif

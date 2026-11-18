#if DEBUG
    import Foundation
    import os

    /// The one session every intercepted request is sent on through, which hands each task's
    /// events to the `DebugNetworkProtocol` that started it, and lets go of that protocol when the
    /// task completes.
    ///
    /// One session for the process, rather than one per request: a session holds its delegate
    /// until it is invalidated, and making a session costs more than the request it carries. The
    /// session lives as long as the app, and holds only the protocols of requests in flight.
    final class NetworkForwardingSession: NSObject, Sendable {
        static let shared = NetworkForwardingSession()

        /// The protocol of each task in flight, by task identifier. Behind a lock rather than in
        /// an actor: tasks start on the loading system's threads and report on the session's
        /// queue, and each hop to an actor would cost more than the lookup.
        private let protocols = OSAllocatedUnfairLock<[Int: DebugNetworkProtocol]>(initialState: [:])

        /// Made on first use, with the shared forwarder as its delegate. Its configuration gets
        /// the URL protocol too once `installNetwork()` swizzles configurations; the requests sent
        /// on it are marked handled, so the protocol passes them by.
        private static let session = URLSession(configuration: .default, delegate: shared, delegateQueue: nil)

        override private init() {}

        /// Starts `request` on the shared session, for `owner` to hear its events until it
        /// completes.
        ///
        /// - Returns: The task, which `owner` cancels when its own loading stops.
        func start(_ request: URLRequest, for owner: DebugNetworkProtocol) -> URLSessionDataTask {
            let task = Self.session.dataTask(with: request)
            protocols.withLock { $0[task.taskIdentifier] = owner }
            task.resume()
            return task
        }

        private func owner(of task: URLSessionTask) -> DebugNetworkProtocol? {
            protocols.withLock { $0[task.taskIdentifier] }
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

        func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            owner(of: task)?.forwardingDidCollect(metrics)
        }

        func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let owner = protocols.withLock { $0.removeValue(forKey: task.taskIdentifier) }
            owner?.forwardingDidComplete(error: error)
        }
    }
#endif

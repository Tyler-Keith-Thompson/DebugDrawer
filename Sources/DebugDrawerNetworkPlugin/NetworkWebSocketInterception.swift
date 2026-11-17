#if DEBUG
    import Foundation
    import ObjectiveC

    /// Records the app's WebSocket traffic, which never passes through a URL protocol: the
    /// connections `URLSession` creates, the messages and pings sent and received on them, and how
    /// each closed, into ``NetworkWebSocketRecorder/shared``.
    ///
    /// Only `install()` changes anything, once per process, and only public selectors of
    /// `NSURLSession` and of the class `URLSession`'s web socket tasks are: the three
    /// `webSocketTask…` factories, then `sendMessage:completionHandler:`,
    /// `receiveMessageWithCompletionHandler:`, `sendPingWithPongReceiveHandler:` and
    /// `cancelWithCloseCode:reason:`. Each replacement calls the implementation it replaced with
    /// the same arguments, and wraps a completion handler only to record what it is handed before
    /// handing the app the same message or error: nothing is consumed, reordered or delayed.
    enum NetworkWebSocketInterception {
        /// Starts recording WebSocket traffic; calling it again changes nothing.
        static func install() {
            _ = installation
        }

        /// The recorder the replacements write to.
        private static var recorder: NetworkWebSocketRecorder {
            .shared
        }

        // A static's initializer runs once, under a lock, however many threads ask for it.
        private static let installation: Void = {
            // `URLSessionWebSocketTask` is a class cluster: the tasks a session makes are of a
            // class that doesn't inherit from it, so its own methods are never called and
            // replacing them would record nothing. The class is taken from a task that is never
            // resumed, made before the factories are replaced so it isn't recorded, and only the
            // public selectors above are replaced on it.
            guard let probeURL = URL(string: "ws://127.0.0.1") else { return }
            let session = URLSession(configuration: .ephemeral)
            let taskClass: AnyClass = type(of: session.webSocketTask(with: probeURL))
            session.invalidateAndCancel()

            interceptCreation()
            interceptSend(on: taskClass)
            interceptReceive(on: taskClass)
            interceptPing(on: taskClass)
            interceptCancel(on: taskClass)
        }()

        // MARK: - Creation

        private typealias MakeWithURL = @convention(c) (URLSession, Selector, NSURL) -> URLSessionWebSocketTask
        private typealias MakeWithURLAndProtocols = @convention(c) (URLSession, Selector, NSURL, NSArray) -> URLSessionWebSocketTask
        private typealias MakeWithRequest = @convention(c) (URLSession, Selector, NSURLRequest) -> URLSessionWebSocketTask

        /// Records a connection for each task the factories make. The factories are
        /// `NSURLSession`'s own, which its subclasses inherit.
        private static func interceptCreation() {
            let withURL = NSSelectorFromString("webSocketTaskWithURL:")
            if let (method, original) = implementation(of: withURL, on: URLSession.self, as: MakeWithURL.self) {
                let replacement: @convention(block) (URLSession, NSURL) -> URLSessionWebSocketTask = { session, url in
                    opened(original(session, withURL, url), url: url as URL, protocols: [])
                }
                method_setImplementation(method, imp_implementationWithBlock(replacement))
            }

            let withProtocols = NSSelectorFromString("webSocketTaskWithURL:protocols:")
            if let (method, original) = implementation(of: withProtocols, on: URLSession.self, as: MakeWithURLAndProtocols.self) {
                let replacement: @convention(block) (URLSession, NSURL, NSArray) -> URLSessionWebSocketTask = { session, url, protocols in
                    opened(original(session, withProtocols, url, protocols), url: url as URL, protocols: protocols.compactMap { $0 as? String })
                }
                method_setImplementation(method, imp_implementationWithBlock(replacement))
            }

            let withRequest = NSSelectorFromString("webSocketTaskWithRequest:")
            if let (method, original) = implementation(of: withRequest, on: URLSession.self, as: MakeWithRequest.self) {
                let replacement: @convention(block) (URLSession, NSURLRequest) -> URLSessionWebSocketTask = { session, request in
                    let offered = request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") ?? ""
                    let protocols = offered.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    return opened(original(session, withRequest, request), url: request.url?.webSocketScheme, protocols: protocols)
                }
                method_setImplementation(method, imp_implementationWithBlock(replacement))
            }
        }

        /// Records `task` as a new connection, unless it is recorded already: the URL factories
        /// make their task with the request factory, which records it first.
        private static func opened(_ task: URLSessionWebSocketTask, url: URL?, protocols: [String]) -> URLSessionWebSocketTask {
            guard connectionID(of: task) == nil else { return task }
            let id = UUID()
            objc_setAssociatedObject(task, connectionKey, id as NSUUID, .OBJC_ASSOCIATION_RETAIN)
            recorder.open(NetworkWebSocketConnection(id: id, url: url?.absoluteString ?? "", protocols: protocols, opened: Date()))
            return task
        }

        // MARK: - Messages

        private typealias SendCompletion = @convention(block) (NSError?) -> Void
        private typealias Send = @convention(c) (URLSessionWebSocketTask, Selector, __NSURLSessionWebSocketMessage, SendCompletion?) -> Void
        private typealias ReceiveCompletion = @convention(block) (__NSURLSessionWebSocketMessage?, NSError?) -> Void
        private typealias Receive = @convention(c) (URLSessionWebSocketTask, Selector, ReceiveCompletion?) -> Void
        private typealias Ping = @convention(c) (URLSessionWebSocketTask, Selector, SendCompletion?) -> Void
        private typealias Cancel = @convention(c) (URLSessionWebSocketTask, Selector, Int, NSData?) -> Void

        /// Records each message the app sends when it sends it, and marks it failed if the send
        /// fails. Swift's `send(_:)`, async or with a completion handler, calls this method.
        private static func interceptSend(on taskClass: AnyClass) {
            let selector = NSSelectorFromString("sendMessage:completionHandler:")
            guard let (method, original) = implementation(of: selector, on: taskClass, as: Send.self) else { return }
            typealias Replacement = @convention(block) (URLSessionWebSocketTask, __NSURLSessionWebSocketMessage, SendCompletion?) -> Void
            let replacement: Replacement = { task, message, completion in
                guard let id = connectionID(of: task) else {
                    original(task, selector, message, completion)
                    return
                }
                let frame = NetworkWebSocketFrame(message, direction: .sent, timestamp: Date())
                recorder.record(frame, on: id)
                original(task, selector, message) { [weak task] error in
                    if let error {
                        recorder.fail(frame.id, on: id, error.localizedDescription)
                        ended(task, id, by: error)
                    }
                    completion?(error)
                }
            }
            class_replaceMethod(taskClass, selector, imp_implementationWithBlock(replacement), method_getTypeEncoding(method))
        }

        /// Records each message the app receives, and how the connection ended when a receive
        /// fails. Swift's `receive()`, async or with a completion handler, calls this method.
        private static func interceptReceive(on taskClass: AnyClass) {
            let selector = NSSelectorFromString("receiveMessageWithCompletionHandler:")
            guard let (method, original) = implementation(of: selector, on: taskClass, as: Receive.self) else { return }
            let replacement: @convention(block) (URLSessionWebSocketTask, ReceiveCompletion?) -> Void = { task, completion in
                guard let id = connectionID(of: task) else {
                    original(task, selector, completion)
                    return
                }
                original(task, selector) { [weak task] message, error in
                    if let message {
                        recorder.record(NetworkWebSocketFrame(message, direction: .received, timestamp: Date()), on: id)
                    }
                    if let error {
                        ended(task, id, by: error)
                    }
                    completion?(message, error)
                }
            }
            class_replaceMethod(taskClass, selector, imp_implementationWithBlock(replacement), method_getTypeEncoding(method))
        }

        /// Records each ping the app sends, and the pong that answers it.
        private static func interceptPing(on taskClass: AnyClass) {
            let selector = #selector(URLSessionWebSocketTask.sendPing(pongReceiveHandler:))
            guard let (method, original) = implementation(of: selector, on: taskClass, as: Ping.self) else { return }
            let replacement: @convention(block) (URLSessionWebSocketTask, SendCompletion?) -> Void = { task, completion in
                guard let id = connectionID(of: task) else {
                    original(task, selector, completion)
                    return
                }
                let ping = NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: Date())
                recorder.record(ping, on: id)
                original(task, selector) { [weak task] error in
                    if let error {
                        recorder.fail(ping.id, on: id, error.localizedDescription)
                        ended(task, id, by: error)
                    } else {
                        recorder.record(NetworkWebSocketFrame(direction: .received, kind: .pong, timestamp: Date()), on: id)
                    }
                    completion?(error)
                }
            }
            class_replaceMethod(taskClass, selector, imp_implementationWithBlock(replacement), method_getTypeEncoding(method))
        }

        /// Records the app's close, with its code and reason, before the task sends it.
        private static func interceptCancel(on taskClass: AnyClass) {
            let selector = #selector(URLSessionWebSocketTask.cancel(with:reason:))
            guard let (method, original) = implementation(of: selector, on: taskClass, as: Cancel.self) else { return }
            let replacement: @convention(block) (URLSessionWebSocketTask, Int, NSData?) -> Void = { task, code, reason in
                if let id = connectionID(of: task) {
                    let reason = NetworkWebSocketClose.reason(reason as Data?)
                    let close = NetworkWebSocketClose(side: .app, code: code, reason: reason, timestamp: Date())
                    recorder.end(id, .closed(close))
                }
                original(task, selector, code, reason)
            }
            class_replaceMethod(taskClass, selector, imp_implementationWithBlock(replacement), method_getTypeEncoding(method))
        }

        /// Records how the connection ended when a send, receive or ping fails with `error`: the
        /// server's close, with the code and reason the task read from its close frame; the app's
        /// cancel, when the task has no close code (`cancel(with:reason:)` recorded its own
        /// already); otherwise the error.
        private static func ended(_ task: URLSessionWebSocketTask?, _ id: NetworkWebSocketConnection.ID, by error: NSError) {
            let now = Date()
            if let task, task.closeCode != .invalid {
                let reason = NetworkWebSocketClose.reason(task.closeReason)
                let close = NetworkWebSocketClose(side: .server, code: task.closeCode.rawValue, reason: reason, timestamp: now)
                recorder.end(id, .closed(close))
            } else if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                recorder.end(id, .closed(NetworkWebSocketClose(side: .app, code: 0, reason: nil, timestamp: now)))
            } else {
                recorder.end(id, .failed(message: error.localizedDescription, at: now))
            }
        }

        // MARK: - Runtime

        /// The method `selector` names on `type`, its own or inherited, and its implementation as
        /// a function of type `Function`.
        private static func implementation<Function>(of selector: Selector, on type: AnyClass, as _: Function.Type) -> (Method, Function)? {
            guard let method = class_getInstanceMethod(type, selector) else { return nil }
            return (method, unsafeBitCast(method_getImplementation(method), to: Function.self))
        }

        /// The id of the connection recorded for `task`, kept on the task itself so it lives and
        /// goes with it; `nil` for a task made before `install()`.
        static func connectionID(of task: URLSessionWebSocketTask) -> NetworkWebSocketConnection.ID? {
            (objc_getAssociatedObject(task, connectionKey) as? NSUUID) as UUID?
        }

        /// A key no other associated object uses: the address of an object that lives for the
        /// process.
        private static var connectionKey: UnsafeRawPointer {
            UnsafeRawPointer(Unmanaged.passUnretained(AssociationKey.shared).toOpaque())
        }

        private final class AssociationKey: Sendable {
            static let shared = AssociationKey()
        }
    }

    extension URL {
        /// The URL with `http` as `ws` and `https` as `wss`: the URL factories hand the request
        /// factory their URL in its HTTP form, and the log shows the form the app passed.
        fileprivate var webSocketScheme: URL {
            guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
            switch components.scheme?.lowercased() {
            case "http": components.scheme = "ws"
            case "https": components.scheme = "wss"
            default: return self
            }
            return components.url ?? self
        }
    }
#endif

#if DEBUG
    import Foundation
    import ObjectiveC

    /// Records the app's WebSocket traffic, which never passes through a URL protocol: the
    /// connections `URLSession` creates, the messages and pings sent and received on them, and how
    /// each closed, into ``NetworkWebSocketRecorder/shared``.
    ///
    /// Only `install()` changes anything, until `uninstall()` puts it back, and only public selectors of
    /// `NSURLSession` and of the class `URLSession`'s web socket tasks are: the three
    /// `webSocketTask…` factories, then `sendMessage:completionHandler:`,
    /// `receiveMessageWithCompletionHandler:`, `sendPingWithPongReceiveHandler:` and
    /// `cancelWithCloseCode:reason:`. Each replacement calls the implementation it replaced with
    /// the same arguments, and wraps a completion handler only to record what it is handed before
    /// handing the app the same message or error: nothing is consumed, reordered or delayed.
    /// While uninstalled, a replacement other code kept in place calls straight through.
    enum NetworkWebSocketInterception {
        /// Starts recording WebSocket traffic; calling it again changes nothing.
        @MainActor
        static func install() {
            guard let taskClass else { return }
            interceptCreation()
            interceptSend(on: taskClass)
            interceptReceive(on: taskClass)
            interceptPing(on: taskClass)
            interceptCancel(on: taskClass)
        }

        /// Gives every replaced method its original implementation back, unless other code
        /// replaced it again since.
        @MainActor
        static func uninstall() {
            replacements.restore()
        }

        @MainActor private static let replacements = MethodReplacements()

        /// The recorder the replacements write to.
        private static var recorder: NetworkWebSocketRecorder {
            .shared
        }

        // `URLSessionWebSocketTask` is a class cluster: the tasks a session makes are of a class
        // that doesn't inherit from it, so its own methods are never called and replacing them
        // would record nothing. The class is taken, once, from a task that is never resumed, made
        // before the factories are first replaced so it isn't recorded, and only the public
        // selectors above are replaced on it.
        @MainActor private static let taskClass: AnyClass? = {
            guard let probeURL = URL(string: "ws://127.0.0.1") else { return nil }
            let session = URLSession(configuration: .ephemeral)
            let taskClass: AnyClass = type(of: session.webSocketTask(with: probeURL))
            session.invalidateAndCancel()
            return taskClass
        }()

        /// Whether the replacements record: installed, rather than left in place by an uninstall.
        private static var isRecording: Bool {
            !NetworkInterception.isUninstalled
        }

        // MARK: - Creation

        private typealias MakeWithURL = @convention(c) (URLSession, Selector, NSURL) -> URLSessionWebSocketTask
        private typealias MakeWithURLAndProtocols = @convention(c) (URLSession, Selector, NSURL, NSArray) -> URLSessionWebSocketTask
        private typealias MakeWithRequest = @convention(c) (URLSession, Selector, NSURLRequest) -> URLSessionWebSocketTask

        /// Records a connection for each task the factories make. The factories are
        /// `NSURLSession`'s own, which its subclasses inherit.
        @MainActor
        private static func interceptCreation() {
            // Every replacement block is `@Sendable`: made on the main actor, it runs on whatever
            // thread the app calls the method from, so it must not take the main actor's isolation.
            let withURL = NSSelectorFromString("webSocketTaskWithURL:")
            if let method = class_getInstanceMethod(URLSession.self, withURL) {
                replacements.replace(method) { implementation in
                    let original = unsafeBitCast(implementation, to: MakeWithURL.self)
                    let replacement: @Sendable @convention(block) (URLSession, NSURL) -> URLSessionWebSocketTask = { session, url in
                        let task = original(session, withURL, url)
                        return isRecording ? opened(task, url: url as URL, protocols: []) : task
                    }
                    return imp_implementationWithBlock(replacement)
                }
            }

            let withProtocols = NSSelectorFromString("webSocketTaskWithURL:protocols:")
            if let method = class_getInstanceMethod(URLSession.self, withProtocols) {
                replacements.replace(method) { implementation in
                    let original = unsafeBitCast(implementation, to: MakeWithURLAndProtocols.self)
                    typealias Factory = @Sendable @convention(block) (URLSession, NSURL, NSArray) -> URLSessionWebSocketTask
                    let replacement: Factory = { session, url, protocols in
                        let task = original(session, withProtocols, url, protocols)
                        guard isRecording else { return task }
                        return opened(task, url: url as URL, protocols: protocols.compactMap { $0 as? String })
                    }
                    return imp_implementationWithBlock(replacement)
                }
            }

            let withRequest = NSSelectorFromString("webSocketTaskWithRequest:")
            if let method = class_getInstanceMethod(URLSession.self, withRequest) {
                replacements.replace(method) { implementation in
                    let original = unsafeBitCast(implementation, to: MakeWithRequest.self)
                    let replacement: @Sendable @convention(block) (URLSession, NSURLRequest) -> URLSessionWebSocketTask = { session, request in
                        let task = original(session, withRequest, request)
                        guard isRecording else { return task }
                        let offered = request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") ?? ""
                        let protocols = offered.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        return opened(task, url: request.url?.webSocketScheme, protocols: protocols)
                    }
                    return imp_implementationWithBlock(replacement)
                }
            }
        }

        /// Records `task` as a new connection, unless it is recorded already (the URL factories
        /// make their task with the request factory, which records it first) or its host is
        /// bypassed (``NetworkBypass``).
        private static func opened(_ task: URLSessionWebSocketTask, url: URL?, protocols: [String]) -> URLSessionWebSocketTask {
            guard connectionID(of: task) == nil, !NetworkBypass.covers(url) else { return task }
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
        @MainActor
        private static func interceptSend(on taskClass: AnyClass) {
            let selector = NSSelectorFromString("sendMessage:completionHandler:")
            guard let method = ownMethod(selector, on: taskClass) else { return }
            replacements.replace(method) { implementation in
                let original = unsafeBitCast(implementation, to: Send.self)
                typealias Replacement = @Sendable @convention(block) (
                    URLSessionWebSocketTask, __NSURLSessionWebSocketMessage, SendCompletion?
                ) -> Void
                let replacement: Replacement = { task, message, completion in
                    guard isRecording, let id = connectionID(of: task) else {
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
                return imp_implementationWithBlock(replacement)
            }
        }

        /// Records each message the app receives, and how the connection ended when a receive
        /// fails. Swift's `receive()`, async or with a completion handler, calls this method.
        @MainActor
        private static func interceptReceive(on taskClass: AnyClass) {
            let selector = NSSelectorFromString("receiveMessageWithCompletionHandler:")
            guard let method = ownMethod(selector, on: taskClass) else { return }
            replacements.replace(method) { implementation in
                let original = unsafeBitCast(implementation, to: Receive.self)
                let replacement: @Sendable @convention(block) (URLSessionWebSocketTask, ReceiveCompletion?) -> Void = { task, completion in
                    guard isRecording, let id = connectionID(of: task) else {
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
                return imp_implementationWithBlock(replacement)
            }
        }

        /// Records each ping the app sends, and the pong that answers it.
        @MainActor
        private static func interceptPing(on taskClass: AnyClass) {
            let selector = #selector(URLSessionWebSocketTask.sendPing(pongReceiveHandler:))
            guard let method = ownMethod(selector, on: taskClass) else { return }
            replacements.replace(method) { implementation in
                let original = unsafeBitCast(implementation, to: Ping.self)
                let replacement: @Sendable @convention(block) (URLSessionWebSocketTask, SendCompletion?) -> Void = { task, completion in
                    guard isRecording, let id = connectionID(of: task) else {
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
                return imp_implementationWithBlock(replacement)
            }
        }

        /// Records the app's close, with its code and reason, before the task sends it.
        @MainActor
        private static func interceptCancel(on taskClass: AnyClass) {
            let selector = #selector(URLSessionWebSocketTask.cancel(with:reason:))
            guard let method = ownMethod(selector, on: taskClass) else { return }
            replacements.replace(method) { implementation in
                let original = unsafeBitCast(implementation, to: Cancel.self)
                let replacement: @Sendable @convention(block) (URLSessionWebSocketTask, Int, NSData?) -> Void = { task, code, reason in
                    if isRecording, let id = connectionID(of: task) {
                        let reason = NetworkWebSocketClose.reason(reason as Data?)
                        let close = NetworkWebSocketClose(side: .app, code: code, reason: reason, timestamp: Date())
                        recorder.end(id, .closed(close))
                    }
                    original(task, selector, code, reason)
                }
                return imp_implementationWithBlock(replacement)
            }
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

        /// The method `selector` names on `type` itself: one it inherits is first added to `type`
        /// with the inherited implementation, so replacing it changes `type` alone, as
        /// `class_replaceMethod` would, and putting it back leaves `type` running the inherited
        /// code.
        private static func ownMethod(_ selector: Selector, on type: AnyClass) -> Method? {
            guard let inherited = class_getInstanceMethod(type, selector) else { return nil }
            class_addMethod(type, selector, method_getImplementation(inherited), method_getTypeEncoding(inherited))
            return class_getInstanceMethod(type, selector)
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

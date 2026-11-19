#if DEBUG
    import Foundation

    // MARK: - URLProtocol interceptor

    /// Captures a request, then answers it from a mock rule, or sends it on the forwarding session
    /// of the app session that made it (``NetworkAppSessions``) and hands the app's task what that
    /// session hears, conditioned when a profile applies. Redirects and authentication challenges
    /// go to the app's task, so its own session delegate decides them.
    ///
    /// `@unchecked Sendable`: its state is kept on the thread it was started on
    /// (``NetworkClientThread``), where URL loading calls `startLoading()` and `stopLoading()`.
    /// What the forwarding session and a conditioned delivery report is handed to that thread
    /// before it touches the state or the client, so nothing races `stopLoading()`.
    final class DebugNetworkProtocol: URLProtocol, @unchecked Sendable {
        /// The request property that marks a request the plugin sends itself (the forwarded copy of
        /// one it captured), which it then leaves alone, so nothing is captured twice.
        static let handledKey = "com.debugdrawer.network.handled"

        /// Where `startLoading()` was called; the client is called there, and the state changed.
        private var clientThread: NetworkClientThread?
        /// Set by `stopLoading()`, after which the client hears nothing more.
        private var isStopped = false
        private var entryId: UUID?
        private var startTime: CFAbsoluteTime = 0
        /// The response body the log keeps: its first bytes, up to the limit `installNetwork()`
        /// set when the request started.
        private var capture = NetworkBodyCapture(limit: NetworkBodyCapture.limit.withLock { $0 })
        /// The whole body of a conditioned or redirected request, handed to the client once it
        /// has all arrived; unused otherwise, as the client gets each chunk as it comes.
        private var heldBody = Data()
        private var httpResponse: HTTPURLResponse?
        /// The redirect the server answered with, which the app's task is told of once the
        /// redirect's own response has arrived whole (``complete(error:)``).
        private var redirect: (request: URLRequest, response: HTTPURLResponse)?
        /// The authentication challenge the app's task was asked to answer, until loading stops.
        private var pendingChallenge: NetworkChallengeSender?
        private var dataTask: URLSessionDataTask?
        /// Times the request when a conditioning profile applies to it; `nil` leaves it alone.
        private var delivery: NetworkConditionedDelivery?
        /// The log's record of a conditioned request, completed when its delivery ends.
        private var conditionedEntry: NetworkEntry?
        /// Where the request is logged and finds its mocks and conditions: the route of the drawer
        /// that installed the plugin last when it started, kept for the request's whole life.
        private var route = NetworkRoute.shared
        /// The temporary file of a request body past the body limit, which the forwarded request
        /// streams from; held for as long as the request is, and removed with it. Set before the
        /// forwarded request starts, so its session may read it from its own queue.
        private var requestBodyFile: NetworkBodyFile?

        override static func canInit(with request: URLRequest) -> Bool {
            // A session made while capturing still lists the protocol once the plugin is
            // uninstalled; its requests then go to the system's protocols.
            guard !NetworkInterception.isUninstalled else { return false }
            guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
            // A host the app bypassed goes to the system's protocols, on the app's own session.
            guard !NetworkBypass.covers(request.url) else { return false }
            return request.url?.scheme == "http" || request.url?.scheme == "https"
        }

        override static func canInit(with task: URLSessionTask) -> Bool {
            // A WebSocket's handshake is an HTTP request, but answered through a data task here it
            // would never upgrade, and the socket would fail. Its traffic is recorded on the task
            // instead (NetworkWebSocketInterception).
            guard !(task is URLSessionWebSocketTask) else { return false }
            return super.canInit(with: task)
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            clientThread = .current
            route = NetworkInterception.route
            // An NSURLRequest's mutableCopy is an NSMutableURLRequest.
            guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
                client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
            }
            URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

            let url = request.url?.absoluteString ?? ""
            // httpBody is often nil: URLSession moves it to httpBodyStream itself. Reading a
            // stream uses it up, so the forwarded request carries the bytes read instead.
            let body: NetworkRequestBody?
            do {
                body = try NetworkRequestBody.read(from: request, limit: capture.limit)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            body?.forward(in: mutable)
            if case let .file(file) = body?.source {
                requestBodyFile = file
            }
            let entry = NetworkEntry(
                timestamp: Date(),
                method: request.httpMethod ?? "GET",
                url: url,
                host: request.url?.host ?? "",
                path: request.url?.path ?? "/",
                requestHeaders: request.allHTTPHeaderFields ?? [:],
                requestBody: body?.recorded,
                requestBodySize: body?.size,
                isComplete: false,
                replayOf: request.replayOf
            )
            entryId = entry.id
            startTime = CFAbsoluteTimeGetCurrent()

            let answer = request.url.flatMap { route.mocks.answer(method: entry.method, url: $0) }
            if let requestURL = request.url, let plan = route.conditions.plan(for: requestURL) {
                condition(entry, to: requestURL, by: plan, answer: answer, network: mutable as URLRequest)
                return
            }

            if let requestURL = request.url, let answer {
                respond(with: answer, to: requestURL, entry: entry)
                return
            }

            Task { @MainActor [route] in
                route.store.recordStart(entry)
            }

            startNetwork(mutable as URLRequest)
        }

        override func stopLoading() {
            isStopped = true
            delivery?.cancel()
            dataTask?.cancel()
            pendingChallenge?.cancelUnanswered()
            pendingChallenge = nil
        }

        /// Sends `request` on the forwarding session of the app session that made this task, once
        /// that session is found, unless loading stopped meanwhile.
        private func startNetwork(_ request: URLRequest) {
            let appTask = task
            let send: @Sendable () async -> Void = { [self] in
                let session = await NetworkAppSessions.shared.forwardingSession(for: appTask)
                onClientThread { [self] in
                    guard !isStopped else {
                        complete(error: URLError(.cancelled))
                        return
                    }
                    dataTask = NetworkForwardingSession.shared.start(request, on: session, for: self)
                }
            }
            Task(operation: send)
        }

        /// Runs `body` on the thread this protocol was started on, after the work handed there
        /// before it.
        private func onClientThread(_ body: @escaping @Sendable () -> Void) {
            clientThread?.perform(body)
        }

        /// Conditions the request by `plan`: the latency first, then the failure the plan decided,
        /// or the mock's answer, or the network's, read whole and then delivered at the plan's
        /// bandwidth. The log shows the request in progress meanwhile, marked with the profile.
        private func condition(_ entry: NetworkEntry, to url: URL, by plan: NetworkConditionPlan, answer: NetworkMockAnswer?, network: URLRequest) {
            var entry = entry
            entry.conditionEffect = plan.effect
            entry.mockRuleName = plan.effect.failure == nil ? answer?.ruleName : nil
            conditionedEntry = entry
            Task { @MainActor [entry, route] in
                route.store.recordStart(entry)
            }
            let delivery = NetworkConditionedDelivery(plan: plan) { [weak self] event in
                self?.onClientThread { [weak self] in
                    self?.forward(event)
                }
            }
            self.delivery = delivery
            delivery.start(url: url) { [weak self] in
                guard let self else { return }
                guard let answer else {
                    startNetwork(network)
                    return
                }
                let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)
                guard let response else {
                    delivery.fail(URLError(.badServerResponse) as NSError)
                    return
                }
                // What the log records as the body, as the network's would be. Appended on the
                // client thread, where the rest of the capture is.
                onClientThread { [self] in
                    capture.append(answer.body)
                }
                delivery.deliver(response, body: answer.body)
            }
        }

        /// Tells the client of a conditioned request's event, and completes its log record at the
        /// end.
        private func forward(_ event: NetworkConditionedDelivery.Event) {
            guard !isStopped else { return }
            switch event {
            case let .response(response):
                httpResponse = response as? HTTPURLResponse
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            case let .data(data):
                client?.urlProtocol(self, didLoad: data)
            case .finished:
                client?.urlProtocolDidFinishLoading(self)
                recordConditionedCompletion(error: nil)
            case let .failed(error):
                client?.urlProtocol(self, didFailWithError: error)
                recordConditionedCompletion(error: error)
            }
        }

        private func recordConditionedCompletion(error: NSError?) {
            guard let entry = conditionedEntry else { return }
            let completion = NetworkCompletion(
                statusCode: httpResponse?.statusCode,
                headers: httpResponse?.allHeaderFields as? [String: String],
                body: httpResponse == nil ? nil : capture.body,
                duration: CFAbsoluteTimeGetCurrent() - startTime,
                error: error?.localizedDescription
            )
            Task { @MainActor [route] in
                route.store.recordCompletion(id: entry.id, completion)
            }
        }

        /// Answers the request from a mock rule, as the network would: the response, the body and
        /// the finish, with no request made. The log gets the request complete, marked with the
        /// rule's name, in one record, so it never shows a mocked request in progress.
        private func respond(with answer: NetworkMockAnswer, to url: URL, entry: NetworkEntry) {
            let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)
            guard let response else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            // A mock's answer never enters the app's cache, so the next request asks the rules
            // again.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !answer.body.isEmpty {
                client?.urlProtocol(self, didLoad: answer.body)
            }
            client?.urlProtocolDidFinishLoading(self)

            var entry = entry
            entry.mockRuleName = answer.ruleName
            entry.statusCode = answer.status
            entry.responseHeaders = answer.headers
            capture.append(answer.body)
            entry.response = capture.body
            entry.duration = CFAbsoluteTimeGetCurrent() - startTime
            entry.isComplete = true
            Task { @MainActor [entry, route] in
                route.store.recordStart(entry)
            }
        }
    }

    // The forwarding session's events for this protocol's request (NetworkForwardingSession), each
    // reported on the session's queue and handled on the client thread.
    extension DebugNetworkProtocol {
        func forwardingDidReceive(_ response: URLResponse) {
            onClientThread { [self] in
                httpResponse = response as? HTTPURLResponse
                // A conditioned request's answer is read whole, then delivered at the profile's
                // pace; a redirect's, whole with the redirect. Not stored by the app's loading:
                // the forwarding session, whose configuration is the app session's, has already
                // stored it in the app's cache.
                if delivery == nil, redirect == nil, !isStopped {
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
            }
        }

        func forwardingDidLoad(_ data: Data) {
            onClientThread { [self] in
                capture.append(data)
                if delivery != nil || redirect != nil {
                    heldBody.append(data)
                } else if !isStopped {
                    client?.urlProtocol(self, didLoad: data)
                }
            }
        }

        /// Keeps the redirect to `request` for the app's task, which is told of it with its
        /// response once that has arrived; the forwarding session goes on to load that response.
        func forwardingWasRedirected(to request: URLRequest, by response: HTTPURLResponse) {
            onClientThread { [self] in
                // The redirect's request is the app's to send: unmarked, so this protocol captures
                // it as a request of its own.
                guard let unmarked = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return }
                URLProtocol.removeProperty(forKey: Self.handledKey, in: unmarked)
                redirect = (unmarked as URLRequest, response)
            }
        }

        /// Asks the app's task to answer `challenge`, and hands its session delegate's decision to
        /// the forwarded request through `answer`.
        func forwardingDidReceive(_ challenge: URLAuthenticationChallenge, answer: @escaping NetworkChallengeSender.Answer) {
            onClientThread { [self] in
                guard !isStopped, let client else {
                    answer(.cancelAuthenticationChallenge, nil)
                    return
                }
                let sender = NetworkChallengeSender(answer: answer)
                pendingChallenge = sender
                client.urlProtocol(self, didReceive: URLAuthenticationChallenge(authenticationChallenge: challenge, sender: sender))
            }
        }

        /// A new stream of the request's body, for the session to send it over again (an
        /// authentication challenge); `nil` when the body isn't a stream.
        func forwardingNeedsNewBodyStream() -> InputStream? {
            requestBodyFile?.stream
        }

        func forwardingDidCollect(_ metrics: URLSessionTaskMetrics) {
            onClientThread { [self] in
                guard let id = entryId, let timing = NetworkTimingMetrics(metrics) else { return }
                Task { @MainActor [route] in
                    route.store.recordMetrics(id: id, metrics: timing)
                }
            }
        }

        func forwardingDidComplete(error: Error?) {
            onClientThread { [self] in
                complete(error: error)
            }
        }

        /// Ends the request: completes its log record and tells the client, or hands a conditioned
        /// request's answer to its delivery. Called on the client thread.
        private func complete(error: Error?) {
            if let redirect, error == nil, let httpResponse {
                // URL loading asks the app's delegate about a redirect on a queue of its own, and
                // adds what it hears after the delegate chose to follow to the target's body. So
                // the redirect, its response and its body go over together, before the delegate
                // is asked: loading keeps them if the delegate refuses, and drops them if it
                // follows. A conditioned request's latency has been waited out; its redirect's
                // short body isn't paced.
                delivery?.cancel()
                record(error: nil)
                guard !isStopped else { return }
                client?.urlProtocol(self, wasRedirectedTo: redirect.request, redirectResponse: redirect.response)
                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                if !heldBody.isEmpty {
                    client?.urlProtocol(self, didLoad: heldBody)
                }
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            if let delivery {
                // The delivery tells the client, and completes the log record when it ends.
                if let error {
                    delivery.fail(error as NSError)
                } else if let httpResponse {
                    delivery.deliver(httpResponse, body: heldBody)
                } else {
                    delivery.fail(URLError(.badServerResponse) as NSError)
                }
                return
            }
            record(error: error)
            guard !isStopped else { return }
            if let error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        /// Completes the request's log record with its response, the body kept, and `error`.
        private func record(error: Error?) {
            let completion = NetworkCompletion(
                statusCode: httpResponse?.statusCode,
                headers: httpResponse?.allHeaderFields as? [String: String],
                body: capture.body,
                duration: CFAbsoluteTimeGetCurrent() - startTime,
                error: error?.localizedDescription
            )
            guard let id = entryId else { return }
            Task { @MainActor [route] in
                route.store.recordCompletion(id: id, completion)
            }
        }
    }
#endif

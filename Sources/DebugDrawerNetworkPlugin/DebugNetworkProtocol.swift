#if DEBUG
    import Foundation

    // MARK: - URLProtocol interceptor

    final class DebugNetworkProtocol: URLProtocol, @unchecked Sendable {
        private static let handledKey = "com.debugdrawer.network.handled"

        private var entryId: UUID?
        private var startTime: CFAbsoluteTime = 0
        /// The response body the log keeps: its first bytes, up to the limit `installNetwork()`
        /// set when the request started.
        private var capture = NetworkBodyCapture(limit: NetworkBodyCapture.limit.withLock { $0 })
        /// A conditioned request's whole body, which its delivery hands the client once it has
        /// all arrived; unused otherwise, as the client gets each chunk as it comes.
        private var deliveryBody = Data()
        private var httpResponse: HTTPURLResponse?
        private var dataTask: URLSessionDataTask?
        /// Times the request when a conditioning profile applies to it; `nil` leaves it alone.
        private var delivery: NetworkConditionedDelivery?
        /// The log's record of a conditioned request, completed when its delivery ends.
        private var conditionedEntry: NetworkEntry?
        /// The temporary file of a request body past the body limit, which the forwarded request
        /// streams from; held for as long as the request is, and removed with it.
        private var requestBodyFile: NetworkBodyFile?

        override static func canInit(with request: URLRequest) -> Bool {
            guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
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

            let answer = request.url.flatMap { NetworkMockRules.shared.answer(method: entry.method, url: $0) }
            if let requestURL = request.url, let plan = NetworkConditions.shared.plan(for: requestURL) {
                condition(entry, to: requestURL, by: plan, answer: answer, network: mutable as URLRequest)
                return
            }

            if let requestURL = request.url, let answer {
                respond(with: answer, to: requestURL, entry: entry)
                return
            }

            Task { @MainActor in
                NetworkStore.shared.recordStart(entry)
            }

            startNetwork(mutable as URLRequest)
        }

        override func stopLoading() {
            // Cancelled first: once it returns no step of the delivery runs, so none starts the
            // data task after it is read here, and the client hears nothing more.
            delivery?.cancel()
            dataTask?.cancel()
        }

        private func startNetwork(_ request: URLRequest) {
            dataTask = NetworkForwardingSession.shared.start(request, for: self)
        }

        /// Conditions the request by `plan`: the latency first, then the failure the plan decided,
        /// or the mock's answer, or the network's, read whole and then delivered at the plan's
        /// bandwidth. The log shows the request in progress meanwhile, marked with the profile.
        private func condition(_ entry: NetworkEntry, to url: URL, by plan: NetworkConditionPlan, answer: NetworkMockAnswer?, network: URLRequest) {
            var entry = entry
            entry.conditionEffect = plan.effect
            entry.mockRuleName = plan.effect.failure == nil ? answer?.ruleName : nil
            conditionedEntry = entry
            Task { @MainActor [entry] in
                NetworkStore.shared.recordStart(entry)
            }
            let delivery = NetworkConditionedDelivery(plan: plan) { [weak self] event in
                self?.forward(event)
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
                // What the log records as the body, as the network's would be.
                capture.append(answer.body)
                delivery.deliver(response, body: answer.body)
            }
        }

        /// Tells the client of a conditioned request's event, and completes its log record at the
        /// end.
        private func forward(_ event: NetworkConditionedDelivery.Event) {
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
            Task { @MainActor in
                NetworkStore.shared.recordCompletion(id: entry.id, completion)
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
            Task { @MainActor [entry] in
                NetworkStore.shared.recordStart(entry)
            }
        }
    }

    // The forwarding session's events for this protocol's request (NetworkForwardingSession).
    extension DebugNetworkProtocol {
        func forwardingDidReceive(_ response: URLResponse) {
            httpResponse = response as? HTTPURLResponse
            // A conditioned request's answer is read whole, then delivered at the profile's pace.
            if delivery == nil {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
        }

        func forwardingDidLoad(_ data: Data) {
            capture.append(data)
            if delivery == nil {
                client?.urlProtocol(self, didLoad: data)
            } else {
                deliveryBody.append(data)
            }
        }

        /// A new stream of the request's body, for the session to send it over again (a redirect,
        /// an authentication challenge); `nil` when the body isn't a stream.
        func forwardingNeedsNewBodyStream() -> InputStream? {
            requestBodyFile?.stream
        }

        func forwardingDidCollect(_ metrics: URLSessionTaskMetrics) {
            guard let id = entryId, let timing = NetworkTimingMetrics(metrics) else { return }
            Task { @MainActor in
                NetworkStore.shared.recordMetrics(id: id, metrics: timing)
            }
        }

        func forwardingDidComplete(error: Error?) {
            if let delivery {
                // The delivery tells the client, and completes the log record when it ends.
                if let error {
                    delivery.fail(error as NSError)
                } else if let httpResponse {
                    delivery.deliver(httpResponse, body: deliveryBody)
                } else {
                    delivery.fail(URLError(.badServerResponse) as NSError)
                }
                return
            }
            let completion = NetworkCompletion(
                statusCode: httpResponse?.statusCode,
                headers: httpResponse?.allHeaderFields as? [String: String],
                body: capture.body,
                duration: CFAbsoluteTimeGetCurrent() - startTime,
                error: error?.localizedDescription
            )
            let id = entryId

            Task { @MainActor in
                if let id {
                    NetworkStore.shared.recordCompletion(id: id, completion)
                }
            }

            if let error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    // MARK: - URLSessionConfiguration swizzle

    extension URLSessionConfiguration {
        /// Swizzle the `protocolClasses` getter so every new `URLSessionConfiguration`
        /// (`.default`, `.ephemeral`, custom) automatically includes our interceptor.
        /// This is the same technique FLEX/Netfox use — `URLProtocol.registerClass`
        /// alone only covers `URLSession.shared`.
        static func swizzleProtocolClasses() {
            guard let original = class_getInstanceMethod(self, #selector(getter: protocolClasses)),
                  let swizzled = class_getInstanceMethod(self, #selector(getter: debugDrawerProtocolClasses))
            else { return }
            method_exchangeImplementations(original, swizzled)
        }

        @objc private var debugDrawerProtocolClasses: [AnyClass]? {
            // After the swizzle, this calls the original getter
            guard var classes = self.debugDrawerProtocolClasses else {
                return [DebugNetworkProtocol.self]
            }
            if !classes.contains(where: { $0 == DebugNetworkProtocol.self }) {
                classes.insert(DebugNetworkProtocol.self, at: 0)
            }
            return classes
        }
    }
#endif

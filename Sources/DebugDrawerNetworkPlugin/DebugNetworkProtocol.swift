#if DEBUG
    import Foundation

    // MARK: - URLProtocol interceptor

    final class DebugNetworkProtocol: URLProtocol, @unchecked Sendable {
        private static let handledKey = "com.debugdrawer.network.handled"

        private var entryId: UUID?
        private var startTime: CFAbsoluteTime = 0
        private var responseData = Data()
        private var httpResponse: HTTPURLResponse?
        private var dataTask: URLSessionDataTask?
        /// Times the request when a conditioning profile applies to it; `nil` leaves it alone.
        private var delivery: NetworkConditionedDelivery?
        /// The log's record of a conditioned request, completed when its delivery ends.
        private var conditionedEntry: NetworkEntry?

        override static func canInit(with request: URLRequest) -> Bool {
            guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
            return request.url?.scheme == "http" || request.url?.scheme == "https"
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
            // httpBody is often nil — URLSession moves it to httpBodyStream internally
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let bufferSize = 4096
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate(); stream.close() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    guard read > 0 else { break }
                    data.append(buffer, count: read)
                }
                if !data.isEmpty { body = data }
            }
            let entry = NetworkEntry(
                timestamp: Date(),
                method: request.httpMethod ?? "GET",
                url: url,
                host: request.url?.host ?? "",
                path: request.url?.path ?? "/",
                requestHeaders: request.allHTTPHeaderFields ?? [:],
                requestBody: body,
                isComplete: false
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
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            dataTask = session.dataTask(with: request)
            dataTask?.resume()
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
                responseData = answer.body
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
                body: httpResponse == nil ? nil : responseData,
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
            entry.responseBody = answer.body
            entry.duration = CFAbsoluteTimeGetCurrent() - startTime
            entry.isComplete = true
            Task { @MainActor [entry] in
                NetworkStore.shared.recordStart(entry)
            }
        }
    }

    extension DebugNetworkProtocol: URLSessionDataDelegate {
        func urlSession(
            _: URLSession,
            dataTask _: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            httpResponse = response as? HTTPURLResponse
            // A conditioned request's answer is read whole, then delivered at the profile's pace.
            if delivery == nil {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            completionHandler(.allow)
        }

        func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
            responseData.append(data)
            if delivery == nil {
                client?.urlProtocol(self, didLoad: data)
            }
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            guard let id = entryId, let timing = NetworkTimingMetrics(metrics) else { return }
            Task { @MainActor in
                NetworkStore.shared.recordMetrics(id: id, metrics: timing)
            }
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
            if let delivery {
                // The delivery tells the client, and completes the log record when it ends.
                if let error {
                    delivery.fail(error as NSError)
                } else if let httpResponse {
                    delivery.deliver(httpResponse, body: responseData)
                } else {
                    delivery.fail(URLError(.badServerResponse) as NSError)
                }
                return
            }
            let completion = NetworkCompletion(
                statusCode: httpResponse?.statusCode,
                headers: httpResponse?.allHeaderFields as? [String: String],
                body: responseData,
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

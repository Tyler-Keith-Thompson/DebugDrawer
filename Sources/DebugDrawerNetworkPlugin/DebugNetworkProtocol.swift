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

            Task { @MainActor in
                NetworkStore.shared.recordStart(entry)
            }

            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            dataTask = session.dataTask(with: mutable as URLRequest)
            dataTask?.resume()
        }

        override func stopLoading() {
            dataTask?.cancel()
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
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            completionHandler(.allow)
        }

        func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
            responseData.append(data)
            client?.urlProtocol(self, didLoad: data)
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            guard let id = entryId, let timing = NetworkTimingMetrics(metrics) else { return }
            Task { @MainActor in
                NetworkStore.shared.recordMetrics(id: id, metrics: timing)
            }
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
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

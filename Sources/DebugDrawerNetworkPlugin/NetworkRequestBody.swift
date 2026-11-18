#if DEBUG
    import Foundation

    /// A request's body as the protocol takes it from the app's request: the copy the log keeps,
    /// cut to the body limit, and the whole body, which the forwarded request carries.
    ///
    /// A body the app streamed can be read only once, so reading it for the log uses it up; the
    /// forwarded request then carries the bytes read rather than the app's stream.
    struct NetworkRequestBody {
        /// Where the forwarded request's body comes from.
        enum Source {
            /// The body in memory.
            case data(Data)
            /// The body in a temporary file, removed when the file's last owner goes away.
            case file(NetworkBodyFile)
        }

        /// The body as the log keeps it: all of it, or its first bytes when it was larger than
        /// the limit; `nil` when the body was empty.
        let recorded: Data?
        /// How many bytes the body had, all told.
        let size: Int
        /// The whole body, for the forwarded request.
        let source: Source

        /// The body of `request`: its `httpBody`, or its `httpBodyStream` read to the end; `nil`
        /// when it has neither.
        ///
        /// - Parameters:
        ///   - request: The app's request. Its stream, if it has one, is read to the end and
        ///     can't be read again.
        ///   - limit: The most bytes of the body the log keeps.
        /// - Throws: The stream's error when it fails, or the file system's when a body past
        ///   `limit` can't be written to a temporary file.
        /// - Complexity: O(*n*) in the body's size.
        static func read(from request: URLRequest, limit: Int) throws -> NetworkRequestBody? {
            if let data = request.httpBody {
                var capture = NetworkBodyCapture(limit: limit)
                capture.append(data)
                return NetworkRequestBody(capture, source: .data(data))
            }
            guard let stream = request.httpBodyStream else { return nil }
            return try NetworkRequestBody(reading: stream, limit: limit)
        }

        private init(_ capture: NetworkBodyCapture, source: Source) {
            recorded = capture.size == 0 ? nil : capture.keptData
            size = capture.size
            self.source = source
        }

        // The body is held once, whatever its size. While it fits under the limit it stays in
        // memory, in the capture, which the log's copy and the forwarded body then share. Past
        // the limit, the bytes read so far and every byte after them go to a temporary file the
        // forwarded request streams from, and memory holds only the log's first `limit` bytes,
        // so an upload of any size costs no more than the limit the log already allows. Reading
        // a large upload whole into memory, the simpler way, would hold it a second time beside
        // the app's own copy, and a file the app streams would be loaded whole.
        private init(reading stream: InputStream, limit: Int) throws {
            var capture = NetworkBodyCapture(limit: limit)
            var file: NetworkBodyFile?
            var handle: FileHandle?
            defer { try? handle?.close() }
            let bufferSize = 65536
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            stream.open()
            defer { stream.close() }
            // Read until the end (0) rather than while `hasBytesAvailable`: a stream the app is
            // still writing to (a bound pair) may have no bytes yet, without having ended.
            while true {
                let count = stream.read(buffer, maxLength: bufferSize)
                if count < 0 { throw stream.streamError ?? URLError(.cannotOpenFile) }
                if count == 0 { break }
                let chunk = Data(bytes: buffer, count: count)
                if handle == nil, capture.size + count > limit {
                    let spooled = try NetworkBodyFile(contents: capture.data)
                    file = spooled
                    handle = try FileHandle(forWritingTo: spooled.url)
                    try handle?.seekToEnd()
                }
                try handle?.write(contentsOf: chunk)
                capture.append(chunk)
            }
            try handle?.close()
            handle = nil
            self.init(capture, source: file.map(Source.file) ?? .data(capture.data))
        }

        /// Gives `request` this body, whole, in place of the one it had.
        ///
        /// A body in a file goes as a stream, with a `Content-Length` of its size unless the
        /// request has one, so the server gets a body of known length either way, as it does for
        /// a body in memory.
        func forward(in request: NSMutableURLRequest) {
            switch source {
            case let .data(data):
                // Setting the body clears the request's stream, which is used up.
                request.httpBody = data
            case let .file(file):
                request.httpBodyStream = file.stream
                if request.value(forHTTPHeaderField: "Content-Length") == nil {
                    request.setValue(String(size), forHTTPHeaderField: "Content-Length")
                }
            }
        }
    }
#endif

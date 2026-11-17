#if DEBUG
    import Foundation

    // The mark is a URL protocol property rather than a header: a property lives on the request
    // object inside the process, and the URL loading system never puts it on the wire, so there is
    // nothing to strip before the request leaves and nothing a server could see.
    extension URLRequest {
        /// The key of the property that names the captured request a replay resends.
        private static let replayKey = "com.debugdrawer.network.replayOf"

        /// This request, marked as a replay of the captured request with `id`, so the log links
        /// the two.
        func markedAsReplay(of id: UUID) -> URLRequest {
            // An NSURLRequest's mutableCopy is an NSMutableURLRequest.
            guard let mutable = (self as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return self }
            URLProtocol.setProperty(id.uuidString, forKey: Self.replayKey, in: mutable)
            return mutable as URLRequest
        }

        /// The id of the captured request this request replays, or `nil` when it isn't a replay.
        var replayOf: UUID? {
            (URLProtocol.property(forKey: Self.replayKey, in: self) as? String).flatMap(UUID.init(uuidString:))
        }
    }
#endif

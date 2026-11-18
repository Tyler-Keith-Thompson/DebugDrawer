#if DEBUG
    import DebugDrawer
    import Foundation

    extension NetworkEntry {
        /// The response body with the values `redaction` calls sensitive masked, as it leaves the
        /// log (a HAR file, the session on disk) or shows before it is revealed; `nil` when there
        /// is none.
        ///
        /// A body the log kept only the first bytes of is no longer whole JSON, so the rules
        /// can't be read against it: it is `nil` too whenever `redaction` masks any JSON key or
        /// path, rather than written with its values showing.
        func redactedResponseBody(_ redaction: DebugDrawerRedaction) -> Data? {
            guard let body = responseBody else { return nil }
            if isResponseBodyTruncated, !redaction.keyPatterns.isEmpty || !redaction.jsonPaths.isEmpty {
                return nil
            }
            return redaction.redacting(json: body)
        }
    }
#endif

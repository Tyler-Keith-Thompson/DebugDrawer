#if DEBUG
    import Foundation
    import os
    import UniformTypeIdentifiers

    /// What a mock rule answers a request with, ready to send.
    struct NetworkMockAnswer: Equatable, Sendable {
        /// The name of the rule that answered, which the log shows.
        let ruleName: String
        let status: Int
        /// The headers, `Content-Length` and `Content-Type` included.
        let headers: [String: String]
        let body: Data
    }

    /// The rules the URL protocol answers from: the enabled ones that compile, in order, each with
    /// its response ready to send.
    ///
    /// The URL loading system asks from its own threads and the drawer changes the rules on the
    /// main actor, so the rules sit behind a lock rather than in an actor, which would make each
    /// request wait for a hop. `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18;
    /// switch to `Mutex` once iOS 18 is the minimum.
    final class NetworkMockRules: Sendable {
        /// The rules `DebugNetworkProtocol` answers from. Empty until `installNetwork()` loads the
        /// saved ones.
        static let shared = NetworkMockRules()

        fileprivate struct ActiveRule: Sendable {
            let matcher: CompiledNetworkMockMatcher
            let answer: NetworkMockAnswer
        }

        private let active = OSAllocatedUnfairLock<[ActiveRule]>(initialState: [])

        /// Answers from `rules` from now on: the enabled ones, in order, less any whose pattern
        /// doesn't compile.
        ///
        /// - Parameters:
        ///   - rules: The rules, the first to match answering.
        ///   - body: The contents of a body file, by name; `nil` sends an empty body.
        func activate(_ rules: [NetworkMockRule], body: (String) -> Data?) {
            let compiled = rules.filter(\.isEnabled).compactMap { rule -> ActiveRule? in
                guard let matcher = try? CompiledNetworkMockMatcher(rule.matcher) else { return nil }
                return ActiveRule(matcher: matcher, answer: rule.answer(body: body))
            }
            active.withLock { $0 = compiled }
        }

        /// The answer of the first active rule that matches a request of `method` to `url`, or
        /// `nil` when none does.
        ///
        /// - Complexity: O(*n*) in the number of active rules.
        func answer(method: String, url: URL) -> NetworkMockAnswer? {
            active.withLock { rules in
                rules.first { $0.matcher.matches(method: method, url: url) }?.answer
            }
        }
    }

    extension NetworkMockRule {
        /// The rule's response with its body read and its headers completed.
        fileprivate func answer(body read: (String) -> Data?) -> NetworkMockAnswer {
            let body: Data
            var fileType: String?
            switch response.body {
            case .empty:
                body = Data()
            case let .text(text):
                body = Data(text.utf8)
            case let .file(name):
                body = read(name) ?? Data()
                fileType = UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType
            }
            return NetworkMockAnswer(
                ruleName: name,
                status: response.status,
                headers: response.headerFields(bodyLength: body.count, fileType: fileType),
                body: body
            )
        }
    }

    extension NetworkMockRule.Response {
        /// The headers sent: the rule's own, its content type in place of theirs (or, with neither,
        /// a file's type), and `Content-Length` set to the body's length.
        func headerFields(bodyLength: Int, fileType: String? = nil) -> [String: String] {
            var fields = headers
            if let type = contentType ?? (fields.hasValue(named: "Content-Type") ? nil : fileType) {
                fields.setValue(type, named: "Content-Type")
            }
            fields.setValue(String(bodyLength), named: "Content-Length")
            return fields
        }
    }

    extension [String: String] {
        /// Whether a header named `name`, in any case, is set.
        fileprivate func hasValue(named name: String) -> Bool {
            keys.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }

        /// Sets the header named `name`, replacing one of the same name in any case.
        fileprivate mutating func setValue(_ value: String, named name: String) {
            for key in keys where key.caseInsensitiveCompare(name) == .orderedSame {
                removeValue(forKey: key)
            }
            self[name] = value
        }
    }
#endif

#if DEBUG
    import Foundation

    extension NetworkMockRule {
        /// The methods the rule matches, sorted ("GET, POST"), or "ANY".
        var methodSummary: String {
            matcher.methods.isEmpty ? "ANY" : matcher.methods.sorted().joined(separator: ", ")
        }

        /// The host and path the rule matches, as one line: `api.example.com/v1/users/*`; a regex
        /// after "regex"; "any host" and "any path" for those that match anything.
        var patternSummary: String {
            let host = matcher.host.summary(any: "any host")
            let path = matcher.path.summary(any: "any path")
            let joined = switch (matcher.host, matcher.path) {
            case (.exact, .exact), (.exact, .wildcard), (.wildcard, .exact), (.wildcard, .wildcard):
                host + path
            default:
                "\(host) · \(path)"
            }
            let query = matcher.query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            return query.isEmpty ? joined : joined + "?" + query.joined(separator: "&")
        }

        /// Whether the rule's host or path doesn't compile, so the rule never answers.
        var hasInvalidPattern: Bool {
            (try? CompiledNetworkMockMatcher(matcher)) == nil
        }
    }

    extension NetworkMockRule.Pattern {
        /// The pattern as the summary shows it: a regex after "regex", `any` for one that matches
        /// anything.
        func summary(any: String) -> String {
            switch self {
            case .any: any
            case let .exact(text), let .wildcard(text): text
            case let .regex(text): "regex \(text)"
            }
        }
    }
#endif

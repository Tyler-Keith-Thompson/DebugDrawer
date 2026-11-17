#if DEBUG
    import Foundation

    extension NetworkEntry {
        /// The largest request body read for a GraphQL operation name, in bytes; a larger one (an
        /// upload, say) isn't parsed, so capturing it costs no more than before.
        static let graphQLBodyLimit = 1 << 20
        /// How far into a GraphQL document the scan for its first named operation reads, in UTF-8
        /// bytes, past comments and fragments.
        static let graphQLQueryScanLimit = 64 * 1024

        /// The name of the GraphQL operation a request runs, or `nil` when it isn't a GraphQL
        /// request or runs an anonymous operation.
        ///
        /// - A POST whose body is a JSON object: its `operationName` when that is a non-empty
        ///   string, or else the first named operation in its `query` (`query GetUser`,
        ///   `mutation UpdateUser(…)`, `subscription OnMessage`), past whitespace, comments and
        ///   fragments.
        /// - A POST whose body is a JSON array, a batch: the first two names and how many more,
        ///   "GetUser, GetPosts +1".
        /// - A GET, such as a persisted query: the `operationName` query parameter, or the first
        ///   named operation in a `query` parameter that holds a selection set.
        ///
        /// Any other method, a body that isn't JSON or one over `graphQLBodyLimit` bytes gives
        /// `nil`.
        ///
        /// - Complexity: O(*n*) in the body's length, at most `graphQLBodyLimit`.
        static func graphQLOperationName(method: String, url: String, body: Data?) -> String? {
            switch method.uppercased() {
            case "POST": graphQLOperationName(body: body)
            case "GET": graphQLOperationName(url: url)
            default: nil
            }
        }

        /// The operation name in a POST's JSON body: one request's, or a batch's first two and how
        /// many more.
        private static func graphQLOperationName(body: Data?) -> String? {
            guard let body, body.count <= graphQLBodyLimit, body.startsAsJSONContainer,
                  let json = try? JSONSerialization.jsonObject(with: body) else { return nil }
            if let request = json as? [String: Any] {
                return request.graphQLOperationName
            }
            guard let batch = json as? [Any] else { return nil }
            let names = batch.compactMap { ($0 as? [String: Any])?.graphQLOperationName }
            switch names.count {
            case 0: return nil
            case 1, 2: return names.joined(separator: ", ")
            default: return names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)"
            }
        }

        /// The operation name in a GET's query parameters, as a persisted query sends it.
        private static func graphQLOperationName(url: String) -> String? {
            let items = URLComponents(string: url)?.queryItems ?? []
            if let name = items.first(where: { $0.name == "operationName" })?.value, !name.isEmpty {
                return name
            }
            // A selection set tells a GraphQL document from a search that happens to be named
            // `query`.
            guard let query = items.first(where: { $0.name == "query" })?.value, query.contains("{") else { return nil }
            return firstNamedGraphQLOperation(in: query)
        }

        /// The name of the first named operation in the GraphQL document `query`, after any
        /// whitespace, commas, comments and fragments; `nil` when the first operation is anonymous,
        /// the document holds something else first, or the name lies past
        /// `graphQLQueryScanLimit` bytes. A small scan rather than a parser: it reads only as far
        /// as the first operation's name.
        static func firstNamedGraphQLOperation(in query: String) -> String? {
            var scanner = GraphQLScanner(Array(query.utf8.prefix(graphQLQueryScanLimit)))
            while true {
                scanner.skipIgnored()
                guard let keyword = scanner.name() else { return nil }
                switch keyword {
                case "query", "mutation", "subscription":
                    scanner.skipIgnored()
                    return scanner.name()
                case "fragment":
                    guard scanner.skipBlock() else { return nil }
                default:
                    return nil
                }
            }
        }
    }

    /// Reads a GraphQL document's bytes from the start: names, and what lies between them.
    private struct GraphQLScanner {
        private let bytes: [UInt8]
        private var index = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        /// Moves past whitespace, commas, line terminators, a byte order mark and comments, which
        /// GraphQL ignores between tokens.
        mutating func skipIgnored() {
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: ","):
                    index += 1
                case 0xEF where bytes[index...].starts(with: [0xEF, 0xBB, 0xBF]):
                    index += 3
                case UInt8(ascii: "#"):
                    skipComment()
                default:
                    return
                }
            }
        }

        /// The name at the scanner, `[_A-Za-z][_0-9A-Za-z]*`, moving past it; `nil`, not moving,
        /// when no name starts there.
        mutating func name() -> String? {
            guard index < bytes.count, bytes[index].isNameStart else { return nil }
            let start = index
            while index < bytes.count, bytes[index].isNameStart || bytes[index].isDigit {
                index += 1
            }
            // ASCII letters, digits and underscores, so they always decode.
            return String(bytes: bytes[start ..< index], encoding: .utf8)
        }

        /// Moves past everything up to and including the selection set that closes the definition
        /// here (a fragment's), over strings and comments, whose braces don't count. `false` when
        /// the bytes end first.
        mutating func skipBlock() -> Bool {
            var depth = 0
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "#"):
                    skipComment()
                case UInt8(ascii: "\""):
                    guard skipString() else { return false }
                case UInt8(ascii: "{"):
                    depth += 1
                    index += 1
                case UInt8(ascii: "}"):
                    depth -= 1
                    index += 1
                    // A brace that closes nothing isn't GraphQL.
                    if depth <= 0 { return depth == 0 }
                default:
                    index += 1
                }
            }
            return false
        }

        private mutating func skipComment() {
            while index < bytes.count, bytes[index] != UInt8(ascii: "\n"), bytes[index] != UInt8(ascii: "\r") {
                index += 1
            }
        }

        /// Moves past the string or block string that starts here. `false` when it doesn't end.
        private mutating func skipString() -> Bool {
            let quote = UInt8(ascii: "\"")
            if bytes[index...].starts(with: [quote, quote, quote]) {
                index += 3
                while index < bytes.count {
                    if bytes[index...].starts(with: [UInt8(ascii: "\\"), quote, quote, quote]) {
                        index += 4
                    } else if bytes[index...].starts(with: [quote, quote, quote]) {
                        index += 3
                        return true
                    } else {
                        index += 1
                    }
                }
                return false
            }
            index += 1
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\\"): index += 2
                case quote:
                    index += 1
                    return true
                case UInt8(ascii: "\n"), UInt8(ascii: "\r"): return false
                default: index += 1
                }
            }
            return false
        }
    }

    extension UInt8 {
        /// Whether a GraphQL name can start with this byte: a letter or an underscore.
        fileprivate var isNameStart: Bool {
            (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(self) || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(self)
                || self == UInt8(ascii: "_")
        }

        fileprivate var isDigit: Bool {
            (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(self)
        }
    }

    extension Data {
        /// Whether the first byte past JSON whitespace opens an object or an array, so a body
        /// that isn't JSON is passed over without parsing it.
        fileprivate var startsAsJSONContainer: Bool {
            let first = first { ![UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r")].contains($0) }
            return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
        }
    }

    extension [String: Any] {
        /// The operation name of one GraphQL request: `operationName` when it is a non-empty
        /// string, or else the first named operation in `query`.
        fileprivate var graphQLOperationName: String? {
            if let name = self["operationName"] as? String, !name.isEmpty {
                return name
            }
            return (self["query"] as? String).flatMap(NetworkEntry.firstNamedGraphQLOperation(in:))
        }
    }
#endif

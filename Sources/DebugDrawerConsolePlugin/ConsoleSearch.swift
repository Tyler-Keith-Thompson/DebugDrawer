#if DEBUG
    import Foundation

    /// What the search field asks of a line: nothing, text it contains, or a regular expression it
    /// matches, ignoring case either way. A line matches when its text, subsystem or category does.
    ///
    /// The pattern is compiled once, when the search changes, rather than for each line it's
    /// matched against.
    enum ConsoleSearch: Equatable {
        /// Every line matches.
        case all
        /// Lines containing the text.
        case text(String)
        /// Lines the regular expression finds a match in.
        case pattern(NSRegularExpression)

        /// The search field's text isn't a regular expression `NSRegularExpression` reads.
        struct InvalidPattern: Error, Equatable {
            /// The problem in a sentence, under the field.
            var message: String {
                "Not a valid regular expression. The list keeps the last valid search."
            }
        }

        /// The search for `query`, as text or, when `isRegularExpression`, as a pattern; an empty
        /// query matches every line.
        ///
        /// - Throws: `InvalidPattern` when `isRegularExpression` and `query` isn't a pattern.
        init(_ query: String, isRegularExpression: Bool) throws(InvalidPattern) {
            guard !query.isEmpty else {
                self = .all
                return
            }
            guard isRegularExpression else {
                self = .text(query)
                return
            }
            do {
                self = try .pattern(NSRegularExpression(pattern: query, options: [.caseInsensitive]))
            } catch {
                throw InvalidPattern()
            }
        }

        /// Whether `line`'s text, subsystem or category matches.
        func matches(_ line: LogLine) -> Bool {
            switch self {
            case .all: true
            case let .text(query): [line.text, line.subsystem, line.category].contains { $0.range(of: query, options: .caseInsensitive) != nil }
            case let .pattern(pattern): [line.text, line.subsystem, line.category].contains { pattern.finds(in: $0) }
            }
        }
    }

    extension NSRegularExpression {
        /// Whether the expression finds a match anywhere in `text`.
        fileprivate func finds(in text: String) -> Bool {
            !text.isEmpty && firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }
#endif

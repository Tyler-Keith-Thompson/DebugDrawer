#if DEBUG
    import Foundation

    /// What the search field asks of a line: nothing, text it contains, or a regular expression it
    /// matches, ignoring case either way. A line matches when its text, subsystem, category, or a
    /// metadata key or value does.
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
        struct InvalidPattern: Error, Equatable, Codable {
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

        /// Whether `line`'s text, subsystem, category, or a metadata key, value or `key=value` field
        /// matches.
        func matches(_ line: LogLine) -> Bool {
            switch self {
            case .all: true
            case let .text(query): line.searchedFields.contains { $0.range(of: query, options: .caseInsensitive) != nil }
            case let .pattern(pattern): line.searchedFields.contains { pattern.finds(in: $0) }
            }
        }
    }

    // A compiled pattern isn't `Codable`, so a search is carried as the field's text and compiled
    // again when it is read.
    extension ConsoleSearch: Codable {
        private enum CodingKeys: String, CodingKey {
            case query, isRegularExpression
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let query = try container.decode(String.self, forKey: .query)
            let isRegularExpression = try container.decode(Bool.self, forKey: .isRegularExpression)
            do {
                try self.init(query, isRegularExpression: isRegularExpression)
            } catch {
                throw DecodingError.dataCorruptedError(forKey: .query, in: container, debugDescription: error.message)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .all:
                try container.encode("", forKey: .query)
                try container.encode(false, forKey: .isRegularExpression)
            case let .text(query):
                try container.encode(query, forKey: .query)
                try container.encode(false, forKey: .isRegularExpression)
            case let .pattern(pattern):
                try container.encode(pattern.pattern, forKey: .query)
                try container.encode(true, forKey: .isRegularExpression)
            }
        }
    }

    extension LogLine {
        /// What a search looks in: the text, subsystem and category, then the metadata.
        fileprivate var searchedFields: [String] {
            [text, subsystem, category] + searchableMetadata
        }
    }

    extension NSRegularExpression {
        /// Whether the expression finds a match anywhere in `text`.
        fileprivate func finds(in text: String) -> Bool {
            !text.isEmpty && firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }
#endif

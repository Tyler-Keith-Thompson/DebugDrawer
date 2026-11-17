#if DEBUG
    import Foundation

    /// A rule as the editor holds it while it is changed: text for every field, checked when
    /// saved.
    struct NetworkMockDraft: Equatable {
        /// How a host or path field is read.
        enum PatternKind: String, CaseIterable, Identifiable {
            case any = "Any"
            case exact = "Exact"
            case wildcard = "Wildcard"
            case regex = "Regex"

            var id: Self {
                self
            }
        }

        /// Where the response's body comes from.
        enum BodyKind: String, CaseIterable, Identifiable {
            case empty = "None"
            case text = "Text"
            case file = "File"

            var id: Self {
                self
            }
        }

        /// A header or query item being edited.
        struct Field: Identifiable, Equatable {
            let id: UUID
            var name: String
            var value: String

            init(id: UUID = UUID(), name: String = "", value: String = "") {
                self.id = id
                self.name = name
                self.value = value
            }
        }

        /// The methods the editor offers.
        static let standardMethods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

        let id: UUID
        /// Whether the rule isn't saved yet: Add and Mock This make one.
        let isNew: Bool
        var isEnabled: Bool
        var name: String
        var methods: Set<String>
        var hostKind: PatternKind
        var host: String
        var pathKind: PatternKind
        var path: String
        var query: [Field]
        var status: String
        var headers: [Field]
        var contentType: String
        var bodyKind: BodyKind
        var bodyText: String
        /// The chosen body file's name in the storage, if one was chosen.
        var bodyFile: String?

        /// The editor's fields for `rule`.
        ///
        /// - Parameter isNew: Whether the rule isn't saved yet.
        init(_ rule: NetworkMockRule, isNew: Bool) {
            id = rule.id
            self.isNew = isNew
            isEnabled = rule.isEnabled
            name = rule.name
            methods = rule.matcher.methods
            (hostKind, host) = Self.fields(rule.matcher.host)
            (pathKind, path) = Self.fields(rule.matcher.path)
            query = rule.matcher.query.sorted { $0.key < $1.key }.map { Field(name: $0.key, value: $0.value) }
            status = String(rule.response.status)
            headers = rule.response.headers.sorted { $0.key < $1.key }.map { Field(name: $0.key, value: $0.value) }
            contentType = rule.response.contentType ?? ""
            switch rule.response.body {
            case .empty:
                bodyKind = .empty
                bodyText = ""
            case let .text(text):
                bodyKind = .text
                bodyText = text
            case let .file(name):
                bodyKind = .file
                bodyText = ""
                bodyFile = name
            }
        }

        /// A draft for a new rule: any request, answered 200 with no body.
        static func new() -> NetworkMockDraft {
            NetworkMockDraft(NetworkMockRule(name: "", matcher: .init(), response: .init()), isNew: true)
        }

        // MARK: Checking

        /// Why the host field can't be saved, or `nil` when it can.
        var hostProblem: String? {
            Self.problem(kind: hostKind, text: host, noun: "host", separator: ".", caseInsensitive: true)
        }

        /// Why the path field can't be saved, or `nil` when it can.
        var pathProblem: String? {
            Self.problem(kind: pathKind, text: path, noun: "path", separator: "/", caseInsensitive: false)
        }

        /// Why the status can't be saved, or `nil` when it can.
        var statusProblem: String? {
            guard let code = Int(status.trimmingCharacters(in: .whitespaces)), (100 ... 599).contains(code) else {
                return "Enter a status from 100 to 599."
            }
            return nil
        }

        /// Why the body can't be saved, or `nil` when it can.
        var bodyProblem: String? {
            bodyKind == .file && bodyFile == nil ? "Choose a file for the body." : nil
        }

        /// The rule the fields describe, or `nil` while one of them has a problem. An empty name
        /// is the method and pattern summary.
        var rule: NetworkMockRule? {
            guard hostProblem == nil, pathProblem == nil, statusProblem == nil, bodyProblem == nil,
                  let code = Int(status.trimmingCharacters(in: .whitespaces)) else { return nil }
            let matcher = NetworkMockRule.Matcher(
                methods: methods,
                host: Self.pattern(hostKind, host.trimmingCharacters(in: .whitespaces)),
                path: Self.pattern(pathKind, path.trimmingCharacters(in: .whitespaces)),
                query: Self.dictionary(query)
            )
            let body: NetworkMockRule.Body = switch bodyKind {
            case .empty: .empty
            case .text: .text(bodyText)
            case .file: bodyFile.map(NetworkMockRule.Body.file) ?? .empty
            }
            let type = contentType.trimmingCharacters(in: .whitespaces)
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let draftRule = NetworkMockRule(
                id: id,
                name: trimmedName,
                isEnabled: isEnabled,
                matcher: matcher,
                response: .init(status: code, headers: Self.dictionary(headers), body: body, contentType: type.isEmpty ? nil : type)
            )
            guard trimmedName.isEmpty else { return draftRule }
            var named = draftRule
            named.name = "\(draftRule.methodSummary) \(draftRule.patternSummary)"
            return named
        }

        // MARK: Converting

        private static func fields(_ pattern: NetworkMockRule.Pattern) -> (PatternKind, String) {
            switch pattern {
            case .any: (.any, "")
            case let .exact(text): (.exact, text)
            case let .wildcard(text): (.wildcard, text)
            case let .regex(text): (.regex, text)
            }
        }

        private static func pattern(_ kind: PatternKind, _ text: String) -> NetworkMockRule.Pattern {
            switch kind {
            case .any: .any
            case .exact: .exact(text)
            case .wildcard: .wildcard(text)
            case .regex: .regex(text)
            }
        }

        /// The fields with a name, by name; of two with one name, the later wins.
        private static func dictionary(_ fields: [Field]) -> [String: String] {
            fields.reduce(into: [:]) { result, field in
                let name = field.name.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { result[name] = field.value }
            }
        }

        private static func problem(kind: PatternKind, text: String, noun: String, separator: Character, caseInsensitive: Bool) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard kind != .any else { return nil }
            guard !trimmed.isEmpty else { return "Enter a \(noun), or match any." }
            do {
                _ = try CompiledPattern(pattern(kind, trimmed), separator: separator, caseInsensitive: caseInsensitive)
                return nil
            } catch {
                return "Not a valid regular expression: \(error.reason)"
            }
        }
    }
#endif

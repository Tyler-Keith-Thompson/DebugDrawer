import Foundation

/// What the drawer's plugins mask before a value leaves the screen: in copy buttons, cURL
/// commands and reports, and on screen until the developer reveals it.
///
/// A value is sensitive when it sits under a configured header name, under a key that
/// contains one of the key patterns (headers, URL query items, JSON keys, keychain accounts
/// and services, cookie names, `UserDefaults` keys), or at one of the JSON paths. Names and
/// patterns match case-insensitively.
///
/// A JSON path is dot-separated object keys from the document's root (`user.password`); `*`
/// matches any one key, and arrays are transparent, so `items.token` matches the `token` of
/// every element of `items`.
///
/// The type exists in every build, so a ``DebugDrawerReportContributor`` compiles unchanged in
/// release.
public struct DebugDrawerRedaction: Equatable, Sendable {
    /// What a masked value is replaced with.
    public static let mask = "[REDACTED]"

    /// Header names whose values are masked, lowercased.
    public private(set) var headerNames: Set<String>
    /// Substrings of a key that make its value sensitive, lowercased.
    public private(set) var keyPatterns: Set<String>
    /// JSON paths whose values are masked.
    public private(set) var jsonPaths: Set<String>

    /// Rules masking the given header names, keys containing the given patterns and the
    /// given JSON paths.
    public init(
        headers: some Sequence<String> = [String](),
        keys: some Sequence<String> = [String](),
        jsonPaths: some Sequence<String> = [String]()
    ) {
        headerNames = Set(headers.map { $0.lowercased() })
        keyPatterns = Set(keys.map { $0.lowercased() }.filter { !$0.isEmpty })
        self.jsonPaths = Set(jsonPaths)
    }

    /// Credentials in their usual places: the `Authorization`, `Proxy-Authorization`,
    /// `Cookie` and `Set-Cookie` headers, and keys containing `token`, `secret`, `password`,
    /// `session`, `auth` or `apikey`/`api_key`/`api-key`.
    public static let standard = DebugDrawerRedaction(
        headers: ["Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie"],
        keys: ["token", "secret", "password", "session", "auth", "apikey", "api_key", "api-key"]
    )

    /// No rules: nothing is masked.
    public static let none = DebugDrawerRedaction()

    /// These rules with more header names, key patterns and JSON paths.
    public func adding(
        headers: some Sequence<String> = [String](),
        keys: some Sequence<String> = [String](),
        jsonPaths: some Sequence<String> = [String]()
    ) -> DebugDrawerRedaction {
        DebugDrawerRedaction(
            headers: headerNames.union(headers.map { $0.lowercased() }),
            keys: keyPatterns.union(keys.map { $0.lowercased() }),
            jsonPaths: self.jsonPaths.union(jsonPaths)
        )
    }

    /// Whether a key's value is sensitive: the key contains one of the key patterns.
    public func masksKey(_ key: String) -> Bool {
        let key = key.lowercased()
        return keyPatterns.contains { key.contains($0) }
    }

    /// Whether a header's value is sensitive: its name is a configured header name or
    /// contains a key pattern.
    public func masksHeader(_ name: String) -> Bool {
        headerNames.contains(name.lowercased()) || masksKey(name)
    }

    /// The value to show or export for a key: the mask when the key is sensitive.
    public func redacting(_ value: String, forKey key: String) -> String {
        masksKey(key) ? Self.mask : value
    }

    /// The headers with every sensitive header's value masked.
    public func redacting(headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { result, header in
            result[header.key] = masksHeader(header.key) ? Self.mask : header.value
        }
    }

    /// The URL with every sensitive query item's value masked; a URL with none comes back
    /// unchanged.
    public func redacting(url: String) -> String {
        guard var components = URLComponents(string: url),
              let items = components.queryItems,
              items.contains(where: { masksKey($0.name) && $0.value != nil })
        else { return url }
        components.queryItems = items.map { item in
            masksKey(item.name) && item.value != nil ? URLQueryItem(name: item.name, value: Self.mask) : item
        }
        return components.string ?? url
    }

    /// A JSON body with every sensitive value masked: values under a key that contains a key
    /// pattern, and values at the JSON paths. A body that isn't JSON, or has nothing to mask,
    /// comes back unchanged; a masked one is re-encoded with sorted keys.
    public func redacting(json body: Data) -> Data {
        guard !keyPatterns.isEmpty || !jsonPaths.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
        else { return body }
        let paths = jsonPaths.map { $0.split(separator: ".").map(String.init) }
        let redacted = redact(object, at: [], paths: paths)
        guard redacted.changed,
              let data = try? JSONSerialization.data(
                  withJSONObject: redacted.value,
                  options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
              )
        else { return body }
        return data
    }
}

extension DebugDrawerRedaction {
    fileprivate struct Redacted {
        var value: Any
        var changed: Bool
    }

    // JSONSerialization hands back Foundation containers; walking them keeps the document's
    // own types (numbers, nulls) wherever nothing is masked.
    fileprivate func redact(_ value: Any, at path: [String], paths: [[String]]) -> Redacted {
        switch value {
        case let object as [String: Any]:
            var changed = false
            var result = [String: Any]()
            for (key, child) in object {
                let childPath = path + [key]
                if masksKey(key) || paths.contains(where: { $0.matches(childPath) }) {
                    result[key] = Self.mask
                    changed = true
                } else {
                    let redacted = redact(child, at: childPath, paths: paths)
                    result[key] = redacted.value
                    changed = changed || redacted.changed
                }
            }
            return Redacted(value: result, changed: changed)
        case let array as [Any]:
            let elements = array.map { redact($0, at: path, paths: paths) }
            return Redacted(value: elements.map(\.value), changed: elements.contains(where: \.changed))
        default:
            return Redacted(value: value, changed: false)
        }
    }
}

extension [String] {
    /// Whether this JSON path (components, `*` for any key) names the given key path.
    fileprivate func matches(_ keyPath: [String]) -> Bool {
        count == keyPath.count && zip(self, keyPath).allSatisfy { $0 == "*" || $0 == $1 }
    }
}

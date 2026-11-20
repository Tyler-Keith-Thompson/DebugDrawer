import Foundation

/// The keys a reset removes from one UserDefaults domain.
package struct DefaultsDomain: Hashable, Sendable {
    /// The domain: the app's bundle identifier, or an app group's.
    package let name: String
    /// The keys to remove, sorted.
    package let keys: [String]
}

/// The keychain as a reset finds it: the items it will delete, or why it can't read them.
package enum KeychainInventory: Hashable, Sendable {
    case items([KeychainItem])
    case unavailable(KeychainError)
}

/// One line of what a category will delete: a key, an item, a file and its size, a cookie
/// domain and its count.
package struct PlanLine: Hashable, Sendable {
    package let text: String
    /// A size, a count or where it is; `nil` for none.
    package let detail: String?
}

/// Everything a reset would delete, category by category, read before anything is deleted:
/// what the rows summarize, the confirmation lists, and the reset deletes.
package struct ResetPlan: Hashable, Sendable {
    package var defaults: [DefaultsDomain]
    package var keychain: KeychainInventory
    package var files: [FileEntry]
    package var caches: [FileEntry]
    package var cookies: [StoredCookie]
    package var urlCache: URLCacheUsage
    /// The title of the app's own cleanup; `nil` when it supplied none.
    package var cleanup: String?

    /// The categories this app has: all of them, the app's cleanup only when it supplied one.
    package var categories: [AppStateReset.Category] {
        AppStateReset.Category.allCases.filter { $0 != .appCleanup || cleanup != nil }
    }

    /// What `category` will delete, in a few words ("12 keys", "4 items · 4.2 MB").
    package func summary(of category: AppStateReset.Category) -> String {
        switch category {
        case .userDefaults:
            return Self.count(defaults.map(\.keys.count).reduce(0, +), "key", none: "No keys")
        case .keychain:
            switch keychain {
            case let .items(items): return Self.count(items.count, "item", none: "No items")
            case .unavailable: return "Unavailable"
            }
        case .files:
            return Self.summary(of: files)
        case .caches:
            return Self.summary(of: caches)
        case .cookies:
            return Self.count(cookies.count, "cookie", none: "No cookies")
        case .urlCache:
            return "\(Self.bytes(urlCache.disk)) on disk"
        case .appCleanup:
            return cleanup ?? ""
        }
    }

    /// Why `category` can't be read, such as the keychain's error; `nil` when it can.
    package func problem(of category: AppStateReset.Category) -> String? {
        guard category == .keychain, case let .unavailable(error) = keychain else { return nil }
        return error.message
    }

    /// What `category` will delete, line by line.
    package func lines(of category: AppStateReset.Category) -> [PlanLine] {
        switch category {
        case .userDefaults:
            return defaults.flatMap { domain in
                domain.keys.map { PlanLine(text: $0, detail: defaults.count > 1 ? domain.name : nil) }
            }
        case .keychain:
            guard case let .items(items) = keychain else { return [] }
            return items.map { PlanLine(text: $0.name, detail: $0.itemClass.title) }
        case .files:
            return files.map(Self.line)
        case .caches:
            return caches.map(Self.line)
        case .cookies:
            let byDomain = Dictionary(grouping: cookies, by: \.domain)
            return byDomain.keys.sorted().map { domain in
                PlanLine(text: domain, detail: Self.count(byDomain[domain]?.count ?? 0, "cookie", none: ""))
            }
        case .urlCache:
            return [
                PlanLine(text: "On disk", detail: Self.bytes(urlCache.disk)),
                PlanLine(text: "In memory", detail: Self.bytes(urlCache.memory))
            ]
        case .appCleanup:
            return cleanup.map { [PlanLine(text: $0, detail: nil)] } ?? []
        }
    }

    /// "1 key", "12 keys", or `none` for zero.
    package static func count(_ count: Int, _ noun: String, none: String) -> String {
        switch count {
        case 0: none
        case 1: "1 \(noun)"
        default: "\(count.formatted()) \(noun)s"
        }
    }

    /// A size as Finder writes it ("4.2 MB").
    package static func bytes(_ count: some BinaryInteger) -> String {
        // "0 bytes" rather than "Zero kB": a size column reads as numbers.
        Int64(count).formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    private static func summary(of entries: [FileEntry]) -> String {
        guard !entries.isEmpty else { return "Empty" }
        return "\(count(entries.count, "item", none: "")) · \(bytes(entries.map(\.byteCount).reduce(0, +)))"
    }

    private static func line(_ entry: FileEntry) -> PlanLine {
        PlanLine(text: entry.displayPath, detail: bytes(entry.byteCount))
    }
}

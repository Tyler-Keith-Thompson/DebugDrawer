#if DEBUG
    import Foundation
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset

    /// A plan with something in every category, for the views.
    enum ResetPlanFixture {
        static let plan = ResetPlan(
            defaults: [
                DefaultsDomain(name: "com.example.orders", keys: ["counter", "hasSeenOnboarding", "lastSync"]),
                DefaultsDomain(name: "group.com.example.orders", keys: ["widgetTheme"])
            ],
            keychain: .items([
                KeychainItem(
                    itemClass: .genericPassword, service: "api.example.com", account: "alice", label: nil, persistentReference: Data("1".utf8)
                ),
                KeychainItem(itemClass: .internetPassword, service: "example.com", account: "alice", label: nil, persistentReference: Data("2".utf8))
            ]),
            files: [
                FileEntry(url: URL(filePath: "/tmp/Documents/Drafts"), displayPath: "Documents/Drafts", byteCount: 1_250_000),
                FileEntry(url: URL(filePath: "/tmp/Documents/notes.txt"), displayPath: "Documents/notes.txt", byteCount: 2_400),
                FileEntry(
                    url: URL(filePath: "/tmp/Application Support/orders.sqlite"), displayPath: "Application Support/orders.sqlite",
                    byteCount: 3_000_000
                )
            ],
            caches: [
                FileEntry(url: URL(filePath: "/tmp/Caches/thumbnails"), displayPath: "Caches/thumbnails", byteCount: 8_600_000)
            ],
            cookies: [
                StoredCookie(store: .http, name: "session", domain: "example.com", path: "/"),
                StoredCookie(store: .http, name: "theme", domain: "example.com", path: "/"),
                StoredCookie(store: .web, name: "consent", domain: "help.example.com", path: "/")
            ],
            urlCache: URLCacheUsage(disk: 4_200_000, memory: 512_000),
            cleanup: "Close the orders database"
        )
    }
#endif

#if DEBUG
    import Combine
    import Foundation

    /// What the plugin knows of the app's cookies.
    enum CookiesContents {
        /// Not read yet.
        case unread
        /// Every cookie in every store, sorted for display.
        case cookies([StoredCookie])
    }

    /// The Cookies plugin's state: every store's cookies, the filter, and the deletes made through
    /// it.
    @MainActor
    final class CookiesModel: ObservableObject {
        @Published private(set) var contents = CookiesContents.unread
        @Published var filter = ""

        private nonisolated let jar: any CookieJar
        /// The drawers the plugin is installed in; the last to remove it drops the cookies read.
        private var installations: Set<ObjectIdentifier> = []

        nonisolated init(jar: any CookieJar) {
            self.jar = jar
        }

        /// Every cookie, in every store.
        var allCookies: [StoredCookie] {
            guard case let .cookies(cookies) = contents else { return [] }
            return cookies
        }

        /// The cookies the filter lets through.
        var shownCookies: [StoredCookie] {
            allCookies.matching(filter)
        }

        /// How many cookies the filter shows, of how many there are.
        var count: CookieCount {
            CookieCount(shown: shownCookies.count, total: allCookies.count)
        }

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, drops the cookies read, so the next
        /// show reads the stores again. The filter stays.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            contents = .unread
        }

        /// Reads every store again.
        func reload() async {
            contents = await .cookies(jar.cookies().sortedForDisplay())
        }

        /// Deletes `cookie` from its store, then reads the stores again.
        func delete(_ cookie: StoredCookie) async {
            await jar.delete(cookie)
            await reload()
        }

        /// Deletes the cookies the filter shows, each from its own store, and no others, then reads
        /// the stores again.
        func deleteShown() async {
            for cookie in shownCookies {
                await jar.delete(cookie)
            }
            await reload()
        }
    }
#endif

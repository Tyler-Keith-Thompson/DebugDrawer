#if DEBUG
    import Foundation
    // tvOS and watchOS have no WebKit, so there the jar is `HTTPCookieStorage.shared` alone.
    #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
        import WebKit
    #endif

    /// The app's own cookie stores: `HTTPCookieStorage.shared`, and where WebKit exists,
    /// `WKWebsiteDataStore.default().httpCookieStore`, which web views keep apart from it.
    struct _CookieJar: CookieJar {
        func cookies() async -> [StoredCookie] {
            let shared = (HTTPCookieStorage.shared.cookies ?? []).map { StoredCookie(cookie: $0, store: .urlSession) }
            #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
                // WebKit's store answers on the main actor, once its network process has read it.
                let webView = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
                    .map { StoredCookie(cookie: $0, store: .webView) }
                return shared + webView
            #else
                return shared
            #endif
        }

        func delete(_ cookie: StoredCookie) async {
            switch cookie.store {
            case .urlSession:
                HTTPCookieStorage.shared.deleteCookie(cookie.cookie)
            case .webView:
                #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
                    await WKWebsiteDataStore.default().httpCookieStore.deleteCookie(cookie.cookie)
                #endif
            }
        }
    }
#endif

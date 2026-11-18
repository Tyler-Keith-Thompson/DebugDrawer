import DebugDrawer
import Foundation

extension CookiesPlugin: DebugDrawerReportContributor {
    /// Adds every cookie in `HTTPCookieStorage.shared`, as Copy copies them, as `cookies.txt`.
    /// WebKit's store answers only asynchronously, so a web view's cookies are left out. In release
    /// builds it adds nothing.
    public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        #if DEBUG
            let cookies = (HTTPCookieStorage.shared.cookies ?? []).map { StoredCookie(cookie: $0, store: .urlSession) }.sortedForDisplay()
            Self.contribute(cookies, to: &report, redaction: redaction)
        #endif
    }
}

#if DEBUG
    extension CookiesPlugin {
        /// Adds `cookies` as `cookies.txt` in Copy's format, sensitive values masked; no cookies
        /// add nothing.
        static func contribute(_ cookies: [StoredCookie], to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            guard !cookies.isEmpty else { return }
            report.add(text: cookies.report(redaction: redaction), named: "cookies.txt")
        }
    }
#endif

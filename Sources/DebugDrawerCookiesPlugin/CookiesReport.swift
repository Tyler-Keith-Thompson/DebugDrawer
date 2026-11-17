import DebugDrawer
import Foundation

extension CookiesPlugin: DebugDrawerReportContributor {
    /// Adds every cookie in the shared cookie storage, as Copy copies them, as `cookies.txt`. In
    /// release builds it adds nothing.
    public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        #if DEBUG
            let cookies = (HTTPCookieStorage.shared.cookies ?? []).sorted { ($0.domain, $0.name) < ($1.domain, $1.name) }
            Self.contribute(cookies, to: &report, redaction: redaction)
        #endif
    }
}

#if DEBUG
    extension CookiesPlugin {
        /// Adds `cookies` as `cookies.txt` in Copy's format, sensitive values masked; no cookies
        /// add nothing.
        static func contribute(_ cookies: [HTTPCookie], to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            guard !cookies.isEmpty else { return }
            report.add(text: cookies.report(redaction: redaction), named: "cookies.txt")
        }
    }
#endif

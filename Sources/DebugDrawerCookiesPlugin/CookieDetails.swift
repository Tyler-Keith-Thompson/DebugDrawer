#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A cookie's value, domain, path, store, flags and expiry, one labeled field each. A sensitive
    /// value is masked until revealed.
    struct CookieDetails: View {
        let stored: StoredCookie
        let redaction: DebugDrawerRedaction

        private var cookie: HTTPCookie {
            stored.cookie
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                DebugDrawerKeyValueRow("Value", value: cookie.value, redacted: cookie.redactedValue(redaction))
                DebugDrawerKeyValueRow("Domain", value: cookie.domain)
                DebugDrawerKeyValueRow("Path", value: cookie.path)
                DebugDrawerKeyValueRow("Store", value: stored.store.title)
                DebugDrawerKeyValueRow("Secure", value: cookie.isSecure ? "Yes" : "No")
                DebugDrawerKeyValueRow("HTTP Only", value: cookie.isHTTPOnly ? "Yes" : "No")
                if let expires = cookie.expiresDate {
                    DebugDrawerKeyValueRow("Expires", value: formatDate(expires))
                } else {
                    DebugDrawerKeyValueRow("Expires", value: "Session")
                }
            }
            .lineLimit(3)
        }

        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }
    }
#endif

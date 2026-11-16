#if DEBUG
    import DebugDrawer
    import Foundation

    extension HTTPCookie {
        /// The cookie's value, or the mask when the rules call it sensitive: they mask the
        /// `Cookie` header, or the cookie's name contains a key pattern.
        func redactedValue(_ redaction: DebugDrawerRedaction) -> String {
            redaction.masksHeader("Cookie") || redaction.masksKey(name) ? DebugDrawerRedaction.mask : value
        }
    }

    extension [HTTPCookie] {
        /// The text Copy puts on the clipboard: each cookie's name, value, domain, path, secure
        /// flag and expiry, with sensitive values masked.
        func report(redaction: DebugDrawerRedaction) -> String {
            var report = "HTTP Cookies (\(count))\n"
            report += String(repeating: "=", count: 40) + "\n"
            for cookie in self {
                report += "\nName: \(cookie.name)\n"
                report += "Value: \(cookie.redactedValue(redaction))\n"
                report += "Domain: \(cookie.domain)\n"
                report += "Path: \(cookie.path)\n"
                report += "Secure: \(cookie.isSecure)\n"
                if let expires = cookie.expiresDate {
                    report += "Expires: \(expires)\n"
                }
            }
            return report
        }
    }
#endif

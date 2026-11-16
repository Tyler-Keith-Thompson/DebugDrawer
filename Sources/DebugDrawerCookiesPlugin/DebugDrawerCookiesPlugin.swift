#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Plugin

    public struct CookiesPlugin: DebugDrawerPlugin {
        public var title = "HTTP Cookies"
        public var category = "Logs & Network"
        public var icon = "doc.plaintext"

        public init() {}

        public var body: some View {
            CookiesPluginView()
        }
    }

    // MARK: - View

    private struct CookiesPluginView: View {
        @State private var cookies: [HTTPCookie] = []
        @State private var searchText = ""
        @ObservedObject private var drawer = DebugDrawer.shared

        private var filtered: [HTTPCookie] {
            guard !searchText.isEmpty else { return cookies }
            let query = searchText.lowercased()
            return cookies.filter {
                $0.name.lowercased().contains(query) || $0.domain.lowercased().contains(query)
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                CookiesToolbar(count: cookies.count, refresh: loadCookies, deleteAll: deleteAll, copy: copyReport)

                // Search
                TextField("Filter by name or domain...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                    .accessibilityLabel("Filter cookies by name or domain")

                Divider()

                // Cookie list
                if filtered.isEmpty {
                    Text(cookies.isEmpty ? "No cookies stored" : "No matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(filtered.enumerated()), id: \.offset) { _, cookie in
                                CookieRow(cookie: cookie, redaction: drawer.redaction) {
                                    deleteCookie(cookie)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            .onAppear { loadCookies() }
        }

        private func loadCookies() {
            cookies = (HTTPCookieStorage.shared.cookies ?? [])
                .sorted { ($0.domain, $0.name) < ($1.domain, $1.name) }
        }

        private func deleteCookie(_ cookie: HTTPCookie) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
            loadCookies()
        }

        private func deleteAll() {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
            loadCookies()
        }

        private func copyReport() {
            debugDrawerCopyToClipboard(cookies.report(redaction: drawer.redaction))
        }
    }

    /// A cookie's name and domain, with a button to delete it; tapping the name shows the rest.
    struct CookieRow: View {
        let cookie: HTTPCookie
        let redaction: DebugDrawerRedaction
        let onDelete: () -> Void

        @State private var expanded = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(cookie.name)
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.medium)
                                .lineLimit(3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")

                    Spacer()

                    Text(cookie.domain)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(cookie.name)")
                }

                if expanded {
                    CookieDetails(cookie: cookie, redaction: redaction)
                        .padding(.leading, 16)
                }
            }
        }
    }

    /// A cookie's value, domain, path, flags and expiry, one labeled field each. A sensitive
    /// value is masked until revealed.
    struct CookieDetails: View {
        let cookie: HTTPCookie
        let redaction: DebugDrawerRedaction

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                DebugDrawerKeyValueRow("Value", value: cookie.value, redacted: cookie.redactedValue(redaction), labelWidth: 60)
                DebugDrawerKeyValueRow("Domain", value: cookie.domain, labelWidth: 60)
                DebugDrawerKeyValueRow("Path", value: cookie.path, labelWidth: 60)
                DebugDrawerKeyValueRow("Secure", value: cookie.isSecure ? "Yes" : "No", labelWidth: 60)
                DebugDrawerKeyValueRow("HTTP Only", value: cookie.isHTTPOnly ? "Yes" : "No", labelWidth: 60)
                if let expires = cookie.expiresDate {
                    DebugDrawerKeyValueRow("Expires", value: formatDate(expires), labelWidth: 60)
                } else {
                    DebugDrawerKeyValueRow("Expires", value: "Session", labelWidth: 60)
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installCookies() {
            registerGlobal(CookiesPlugin())
        }
    }
#endif

import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// `HTTPCookieStorage.shared`'s cookies, searched by name or domain, each expanded to its
/// attributes and deletable, or all of them.
public struct CookiesPlugin: DebugDrawerPlugin {
    public var title = "HTTP Cookies"
    public var category = "Logs & Network"
    public var icon = "doc.plaintext"

    public init() {}

    public var body: some View {
        #if DEBUG
            CookiesPluginView()
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the HTTP Cookies plugin, which lists `HTTPCookieStorage.shared`'s cookies.
    func installCookies() {
        #if DEBUG
            registerGlobal(CookiesPlugin())
        #endif
    }
}

#if DEBUG
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
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("Filter cookies by name or domain")

                // Cookie list
                if filtered.isEmpty {
                    Text(cookies.isEmpty ? "No cookies stored" : "No matches")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
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
                                .debugDrawerFont(.secondary)
                                .debugDrawerForegroundStyle(.secondary)
                                .accessibilityHidden(true)
                            // One line cut in the middle, as the UserDefaults keys are, until
                            // expanded; VoiceOver reads it whole.
                            Text(cookie.name)
                                .debugDrawerFont(.code)
                                .fontWeight(.medium)
                                .debugDrawerForegroundStyle(.primary)
                                .lineLimit(expanded ? nil : 1)
                                .truncationMode(.middle)
                                .help(cookie.name)
                        }
                    }
                    .debugDrawerButtonStyle(.plain)
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")

                    Spacer()

                    // Cut in the middle like the name, and whole once the cookie is expanded.
                    Text(cookie.domain)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.tertiary)
                        .lineLimit(expanded ? nil : 1)
                        .truncationMode(.middle)
                        .help(cookie.domain)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .debugDrawerButtonStyle(.borderless)
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
                DebugDrawerKeyValueRow("Value", value: cookie.value, redacted: cookie.redactedValue(redaction))
                DebugDrawerKeyValueRow("Domain", value: cookie.domain)
                DebugDrawerKeyValueRow("Path", value: cookie.path)
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

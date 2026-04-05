#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Plugin

    public struct CookiesPlugin: DebugDrawerPlugin {
        public var title = "HTTP Cookies"
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

        private var filtered: [HTTPCookie] {
            guard !searchText.isEmpty else { return cookies }
            let query = searchText.lowercased()
            return cookies.filter {
                $0.name.lowercased().contains(query) || $0.domain.lowercased().contains(query)
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack {
                    Text("\(cookies.count) cookies")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { loadCookies() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    Button("Delete All") { deleteAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.red)
                    Button("Copy") { copyReport() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }

                // Search
                TextField("Filter by name or domain...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))

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
                                CookieRow(cookie: cookie) {
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
            var report = "HTTP Cookies (\(cookies.count))\n"
            report += String(repeating: "=", count: 40) + "\n"
            for cookie in cookies {
                report += "\nName: \(cookie.name)\n"
                report += "Value: \(cookie.value)\n"
                report += "Domain: \(cookie.domain)\n"
                report += "Path: \(cookie.path)\n"
                report += "Secure: \(cookie.isSecure)\n"
                if let expires = cookie.expiresDate {
                    report += "Expires: \(expires)\n"
                }
            }
            debugDrawerCopyToClipboard(report)
        }
    }

    private struct CookieRow: View {
        let cookie: HTTPCookie
        let onDelete: () -> Void

        @State private var expanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text(cookie.name)
                                .font(.system(size: 10, design: .monospaced))
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(cookie.domain)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 2) {
                        cookieField("Value", cookie.value)
                        cookieField("Domain", cookie.domain)
                        cookieField("Path", cookie.path)
                        cookieField("Secure", cookie.isSecure ? "Yes" : "No")
                        cookieField("HTTP Only", cookie.isHTTPOnly ? "Yes" : "No")
                        if let expires = cookie.expiresDate {
                            cookieField("Expires", formatDate(expires))
                        } else {
                            cookieField("Expires", "Session")
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }

        private func cookieField(_ label: String, _ value: String) -> some View {
            HStack(alignment: .top) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Text(value)
                    .font(.system(size: 9, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
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

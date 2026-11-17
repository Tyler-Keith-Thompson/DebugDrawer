#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// In a request's detail, what ignores its host: Ignore and the host, or, for a host with
    /// parent domains, a menu of the host and each parent (`Ignore cdn.example.com`,
    /// `Ignore example.com`), so a whole CDN or analytics domain goes in one step. Nothing shows
    /// for a request with no host.
    struct NetworkIgnoreHostButton: View {
        let host: String
        let ignore: (NetworkIgnoredDomain) -> Void

        var body: some View {
            let choices = NetworkIgnoredDomain.choices(forHost: host)
            if choices.count == 1, let domain = choices.first {
                Button("Ignore \(domain.name)") { ignore(domain) }
                    .accessibilityLabel("Ignore \(domain.name)")
                    .accessibilityHint(Self.hint)
            } else if !choices.isEmpty {
                Menu("Ignore Host") {
                    ForEach(choices, id: \.self) { domain in
                        Button("Ignore \(domain.name)") { ignore(domain) }
                            .accessibilityLabel("Ignore \(domain.name)")
                    }
                }
                .menuStyle(.button)
                .fixedSize()
                .accessibilityLabel("Ignore Host")
                .accessibilityHint(Self.hint)
            }
        }

        private static let hint = "Hides the requests to this host, and its subdomains, from the log"
    }
#endif

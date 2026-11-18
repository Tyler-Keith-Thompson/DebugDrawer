#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// More, beside Resend in a request's detail: Copy cURL, Mock This, Edit and Resend… and Ignore
    /// Host, each offered only when its closure is set. In a menu rather than the action row, where
    /// the five buttons need two lines in an iPad's drawer.
    struct NetworkRequestMoreMenu: View {
        /// Copies the request as a cURL command.
        let copyCURL: () -> Void
        /// Opens a new mock made from the request; `nil` offers no Mock This.
        var mock: (() -> Void)?
        /// Opens the request in the resend editor; `nil` offers no Edit and Resend.
        var editAndResend: (() -> Void)?
        /// The request's host, offered to the ignore list with its parent domains.
        var host = ""
        /// Adds the host, or a parent domain, to the ignore list; `nil` offers no Ignore.
        var ignore: ((NetworkIgnoredDomain) -> Void)?

        var body: some View {
            Menu {
                Button("Copy cURL", action: copyCURL)
                    .accessibilityLabel("Copy cURL")
                    .accessibilityHint("Copies to the clipboard")
                if let mock {
                    Button("Mock This", action: mock)
                        .accessibilityLabel("Mock This")
                        .accessibilityHint("Makes a mock that answers requests like this one with its response")
                }
                if let editAndResend {
                    Button("Edit and Resend…", action: editAndResend)
                        .accessibilityLabel("Edit and Resend…")
                        .accessibilityHint("Opens the request to change its method, URL, headers or body before sending it again")
                }
                if let ignore {
                    Divider()
                    NetworkIgnoreHostButton(host: host, ignore: ignore)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .debugDrawerButtonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("More")
            .help("Copy as cURL, mock, edit and resend, or ignore the host")
        }
    }
#endif

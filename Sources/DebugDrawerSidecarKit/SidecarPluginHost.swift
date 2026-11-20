#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One plugin of the app's: waiting for its model's first snapshot, then the plugin as the
    /// drawer shows it, or why it couldn't be reached.
    struct SidecarPluginHost: View {
        /// Where the plugin is.
        enum Hosting {
            case waiting
            case shown(AnyDebugDrawerPlugin)
            case failed(DebugDrawerTransportError)
        }

        let connection: DebugDrawerSidecarConnection
        let plugin: DebugDrawerSidecarPlugin
        @State private var hosting = Hosting.waiting

        var body: some View {
            Group {
                switch hosting {
                case .waiting:
                    ProgressView("Waiting for \(plugin.title)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .shown(hosted):
                    SidecarHostedPlugin(plugin: hosted)
                case let .failed(error):
                    DebugDrawerEmptyState("\(plugin.title) Not Reached", systemImage: "exclamationmark.triangle") {
                        Text(error.localizedDescription)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // Cancelled as the plugin is no longer shown, which ends the wait.
            .task {
                do throws(DebugDrawerTransportError) {
                    hosting = try await .shown(connection.host(plugin))
                } catch {
                    if error != .cancelled {
                        hosting = .failed(error)
                    }
                }
            }
        }
    }

    /// A plugin shown in the sidecar: its title and header accessory, as the drawer's header row
    /// draws them, over its body.
    struct SidecarHostedPlugin: View {
        let plugin: AnyDebugDrawerPlugin

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Label(plugin.title, systemImage: plugin.icon)
                        .debugDrawerFont(.title)
                    Spacer()
                    plugin.headerAccessory
                        .debugDrawerFont(.label)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                ScrollView {
                    plugin.body
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
#endif

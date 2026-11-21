#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The sidebar: one row per app serving the sidecar, or why there are none.
    struct SidecarAppListView: View {
        let apps: [DebugDrawerSidecarApp]
        /// Why the group's store can't be read, while it can't.
        let error: DebugDrawerTransportError?
        @Binding var selection: DebugDrawerSidecarApp.ID?

        var body: some View {
            if let error {
                DebugDrawerEmptyState("Group Not Reachable", systemImage: "exclamationmark.triangle") {
                    Text(error.localizedDescription)
                }
            } else if apps.isEmpty {
                DebugDrawerEmptyState("No Apps", systemImage: "app.dashed") {
                    Text("No app in the group serves a sidecar. Start an app that runs a receiver.")
                }
            } else {
                #if os(watchOS)
                    // The watch's list has no selection: a row pushes its app, which sets it.
                    List(apps) { app in
                        NavigationLink(value: app.id) {
                            SidecarAppRow(app: app)
                        }
                    }
                #else
                    List(apps, selection: $selection) { app in
                        SidecarAppRow(app: app)
                            .tag(app.id)
                    }
                #endif
            }
        }
    }

    /// An app in the sidebar: its name, then its version and build, its bundle ID and when it
    /// was last seen.
    struct SidecarAppRow: View {
        let app: DebugDrawerSidecarApp

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .debugDrawerFont(.body)
                Text(app.versionLine)
                    .debugDrawerFont(.value)
                    .foregroundStyle(.secondary)
                Text(app.bundleIdentifier)
                    .debugDrawerFont(.code)
                    .foregroundStyle(.secondary)
                if app.isServing {
                    Text("Last seen \(app.lastSeen, style: .relative) ago")
                        .debugDrawerFont(.secondary)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Turned off by the host")
                        .debugDrawerFont(.secondary)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    extension DebugDrawerSidecarApp {
        /// The version and build as the sidebar shows them: `2.4 (881)`, or what the app gave.
        var versionLine: String {
            switch (version.isEmpty, build.isEmpty) {
            case (false, false): "\(version) (\(build))"
            case (false, true): version
            case (true, false): "(\(build))"
            case (true, true): "No version"
            }
        }
    }
#endif

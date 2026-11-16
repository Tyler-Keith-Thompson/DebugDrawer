// The drawer with several plugins open, built from the drawer's own chrome and plugins made of
// the core vocabulary, for the drawer's snapshots on the Mac and on iOS. Fixture views, not
// assertions: each snapshot test hosts and checks it itself.
#if os(macOS) || os(iOS)
    @testable import DebugDrawer
    import SwiftUI

    struct FixtureAppInfoPlugin: DebugDrawerPlugin {
        var title = "App Info"
        var icon = "info.circle"
        var category = "App"
        var body: some View {
            DebugDrawerSection {
                DebugDrawerKeyValueRow("Bundle ID", value: "com.example.orders")
                DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")
                DebugDrawerKeyValueRow("Footprint", value: "63.5 MB")
                DebugDrawerKeyValueRow("Token", value: "t0k3n", redacted: DebugDrawerRedaction.mask)
            }
            DebugDrawerActionRow {
                DebugDrawerCopyButton("Copy Info") { "" }
                Button("Refresh") {}
            }
        }
    }

    struct FixturePerformancePlugin: DebugDrawerPlugin {
        var title = "Performance"
        var icon = "gauge.with.dots.needle.33percent"
        var category = "Performance"
        var body: some View {
            DebugDrawerGaugeRow("CPU", value: "38%", fraction: 0.38)
            DebugDrawerGaugeRow("Memory", value: "182.4 MB", fraction: 0.62)
            DebugDrawerGaugeRow("Frames", value: "52 fps", fraction: 52.0 / 60, severity: .warning)
        }
    }

    struct FixturePermissionsPlugin: DebugDrawerPlugin {
        var title = "Permissions"
        var icon = "lock.shield"
        var category = "App"
        var body: some View {
            DebugDrawerIssueRow("Camera", status: "Allowed", severity: .ok, subline: "NSCameraUsageDescription")
            DebugDrawerIssueRow("Location", status: "Not Asked", severity: .neutral, subline: "NSLocationWhenInUseUsageDescription") {
                Text("Finds the nearest store.")
                DebugDrawerActionRow {
                    Button("Request") {}
                        .debugDrawerButtonStyle(.primary)
                    Button("Open Settings") {}
                }
            }
            DebugDrawerIssueRow("Photos", status: "Limited", severity: .warning, subline: "NSPhotoLibraryUsageDescription")
            DebugDrawerIssueRow("Contacts", status: "Denied", severity: .error, subline: "NSContactsUsageDescription")
        }
    }

    struct FixtureHangPlugin: DebugDrawerPlugin {
        var title = "Hangs"
        var icon = "hourglass"
        var category = "Performance"
        var headerAccessory: some View { DebugDrawerIssueCount(.warning, count: 4) }
        var body: some View {
            DebugDrawerSection("612 ms on the main thread") {
                DebugDrawerStackFrameRow(index: 0, symbol: "__semwait_signal", image: "libsystem_kernel.dylib", isOwnCode: false)
                DebugDrawerStackFrameRow(index: 1, symbol: "usleep", image: "libsystem_c.dylib", isOwnCode: false)
                DebugDrawerStackFrameRow(index: 2, symbol: "OrdersViewModel.load()", image: "Example", isOwnCode: true, isSelected: true)
                DebugDrawerStackFrameRow(index: 3, symbol: "OrdersView.body.getter", image: "Example", isOwnCode: true)
                DebugDrawerStackFrameRow(index: 4, symbol: "ButtonAction.callAsFunction()", image: "SwiftUI", isOwnCode: false)
            }
            DebugDrawerActionRow {
                DebugDrawerCopyButton("Copy Report") { "" }
            } trailing: {
                Button("Clear All", role: .destructive) {}
                    .debugDrawerButtonStyle(.destructive)
            }
        }
    }

    struct FixtureLibrariesPlugin: DebugDrawerPlugin {
        var title = "Loaded Libraries"
        var icon = "books.vertical"
        var category = "Storage"
        var body: some View {
            DebugDrawerTypeBadgeRow("Example", kind: .app, path: "/private/var/containers/Bundle/Application/1C2D/Example.app/Example")
            DebugDrawerTypeBadgeRow(
                "Charts",
                kind: .framework,
                path: "/private/var/containers/Bundle/Application/1C2D/Example.app/Frameworks/Charts.framework/Charts",
                version: "5.1.0"
            )
            DebugDrawerTypeBadgeRow("libswiftCore.dylib", kind: .dylib, path: "/usr/lib/swift/libswiftCore.dylib")
            DebugDrawerCodeBlock {
                Text("{ \"aps\": { \"badge\": 1 } }")
            }
        }
    }

    struct FixtureCollapsedPlugin: DebugDrawerPlugin {
        var title = "User Defaults"
        var icon = "list.bullet.rectangle"
        var category = "Storage"
        var headerAccessory: some View { Text("42 keys") }
        var body: some View { EmptyView() }
    }

    /// The panel as the drawer lays it out: the header block (title, jump bar, navigator tabs),
    /// the outline of plugins, four open and one closed, and the filter bar at the foot.
    struct DrawerFixturePanel: View {
        private let plugins: [AnyDebugDrawerPlugin] = [
            AnyDebugDrawerPlugin(FixtureAppInfoPlugin()),
            AnyDebugDrawerPlugin(FixturePermissionsPlugin()),
            AnyDebugDrawerPlugin(FixturePerformancePlugin()),
            AnyDebugDrawerPlugin(FixtureHangPlugin()),
            AnyDebugDrawerPlugin(FixtureLibrariesPlugin()),
            AnyDebugDrawerPlugin(FixtureCollapsedPlugin())
        ]
        private let badges = ["FixturePermissionsPlugin": 2]

        var body: some View {
            VStack(spacing: 0) {
                DrawerHeader(
                    isReportInProgress: false,
                    context: DrawerJumpBar.Context(appName: "Orders", version: "1.4.2", build: "88", device: "iPad", system: "iOS 27.2"),
                    createReport: {},
                    close: {}
                )
                DrawerNavigatorTabs(tabs: DrawerNavigatorTab.tabs(for: plugins, badges: badges), selection: .constant(.all))
                    .padding(.vertical, 4)
                DrawerRule()
                ForEach(plugins) { plugin in
                    let expanded = plugin.title != "User Defaults"
                    DrawerPluginSection(plugin: plugin, isExpanded: expanded) {
                        PluginSectionHeader(
                            plugin: plugin,
                            isExpanded: expanded,
                            isPinned: plugin.title == "App Info",
                            badge: badges[plugin.id],
                            isMovable: true
                        ) {}
                    }
                }
                DrawerFilterBar(
                    field: { DrawerSearchField(query: .constant("")) },
                    showsOnlyOwnCode: .constant(false),
                    showsOnlyUnread: .constant(false)
                )
            }
            .background(DrawerPalette.panel)
        }
    }
#endif

import DebugDrawer
import SwiftUI

// The whole sidecar in one view, for a company's app to put in its window under its own branding:
// a split view whose sidebar lists the apps in the group serving a sidecar and whose detail is the
// app picked, with its session control, the plugins it serves and the report. Everything the
// company adds (a sign-in screen, its logo, its colors, a grant from its server) goes around this
// view or into the grant closure; the view holds no service of its own.
//
// On watchOS the split view becomes the watch's navigation model, as the drawer's does
// (DrawerWatchList): the list of apps, each row pushing its app's screen, which lists the app's
// plugins, each row pushing that plugin. A NavigationSplitView would collapse to the same stack,
// but a path of its own lets the list push the only app listed as it shows up.

#if DEBUG
    /// A sidecar app's screen: the apps in the group that serve it, and for the one picked, its
    /// session, the plugins it serves and a bug report of them.
    ///
    /// ```swift
    /// @main
    /// struct CompanySidecar: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             DebugDrawerSidecarView(groupIdentifier: "TEAMID.com.example.debug")
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// For an app whose commands act only within a session, the detail shows the session's state
    /// with Open Session and End Session; when the app's sessions require a signed grant, `grant`
    /// fetches one from the company's server as the person opens a session. Send Report appears
    /// beside a finished report when `DebugDrawer.shared.reportUploader` is set, as in the drawer.
    ///
    /// Release builds get a stand-in that says the kit runs in debug builds.
    public struct DebugDrawerSidecarView: View {
        @StateObject private var apps: DebugDrawerSidecarAppList
        @State private var selection: DebugDrawerSidecarApp.ID?
        private let plugins: [DebugDrawerSidecarPlugin]
        private let sessionDuration: TimeInterval
        private let grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)?

        /// The sidecar for the apps serving the app group `groupIdentifier`.
        ///
        /// - Parameters:
        ///   - groupIdentifier: The app group the sidecar and the apps list in their
        ///     `com.apple.security.application-groups` entitlement.
        ///   - plugins: The plugins to show, for each app that serves them, in this order.
        ///   - sessionDuration: How long a session Open Session asks for, in seconds; the app caps
        ///     it at its maximum.
        ///   - grant: Fetches the signed grant for a session with the app given, for apps whose
        ///     sessions require one; what it throws is shown, and no session opens. `nil` opens
        ///     sessions without a grant.
        public init(
            groupIdentifier: String,
            plugins: [DebugDrawerSidecarPlugin] = DebugDrawerSidecarPlugin.defaults,
            sessionDuration: TimeInterval = 15 * 60,
            grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)? = nil
        ) {
            self.init(
                apps: DebugDrawerSidecarAppList(groupIdentifier: groupIdentifier), plugins: plugins, sessionDuration: sessionDuration, grant: grant
            )
        }

        /// The sidecar for the apps serving any of the app groups `groupIdentifiers`: for a
        /// company that gives each app a group of its own, so the apps can't read each other's
        /// files, and has the sidecar join every one.
        ///
        /// - Parameters:
        ///   - groupIdentifiers: The app groups, each listed in the sidecar's
        ///     `com.apple.security.application-groups` entitlement and in its apps'.
        ///   - plugins: The plugins to show, for each app that serves them, in this order.
        ///   - sessionDuration: How long a session Open Session asks for, in seconds; the app caps
        ///     it at its maximum.
        ///   - grant: Fetches the signed grant for a session with the app given, for apps whose
        ///     sessions require one; `nil` opens sessions without a grant.
        public init(
            groupIdentifiers: [String],
            plugins: [DebugDrawerSidecarPlugin] = DebugDrawerSidecarPlugin.defaults,
            sessionDuration: TimeInterval = 15 * 60,
            grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)? = nil
        ) {
            self.init(
                apps: DebugDrawerSidecarAppList(groupIdentifiers: groupIdentifiers), plugins: plugins, sessionDuration: sessionDuration, grant: grant
            )
        }

        /// The sidecar for the apps `apps` lists.
        ///
        /// - Parameters:
        ///   - apps: The apps to list; made once, for the view's lifetime.
        ///   - plugins: The plugins to show, for each app that serves them, in this order.
        ///   - sessionDuration: How long a session Open Session asks for, in seconds.
        ///   - grant: Fetches the signed grant for a session with the app given; `nil` opens
        ///     sessions without one.
        public init(
            apps: @escaping @autoclosure () -> DebugDrawerSidecarAppList,
            plugins: [DebugDrawerSidecarPlugin] = DebugDrawerSidecarPlugin.defaults,
            sessionDuration: TimeInterval = 15 * 60,
            grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)? = nil
        ) {
            _apps = StateObject(wrappedValue: apps())
            self.plugins = plugins
            self.sessionDuration = sessionDuration
            self.grant = grant
        }

        public var body: some View {
            #if os(watchOS)
                NavigationStack(path: path) {
                    SidecarAppListView(apps: apps.apps, error: apps.error, selection: $selection)
                        .navigationTitle("Apps")
                        .navigationDestination(for: DebugDrawerSidecarApp.ID.self) { id in
                            detail(for: id)
                        }
                }
                .onChange(of: apps.apps.map(\.id), initial: true) { _, ids in selectOnlyApp(of: ids) }
            #else
                NavigationSplitView {
                    SidecarAppListView(apps: apps.apps, error: apps.error, selection: $selection)
                        .navigationTitle("Apps")
                } detail: {
                    detail(for: selection)
                }
                .onChange(of: apps.apps.map(\.id), initial: true) { _, ids in selectOnlyApp(of: ids) }
            #endif
        }

        /// The app picked: its screen, why it serves nothing, or a prompt to pick one.
        @ViewBuilder
        private func detail(for id: DebugDrawerSidecarApp.ID?) -> some View {
            if let app = apps.apps.first(where: { $0.id == id }), !app.isServing {
                DebugDrawerEmptyState("Turned Off", systemImage: "power") {
                    Text("\(app.displayName)'s host has turned its receiver off: it serves nothing and refuses every command.")
                }
            } else if let app = apps.apps.first(where: { $0.id == id }) {
                SidecarAppScreen(app: app, plugins: plugins, sessionDuration: sessionDuration, grant: grant)
                    // A new connection for each app picked, not the last one's.
                    .id(app.id)
            } else {
                DebugDrawerEmptyState("No App Selected", systemImage: "app.connected.to.app.below.fill") {
                    Text("Pick an app to open a session and see its plugins.")
                }
            }
        }

        /// The only app listed is the one to show, as soon as it shows up.
        private func selectOnlyApp(of ids: [DebugDrawerSidecarApp.ID]) {
            if selection.map({ !ids.contains($0) }) ?? true, ids.count == 1 {
                selection = ids.first
            }
        }

        #if os(watchOS)
            /// The selection as the navigation stack's path: the app picked, pushed over the list.
            private var path: Binding<[DebugDrawerSidecarApp.ID]> {
                Binding {
                    selection.map { [$0] } ?? []
                } set: { path in
                    selection = path.last
                }
            }
        #endif
    }
#else
    // The release stand-in: the same members, and a line saying why there is nothing to show.

    /// Release builds have no sidecar: this stand-in says the kit runs in debug builds.
    public struct DebugDrawerSidecarView: View {
        /// A stand-in.
        ///
        /// - Parameters:
        ///   - groupIdentifier: Ignored.
        ///   - plugins: Ignored.
        ///   - sessionDuration: Ignored.
        ///   - grant: Never called.
        public init(
            groupIdentifier: String,
            plugins: [DebugDrawerSidecarPlugin] = DebugDrawerSidecarPlugin.defaults,
            sessionDuration: TimeInterval = 15 * 60,
            grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)? = nil
        ) {}

        /// A stand-in.
        ///
        /// - Parameters:
        ///   - groupIdentifiers: Ignored.
        ///   - plugins: Ignored.
        ///   - sessionDuration: Ignored.
        ///   - grant: Never called.
        public init(
            groupIdentifiers: [String],
            plugins: [DebugDrawerSidecarPlugin] = DebugDrawerSidecarPlugin.defaults,
            sessionDuration: TimeInterval = 15 * 60,
            grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)? = nil
        ) {}

        /// A stand-in.
        ///
        /// - Parameters:
        ///   - apps: Never called.
        ///   - plugins: Ignored.
        ///   - sessionDuration: Ignored.
        ///   - grant: Never called.
        public init(
            apps: @escaping @autoclosure () -> DebugDrawerSidecarAppList,
            plugins: [DebugDrawerSidecarPlugin] = DebugDrawerSidecarPlugin.defaults,
            sessionDuration: TimeInterval = 15 * 60,
            grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)? = nil
        ) {}

        public var body: some View {
            Text("The sidecar kit runs in debug builds. Build this app in the Debug configuration.")
                .padding()
        }
    }
#endif

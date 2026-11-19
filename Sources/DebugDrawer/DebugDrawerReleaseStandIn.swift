#if !DEBUG
    import SwiftUI

    // The release stand-in of the drawer in DebugDrawer.swift: the same members, so the host's code
    // compiles unchanged, and no drawer behind them. It registers nothing, opens nothing, calls no
    // plugin's hooks and keeps every value at its start.

    /// Release builds have no drawer: this stand-in keeps the debug build's members and does nothing.
    @MainActor
    public final class DebugDrawer: ObservableObject {
        /// The stand-in drawer.
        public static let shared = DebugDrawer()

        /// Always false: release builds have no drawer to open.
        @Published public var isOpen = false

        /// Always empty: registering drops the plugin.
        @Published public private(set) var globalPlugins: [AnyDebugDrawerPlugin] = []

        /// Always empty: registering drops the plugin.
        @Published public private(set) var localPlugins: [AnyDebugDrawerPlugin] = []

        /// Makes a stand-in drawer, which holds nothing.
        public init() {}

        /// Makes a stand-in drawer, which holds nothing and saves nothing.
        ///
        /// - Parameter defaults: Ignored.
        public init(defaults: UserDefaults) {}

        /// Drops the plugin: release builds have no drawer.
        ///
        /// - Parameter plugin: Ignored.
        public func registerGlobal<P: DebugDrawerPlugin>(_ plugin: P) {}

        /// Does nothing.
        ///
        /// - Parameter id: Ignored.
        public func unregisterGlobal(id: String) {}

        /// Drops the plugin: release builds have no drawer.
        ///
        /// - Parameter plugin: Ignored.
        /// - Returns: A token that unregisters nothing.
        @discardableResult
        public func registerLocal<P: DebugDrawerPlugin>(_ plugin: P) -> UUID {
            UUID()
        }

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - id: Ignored.
        ///   - token: Ignored.
        public func unregisterLocal(id: String, token: UUID) {}

        /// Does nothing: release builds have no drawer to open.
        public func toggle() {}

        /// Runs `action`: there is no drawer or HUD to hide.
        ///
        /// - Parameters:
        ///   - hidesDrawer: Ignored.
        ///   - action: The work to do.
        public func performWhileHidden(drawer hidesDrawer: Bool = true, _ action: @escaping @MainActor () async -> Void) {
            Task { await action() }
        }

        /// Always false.
        public var hasPlugins: Bool {
            false
        }

        /// The rules plugins would mask with; nothing reads them in release.
        @Published public var redaction = DebugDrawerRedaction.standard

        /// Does nothing: nothing in release masks anything.
        ///
        /// - Parameters:
        ///   - headers: Ignored.
        ///   - keys: Ignored.
        ///   - jsonPaths: Ignored.
        public func redact(
            headers: some Sequence<String> = [String](),
            keys: some Sequence<String> = [String](),
            jsonPaths: some Sequence<String> = [String]()
        ) {}

        /// Kept, never called: release builds make no reports.
        @Published public var reportUploader: (any DebugDrawerReportUploader)?

        /// Always empty: release builds have no HUD.
        @Published public internal(set) var hudLayout = HUDLayout()

        /// Always false.
        @Published public internal(set) var isHUDHidden = false

        /// Does nothing.
        ///
        /// - Parameter id: Ignored.
        public func toggleHUD(forPlugin id: String) {}

        /// Does nothing.
        ///
        /// - Parameter origin: Ignored.
        public func moveHUD(to origin: CGPoint) {}

        /// Always empty.
        public var hudPlugins: [AnyDebugDrawerPlugin] {
            []
        }

        /// Always empty.
        @Published public private(set) var badges: [String: Int] = [:]

        /// Always nil.
        @Published public private(set) var toast: DebugDrawerToast?
    }
#endif

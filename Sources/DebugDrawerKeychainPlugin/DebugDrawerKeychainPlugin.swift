import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// The app's keychain: its generic and internet passwords, certificates and keys, each with
/// every attribute the keychain returns, filtered by access group and text. Generic passwords
/// can be added and edited, and any item deleted. A password's value is read only when its
/// detail opens, and a certificate's or key's data never.
public struct KeychainPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "KeychainPlugin"
    }

    public var title = "Keychain"
    public var category = "Storage"
    public var icon = "key"

    #if DEBUG
        /// The model the plugin shows, or `nil` for the shared one.
        private let model: KeychainModel?

        /// The plugin over the app's own keychain: on the Mac, the data protection keychain.
        @MainActor
        public init() {
            model = nil
        }

        /// - Parameter model: The model to show in place of the shared one.
        init(model: KeychainModel) {
            self.model = model
        }
    #else
        /// The plugin over the app's own keychain: on the Mac, the data protection keychain.
        @MainActor
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            let shown = model ?? .shared
            // The passwords reach the view from the model in this process, never through the
            // transport, which could carry them out of the app.
            KeychainPluginView(transport: .direct(to: shown), revealedValue: { shown.revealedValue(for: $0) })
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin; nothing is read until it is shown.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, drops the items it read, the
    /// password of the open item and any form's draft. The keychain itself is untouched.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }

    /// How many items the keychain holds, once read.
    public var headerAccessory: some View {
        #if DEBUG
            KeychainHeaderAccessory(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Keychain plugin.
    func installKeychain() {
        #if DEBUG
            registerGlobal(KeychainPlugin())
        #endif
    }
}

#if DEBUG
    /// "12 items" once the keychain has been read; nothing before.
    struct KeychainHeaderAccessory: View {
        @StateObject private var transport: DebugDrawerPluginTransport<KeychainSnapshot, KeychainCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<KeychainSnapshot, KeychainCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            if case let .items(items) = transport.snapshot.contents {
                Text(items.count == 1 ? "1 item" : "\(items.count) items")
            }
        }
    }
#endif

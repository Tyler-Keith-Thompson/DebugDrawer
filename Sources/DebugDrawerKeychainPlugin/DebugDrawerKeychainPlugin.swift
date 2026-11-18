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
        let model: KeychainModel

        /// The plugin over the app's own keychain: on the Mac, the data protection keychain.
        @MainActor
        public init() {
            self.init(model: KeychainModel(keychain: _Keychain()))
        }

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
            KeychainPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// How many items the keychain holds, once read.
    public var headerAccessory: some View {
        #if DEBUG
            KeychainHeaderAccessory(model: model)
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
        @ObservedObject var model: KeychainModel

        var body: some View {
            if case let .items(items) = model.contents {
                Text(items.count == 1 ? "1 item" : "\(items.count) items")
            }
        }
    }

#endif

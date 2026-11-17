#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The app's keychain: its generic and internet passwords, certificates and keys, each with
    /// every attribute the keychain returns, filtered by access group and text. Generic passwords
    /// can be added and edited, and any item deleted. A password's value is read only when its
    /// detail opens, and a certificate's or key's data never.
    public struct KeychainPlugin: DebugDrawerPlugin {
        public var title = "Keychain"
        public var category = "Storage"
        public var icon = "key"

        let model: KeychainModel

        /// The plugin over the app's own keychain: on the Mac, the data protection keychain.
        @MainActor
        public init() {
            self.init(model: KeychainModel(keychain: _Keychain()))
        }

        init(model: KeychainModel) {
            self.model = model
        }

        public var body: some View {
            KeychainPluginView(model: model)
        }

        /// How many items the keychain holds, once read.
        public var headerAccessory: some View {
            KeychainHeaderAccessory(model: model)
        }
    }

    /// "12 items" once the keychain has been read; nothing before.
    struct KeychainHeaderAccessory: View {
        @ObservedObject var model: KeychainModel

        var body: some View {
            if case let .items(items) = model.contents {
                Text(items.count == 1 ? "1 item" : "\(items.count) items")
            }
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Registers the Keychain plugin.
        func installKeychain() {
            registerGlobal(KeychainPlugin())
        }
    }
#endif

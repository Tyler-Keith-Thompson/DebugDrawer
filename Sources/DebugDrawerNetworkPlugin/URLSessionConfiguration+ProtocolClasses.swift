#if DEBUG
    import Foundation

    extension URLSessionConfiguration {
        /// Swizzle the `protocolClasses` getter so every `URLSessionConfiguration`
        /// (`.default`, `.ephemeral`, custom) includes the plugin's URL protocol first.
        /// `URLProtocol.registerClass` alone only covers `URLSession.shared`.
        static func swizzleProtocolClasses() {
            guard let original = class_getInstanceMethod(self, #selector(getter: protocolClasses)),
                  let swizzled = class_getInstanceMethod(self, #selector(getter: debugDrawerProtocolClasses))
            else { return }
            method_exchangeImplementations(original, swizzled)
        }

        @objc private var debugDrawerProtocolClasses: [AnyClass]? {
            // After the swizzle, this calls the original getter
            guard var classes = self.debugDrawerProtocolClasses else {
                return [DebugNetworkProtocol.self]
            }
            if !classes.contains(where: { $0 == DebugNetworkProtocol.self }) {
                classes.insert(DebugNetworkProtocol.self, at: 0)
            }
            return classes
        }
    }
#endif

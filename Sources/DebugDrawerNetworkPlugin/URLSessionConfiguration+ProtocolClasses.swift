#if DEBUG
    import Foundation
    import ObjectiveC

    extension URLSessionConfiguration {
        /// The `protocolClasses` getter and its replacement, which `NetworkInterception` exchanges
        /// so every `URLSessionConfiguration` (`.default`, `.ephemeral`, custom) lists the
        /// plugin's URL protocol first. `URLProtocol.registerClass` alone only covers
        /// `URLSession.shared`.
        static var protocolClassesMethods: (getter: Method, replacement: Method)? {
            guard let getter = class_getInstanceMethod(self, #selector(getter: protocolClasses)),
                  let replacement = class_getInstanceMethod(self, #selector(getter: debugDrawerProtocolClasses))
            else { return nil }
            return (getter, replacement)
        }

        @objc private var debugDrawerProtocolClasses: [AnyClass]? {
            // After the exchange, this calls the original getter. Left in place by an uninstall
            // (other code replaced the getter again since), it adds nothing.
            guard !NetworkInterception.isUninstalled else { return self.debugDrawerProtocolClasses }
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

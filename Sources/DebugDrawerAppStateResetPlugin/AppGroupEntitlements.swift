#if DEBUG
    import Foundation
    #if os(macOS)
        import Security
    #else
        import MachO
    #endif

    // A copy of the Databases plugin's: plugins depend on core alone, and sixty lines cost less
    // than a shared module the charter rules out.

    /// The app groups the running app's entitlements name, read where each platform keeps them:
    /// on the Mac from the app's code signature (`SecTask`); on a simulator from the entitlements
    /// Xcode and Bazel link into the executable's `__TEXT,__entitlements` section; on a device
    /// from the provisioning profile the app was signed with (`embedded.mobileprovision`).
    enum AppGroupEntitlements {
        /// The key the entitlement is stored under.
        static let key = "com.apple.security.application-groups"

        /// The app group identifiers, sorted; empty when the app belongs to none.
        static func identifiers() -> [String] {
            #if os(macOS)
                let task = SecTaskCreateFromSelf(nil)
                let value = task.flatMap { SecTaskCopyValueForEntitlement($0, key as CFString, nil) }
                return ((value as? [String]) ?? []).sorted()
            #else
                let entitlements = linkedEntitlements() ?? provisionedEntitlements() ?? [:]
                return ((entitlements[key] as? [String]) ?? []).sorted()
            #endif
        }

        #if !os(macOS)
            /// The entitlements linked into the main executable, as a simulator build has them.
            private static func linkedEntitlements() -> [String: Any]? {
                guard let header = _dyld_get_image_header(0) else { return nil }
                var size: UInt = 0
                #if _pointerBitWidth(_64)
                    let section = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
                        getsectiondata($0, "__TEXT", "__entitlements", &size)
                    }
                #else
                    let section = getsectiondata(header, "__TEXT", "__entitlements", &size)
                #endif
                guard let section, size > 0 else { return nil }
                return dictionary(from: Data(bytes: section, count: Int(size)))
            }

            /// The `Entitlements` of the provisioning profile in the app's bundle, as a device
            /// build has it. The profile is a signed message around a property list, which is read
            /// from between its `<?xml` and `</plist>`.
            private static func provisionedEntitlements() -> [String: Any]? {
                guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
                      let data = try? Data(contentsOf: url),
                      let start = data.range(of: Data("<?xml".utf8)),
                      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex)
                else { return nil }
                return dictionary(from: data[start.lowerBound ..< end.upperBound])?["Entitlements"] as? [String: Any]
            }

            private static func dictionary(from data: Data) -> [String: Any]? {
                (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
            }
        #endif
    }
#endif

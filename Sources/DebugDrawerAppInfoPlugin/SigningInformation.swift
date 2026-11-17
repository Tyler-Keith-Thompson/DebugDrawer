#if DEBUG
    import Foundation
    #if os(macOS)
        import Security
    #else
        import MachO
    #endif

    /// Where App Info reads how the app was signed: the embedded provisioning profile's bytes and
    /// the entitlements the app runs with. Tests pass a fake.
    protocol SigningInformation {
        /// The bytes of the provisioning profile in the app's bundle; `nil` when it holds none,
        /// as a simulator, App Store or Mac build signed without one doesn't.
        func embeddedProfile() -> Data?

        /// The entitlements read from the app itself; `nil` when it carries none this way, which on
        /// a device leaves the profile's.
        func entitlements() -> Entitlements?
    }

    /// The running app's signing, read where each platform keeps it.
    ///
    /// The entitlement-reading half is a copy of the one in Reset App State and Databases (their
    /// `AppGroupEntitlements`), widened to every key: plugins depend on core alone, and a few lines
    /// cost less than a shared module the charter rules out.
    struct _SigningInformation: SigningInformation {
        func embeddedProfile() -> Data? {
            #if os(macOS)
                let url = Bundle.main.bundleURL.appending(path: "Contents/embedded.provisionprofile")
            #else
                // Mac Catalyst isn't built for this plugin (CATALYST_MODULES), so the bundle is an
                // iOS one, its profile at the top level.
                guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
            #endif
            return try? Data(contentsOf: url)
        }

        func entitlements() -> Entitlements? {
            #if os(macOS)
                signedEntitlements().map { Entitlements(dictionary: $0, source: .codeSignature) }
            #else
                linkedEntitlements().map { Entitlements(dictionary: $0, source: .executable) }
            #endif
        }

        #if os(macOS)
            /// Every entitlement in the app's code signature. SecCodeCopySigningInformation lists
            /// them all; SecTaskCopyValuesForEntitlements, the other public route, answers only for
            /// keys named in advance, so it would miss one App Info has no label for.
            private func signedEntitlements() -> [String: Any]? {
                var code: SecCode?
                var staticCode: SecStaticCode?
                var information: CFDictionary?
                guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
                      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
                      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSRequirementInformation), &information)
                      == errSecSuccess
                else { return nil }
                return (information as? [String: Any])?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
            }
        #else
            /// The entitlements linked into the main executable, as a simulator build has them
            /// (Xcode and Bazel both embed them, since a simulator app has no profile); a device
            /// build keeps them in its signature, which iOS gives no public API to read.
            private func linkedEntitlements() -> [String: Any]? {
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
                return (try? PropertyListSerialization.propertyList(from: Data(bytes: section, count: Int(size)), format: nil)) as? [String: Any]
            }
        #endif
    }
#endif

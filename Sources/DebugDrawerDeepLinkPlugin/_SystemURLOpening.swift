#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Foundation

    /// The system's own opener: `NSWorkspace` on the Mac, `UIApplication` on iOS.
    ///
    /// On the Mac a URL of a scheme the app declares opens in this copy of the app, rather than
    /// in whichever installed copy Launch Services picks for the scheme. No public API does that
    /// on iOS, where the system picks.
    struct _SystemURLOpening: SystemURLOpening {
        /// The schemes the app declares, lowercased.
        let appSchemes: Set<String>

        init(appSchemes: Set<String> = Set(DeepLinkPreset.bundleURLSchemes.compactMap { $0.url.scheme?.lowercased() })) {
            self.appSchemes = appSchemes
        }

        func open(_ url: URL) async throws {
            #if os(macOS)
                let configuration = NSWorkspace.OpenConfiguration()
                // The plugin shows the error itself, rather than the system's "no application" alert.
                configuration.promptsUserIfNeeded = false
                if let scheme = url.scheme?.lowercased(), appSchemes.contains(scheme) {
                    _ = try await NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL, configuration: configuration)
                    return
                }
                guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                    throw NoApplication(scheme: url.scheme)
                }
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            #elseif os(iOS)
                // A Mac Catalyst app takes this path too: UIApplication opens the URL there as well.
                // UIKit says only whether it opened the URL, false when no installed app takes it.
                guard await UIApplication.shared.open(url) else {
                    throw NoApplication(scheme: url.scheme)
                }
            #else
                throw NoApplication(scheme: url.scheme)
            #endif
        }
    }

    extension _SystemURLOpening {
        /// No installed app opens the URL.
        struct NoApplication: LocalizedError, Equatable {
            let scheme: String?

            var errorDescription: String? {
                scheme.map { "no installed app opens \($0): URLs" } ?? "the URL has no scheme"
            }
        }
    }
#endif

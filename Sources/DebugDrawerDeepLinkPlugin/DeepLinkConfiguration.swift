#if DEBUG
    import Foundation

    // What `installDeepLink` passes, held by the plugin and handed to the model as a drawer
    // installs it, so `DeepLinkModel.shared` serves whichever drawer installed it last. Not part of
    // the snapshot: handlers can't be encoded, and a viewer elsewhere only sees what they did.

    /// The presets the Deep Link Tester lists and where it sends what it opens and continues.
    struct DeepLinkConfiguration {
        /// The URLs listed under Presets.
        var presets: [DeepLinkPreset]
        /// Where continued activities go.
        var delivery: any UserActivityDelivering
        /// Where opened URLs go, in place of the system, when given; it returns whether it
        /// handled the URL.
        var openURL: (@MainActor (URL) -> Bool)?

        /// The app's own URL schemes as presets, URLs opened by the system, and activities
        /// continued in the app's scene or app delegate.
        static var standard: Self {
            Self(presets: DeepLinkPreset.bundleURLSchemes, delivery: _UserActivityDelivering(handler: nil), openURL: nil)
        }
    }
#endif

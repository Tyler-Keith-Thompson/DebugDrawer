import Foundation

// Public because it is `DeepLinkModel`'s `Command`, and opaque: an enum's cases share its access
// level, and an activity is the plugin's own type, so the public type is a struct around the
// internal enum. The mode picker and the activity being composed stay in the form: they only
// shape what the next send carries.

#if DEBUG
    /// Something the Deep Link Tester's view asks ``DeepLinkModel`` to do: change the typed URL,
    /// open a URL, continue an activity or clear the history. `Codable`, so a transport can carry
    /// it.
    public struct DeepLinkCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Puts the text in the URL field.
            case setURLText(String)
            /// Records the URL, then hands it to the `openURL` handler, or without one to the
            /// system.
            case open(URL)
            /// Records the activity, then hands it to the app's continuation path.
            case `continue`(DeepLinkActivity)
            /// Forgets every URL opened and activity continued, here and in the store.
            case clearHistory
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds open no URLs: this stand-in asks for nothing.
    public struct DeepLinkCommand: Codable, Sendable {}
#endif

import Foundation

// Public because it is `ViewInspectorModel`'s `Command`, and opaque: the actions it wraps stay
// internal, as their payloads (a grid color) are the plugin's own. An enum's cases share its
// access level, so the public type is a struct around the internal enum.

#if DEBUG
    /// Something the View Inspector plugin's view asks ``ViewInspectorModel`` to do: flip an
    /// overlay, slow the animations, flash or reset the render counts, snapshot the view
    /// hierarchy. `Codable`, so a transport can carry it.
    public struct ViewInspectorCommand: Codable, Sendable {
        /// What to do, by the part of the plugin it changes.
        enum Action: Codable, Sendable {
            case overlays(Overlays)
            case renders(Renders)
            case hierarchy(Hierarchy)
        }

        /// A change to what is drawn over the app's windows, or how fast they animate.
        enum Overlays: Codable, Sendable {
            case setBordersEnabled(Bool)
            case setGridEnabled(Bool)
            case setGridSpacing(Double)
            case setGridColor(ViewBorderController.GridColor)
            case setGridOpacity(Double)
            case setClickIndicatorEnabled(Bool)
            case setAnimationSpeed(Double)
        }

        /// A change to the render counts of the views tracked with `.trackRenders(_:)`.
        enum Renders: Codable, Sendable {
            case setFlashing(Bool)
            /// Forgets every count.
            case reset
        }

        /// A change to the view hierarchy snapshot.
        enum Hierarchy: Codable, Sendable {
            /// Reads the key window's hierarchy; with no key window, keeps what is shown.
            case snapshot
            /// Lets go of the hierarchy read.
            case collapse
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds inspect nothing: this stand-in asks for nothing.
    public struct ViewInspectorCommand: Codable, Sendable {}
#endif

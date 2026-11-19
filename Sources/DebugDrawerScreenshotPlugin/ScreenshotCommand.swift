import Foundation

// Public because it is `ScreenshotModel`'s `Command`, and opaque: an enum's cases share its access
// level, and a failure is the plugin's own type, so the public type is a struct around the internal
// enum. Copying to the clipboard isn't one: the view writes the clipboard and reports it done with
// `copied`, and the save panel a refused save falls back to is the view's, which reports where the
// file went with `exported`.

#if DEBUG
    /// Something the Screenshot plugin's view asks ``ScreenshotModel`` to do: capture the app's
    /// window, save or copy the capture, clear it, or whether to hide the drawer. `Codable`, so a
    /// transport can carry it.
    public struct ScreenshotCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Hides the drawer while capturing, or leaves it shown.
            case setHidesDrawer(Bool)
            /// Captures the app's key window, dropping the last capture.
            case capture
            /// Writes the last capture to the Desktop; with no capture, does nothing.
            case save
            /// Asks the view to put the last capture on the clipboard; with no capture, does nothing.
            case copy
            /// The view put the last capture on the clipboard.
            case copied
            /// The user saved the capture the Desktop refused at the location picked.
            case exported(path: String)
            /// Saving at the location picked failed.
            case exportFailed(String)
            /// The user closed the save panel without saving.
            case cancelExport
            /// Drops the last capture and where it stands.
            case clear
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds capture nothing: this stand-in asks for nothing.
    public struct ScreenshotCommand: Codable, Sendable {}
#endif

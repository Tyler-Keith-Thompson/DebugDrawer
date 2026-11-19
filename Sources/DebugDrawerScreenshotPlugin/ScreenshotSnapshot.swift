import Foundation

// Public because it is `ScreenshotModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. The last capture travels as PNG bytes with
// its size and scale, not as an image object, so it encodes; the view decodes it to draw.

#if DEBUG
    /// Everything the Screenshot plugin shows, as a value: whether a capture hides the drawer,
    /// the last capture and where it stands.
    ///
    /// ``ScreenshotModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport
    /// can carry it.
    public struct ScreenshotSnapshot: Codable, Equatable, Sendable {
        /// Whether the drawer hides while a capture is taken. The HUD always does.
        var hidesDrawer = true
        /// The last capture, or `nil` before the first, while a new one is taken, and once cleared.
        var capture: ScreenshotCapture?
        /// Where the last capture stands.
        var status = ScreenshotStatus.ready
    }
#else
    /// Release builds capture nothing: this stand-in holds nothing.
    public struct ScreenshotSnapshot: Codable, Equatable, Sendable {}
#endif

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif
import DebugDrawer

extension ScreenshotPlugin: DebugDrawerReportContributor {
    /// Adds the key window, captured now, as `screenshot.png`; with no key window, nothing. In
    /// release builds it adds nothing.
    public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        #if DEBUG && os(macOS)
            Self.contribute(capturing: NSApp?.keyWindow, to: &report)
        #elseif DEBUG && os(iOS)
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .windows.first(where: \.isKeyWindow)
            Self.contribute(capturing: window, to: &report)
        #endif
    }
}

#if DEBUG
    extension ScreenshotPlugin {
        #if os(macOS)
            /// Adds `window`'s content as `screenshot.png`, at the window's backing scale; a
            /// missing window, or one with nothing to draw, adds nothing.
            @MainActor static func contribute(capturing window: NSWindow?, to report: inout DebugDrawerReport) {
                guard let window,
                      let png = WindowCapture.bitmap(of: window)?.representation(using: .png, properties: [:])
                else { return }
                report.add(png: png, named: "screenshot.png")
            }
        #elseif os(iOS)
            /// Adds `window`, sheets and alerts included, as `screenshot.png`; a missing window adds
            /// nothing.
            @MainActor static func contribute(capturing window: UIWindow?, to report: inout DebugDrawerReport) {
                guard let window, let png = WindowCapture.image(of: window).pngData() else { return }
                report.add(png: png, named: "screenshot.png")
            }
        #endif
    }
#endif

#if DEBUG && (os(macOS) || os(iOS))
    import DebugDrawer
    import SwiftUI
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif

    /// The View Inspector's overlay windows, one over each of the app's windows on the Mac and one
    /// over each scene on iOS, each with what it draws.
    ///
    /// Nothing here keeps one of the app's views or windows: each overlay holds its host weakly,
    /// and the outlines and grids are read into values on each refresh.
    @MainActor
    final class InspectorOverlays {
        #if os(macOS)
            typealias Host = NSWindow
        #else
            typealias Host = UIWindowScene
        #endif

        /// One overlay window and what it draws.
        struct Overlay {
            weak var host: Host?
            let window: DrawerOverlayWindow
            let model: InspectorOverlayModel
        }

        private var overlays: [ObjectIdentifier: Overlay] = [:]

        /// The overlay over `host`, or `nil` when it has none.
        func existing(over host: Host) -> Overlay? {
            overlays[ObjectIdentifier(host)].flatMap { $0.host === host ? $0 : nil }
        }

        /// The overlay over `host`, made the first time it is asked for.
        func overlay(over host: Host) -> Overlay {
            if let overlay = existing(over: host) { return overlay }
            let model = InspectorOverlayModel()
            #if os(macOS)
                let window = DrawerOverlayWindow(over: host, content: InspectorOverlayView(model: model))
            #else
                let window = DrawerOverlayWindow(scene: host, content: InspectorOverlayView(model: model))
            #endif
            let overlay = Overlay(host: host, window: window, model: model)
            overlays[ObjectIdentifier(host)]?.window.remove()
            overlays[ObjectIdentifier(host)] = overlay
            return overlay
        }

        /// Removes every overlay whose host is gone or isn't in `hosts`.
        func keep(only hosts: [Host]) {
            let kept = Set(hosts.map(ObjectIdentifier.init))
            for (id, overlay) in overlays where overlay.host == nil || !kept.contains(id) {
                overlay.window.remove()
                overlays[id] = nil
            }
        }

        /// Removes every overlay.
        func removeAll() {
            keep(only: [])
        }
    }
#endif

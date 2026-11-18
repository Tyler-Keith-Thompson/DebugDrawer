import AppKit
import DebugDrawer
import SwiftUI

// More than one window: each has a drawer of its own, toggle() acts on the key window's, and each
// window's content registers a local plugin naming it, which only that window's drawer lists.

/// The app's SwiftUI windows past the first, each showing the example content under a name of its
/// own, kept until they close.
@MainActor
final class ExampleWindows: NSObject {
    /// Launched with this argument, the app opens a second window, then brings the first back in
    /// front, so the key window is not the last one opened; with -OpenDebugDrawer, the drawer opens
    /// in the key window only.
    static let newWindowArgument = "-NewWindow"
    /// Launched with this argument too, the drawer opens in the second window, through
    /// `toggle(in:)`, whichever window is key.
    static let openInNewWindowArgument = "-OpenDebugDrawerInNewWindow"

    private var windows: [NSWindow] = []

    /// Launched with -NewWindow, opens a second window, then brings `mainWindow` back in front: the
    /// drawer -OpenDebugDrawer opens is the key window's, not the last window's opened. With
    /// -OpenDebugDrawerInNewWindow, the second window's drawer opens through `toggle(in:)`.
    func openNewWindowIfAsked(behind mainWindow: NSWindow?) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(Self.newWindowArgument) else { return }
        newWindow()
        if arguments.contains(Self.openInNewWindowArgument), let window = windows.last {
            DebugDrawer.shared.toggle(in: window)
        }
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// Opens another window of the example content, with a drawer of its own.
    @objc func newWindow() {
        let number = windows.count + 2
        let window = Self.makeWindow(title: "DebugDrawer Example \(number)", autosaveName: "DebugDrawerExample\(number)")
        windows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windows.removeAll { $0 === window } }
        }
    }

    /// A window showing the example content, named `title`, made key and ordered in.
    static func makeWindow(title: String, autosaveName: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ExampleContentView(windowName: title))
        window.setFrameAutosaveName(autosaveName)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

/// A local plugin naming the window its view is in: listed only in that window's drawer.
struct ExampleWindowPlugin: DebugDrawerPlugin {
    let windowName: String

    var title: String {
        "This Window"
    }

    var icon: String {
        "macwindow"
    }

    var body: some View {
        DebugDrawerKeyValueRow("Window", value: windowName)
    }
}

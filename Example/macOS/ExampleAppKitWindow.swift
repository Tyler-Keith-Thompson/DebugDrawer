import AppKit
import DebugDrawer

// A window an AppKit app would make: a window controller whose content is a view controller of
// AppKit views, with no SwiftUI view in it and no `.debugDrawer()`. It attaches the drawer itself,
// and the drawer opens beside it with every global plugin, as beside the SwiftUI window.

/// A window whose content is AppKit's alone, with the drawer attached by `attach(to:)`.
@MainActor
final class ExampleAppKitWindowController: NSWindowController {
    /// Launched with this argument, the app opens this window in place of its SwiftUI one, so no
    /// window in the app has a SwiftUI root; with -OpenDebugDrawer too, its drawer opens.
    static let launchArgument = "-AppKitWindow"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AppKit Window"
        window.isReleasedWhenClosed = false
        window.contentViewController = ExampleAppKitViewController()
        window.center()
        window.setFrameAutosaveName("DebugDrawerExampleAppKit")
        self.init(window: window)
    }

    /// Launched with -OpenDebugDrawer, opens the drawer of the window shown at launch.
    static func openDrawerIfAsked() {
        if ProcessInfo.processInfo.arguments.contains("-OpenDebugDrawer"), !DebugDrawer.shared.isOpen {
            DebugDrawer.shared.toggle()
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // An AppKit app attaches the drawer once the window exists. The drawer detaches when the
        // window closes, so a window shown again attaches again; attaching it twice does nothing.
        guard let window else { return }
        DebugDrawer.shared.attach(to: window)
    }
}

/// The AppKit window's content: a title, a line on how it hosts the drawer, and a button that
/// toggles it.
final class ExampleAppKitViewController: NSViewController {
    override func loadView() {
        let title = NSTextField(labelWithString: "AppKit Window")
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.setAccessibilityRole(.staticText)

        let detail = NSTextField(
            wrappingLabelWithString: "No SwiftUI root: this window attaches the drawer with DebugDrawer.shared.attach(to:)."
        )
        detail.font = .preferredFont(forTextStyle: .body)
        detail.textColor = .secondaryLabelColor

        let toggle = NSButton(title: "Toggle Debug Drawer", target: self, action: #selector(toggleDebugDrawer))
        toggle.setAccessibilityLabel("Toggle Debug Drawer")

        let stack = NSStackView(views: [title, detail, toggle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Sized: a window takes its content view controller's view's size when it is set.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 480)
        ])
        view = container
    }

    @objc private func toggleDebugDrawer() {
        DebugDrawer.shared.toggle()
    }
}

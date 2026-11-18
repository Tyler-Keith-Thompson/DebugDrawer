import AppKit
import DebugDrawer
import ExamplePlugins
import ExampleTestBench

// An AppKit app with no SwiftUI root: an app delegate, a menu bar and a window controller whose
// content is AppKit views, with no `.debugDrawer()` anywhere. The window attaches the drawer with
// `attach(to:)`, and the drawer shows every global plugin. The Debug menu toggles the drawer and
// holds the test bench. The Deep Link Tester is installed with no handler, so an activity it sends
// goes to application(_:continue:restorationHandler:), as a Handoff or a Spotlight result does.

@main
@MainActor
final class ExampleAppKitAppDelegate: NSObject, NSApplicationDelegate {
    private let windowController = ExampleAppKitAppWindowController()

    static func main() {
        let app = NSApplication.shared
        let delegate = ExampleAppKitAppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
        ExamplePlugins.install()
        NSApp.mainMenu = mainMenu()
        windowController.showWindow(nil)
        // Launched with -OpenDebugDrawer, the window opens with the drawer open.
        if ProcessInfo.processInfo.arguments.contains("-OpenDebugDrawer"), !DebugDrawer.shared.isOpen {
            DebugDrawer.shared.toggle()
        }
        // Launched with -RunTestBench, runs those test bench actions, then opens the drawer at the
        // plugin -OpenDebugDrawerPlugin names.
        TestBench.runFromLaunchArguments()
    }

    func application(
        _: NSApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        windowController.showContinued(userActivity)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    /// The app menu, and a Debug menu: Toggle Debug Drawer (Ctrl-D) and the test bench.
    private func mainMenu() -> NSMenu {
        let menu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

        // Release builds have no drawer, so there Toggle Debug Drawer does nothing.
        let debugMenu = NSMenu(title: "Debug")
        let toggle = debugMenu.addItem(withTitle: "Toggle Debug Drawer", action: #selector(toggleDebugDrawer), keyEquivalent: "d")
        toggle.keyEquivalentModifierMask = .control
        toggle.target = self
        debugMenu.addItem(.separator())
        let testBench = TestBenchMenu.make { [windowController] action, outcome in
            windowController.showOutcome(outcome, of: action)
        }
        debugMenu.addItem(withTitle: "Test Bench", action: nil, keyEquivalent: "").submenu = testBench
        menu.addItem(withTitle: "Debug", action: nil, keyEquivalent: "").submenu = debugMenu
        return menu
    }

    @objc private func toggleDebugDrawer() {
        DebugDrawer.shared.toggle()
    }
}

/// The app's one window, which attaches the drawer when it is shown.
@MainActor
final class ExampleAppKitAppWindowController: NSWindowController {
    private let screen = ExampleAppKitAppViewController()

    convenience init() {
        self.init(window: nil)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DebugDrawer AppKit Example"
        window.isReleasedWhenClosed = false
        window.contentViewController = screen
        window.center()
        self.window = window
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // An AppKit app attaches the drawer once the window exists; attaching it twice does nothing.
        guard let window else { return }
        DebugDrawer.shared.attach(to: window)
    }

    func showOutcome(_ outcome: String, of action: TestBenchAction) {
        screen.show(label: "Last Test Bench Action", value: "\(action.plugin) › \(action.title): \(outcome)")
    }

    func showContinued(_ activity: NSUserActivity) {
        let detail = activity.webpageURL?.absoluteString ?? activity.activityType
        screen.show(label: "Last Continued Activity", value: "application(_:continue:): \(detail)")
    }
}

/// The window's content: what the app is, how to open the drawer and the test bench, and what the
/// last action or continued activity did.
final class ExampleAppKitAppViewController: NSViewController {
    private let heading = NSTextField(labelWithString: "Last Test Bench Action")
    private let detail = NSTextField(wrappingLabelWithString: "None yet: choose one from Debug › Test Bench.")

    override func loadView() {
        let title = NSTextField(labelWithString: "AppKit Example")
        title.font = .preferredFont(forTextStyle: .largeTitle)

        let explanation = NSTextField(
            wrappingLabelWithString: """
            No SwiftUI root: this window attaches the drawer with DebugDrawer.shared.attach(to:). \
            Press Ctrl-D or choose Debug › Toggle Debug Drawer to open it, and Debug › Test Bench for \
            actions that give each plugin something to show.
            """
        )
        explanation.font = .preferredFont(forTextStyle: .body)
        explanation.textColor = .secondaryLabelColor

        heading.font = .preferredFont(forTextStyle: .headline)
        detail.font = .monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
        detail.textColor = .secondaryLabelColor

        let toggle = NSButton(title: "Toggle Debug Drawer", target: self, action: #selector(toggleDebugDrawer))

        let stack = NSStackView(views: [title, explanation, toggle, heading, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(4, after: heading)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Sized: a window takes its content view controller's view's size when it is set.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 480))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40),
            explanation.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 560)
        ])
        view = container
    }

    func show(label: String, value: String) {
        loadViewIfNeeded()
        heading.stringValue = label
        detail.stringValue = value
    }

    @objc private func toggleDebugDrawer() {
        DebugDrawer.shared.toggle()
    }
}

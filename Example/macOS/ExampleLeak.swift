import AppKit
import CoreFoundation
import DebugDrawerLeakDetectorPlugin

// The iOS example has its own copy of this file, in UIKit: each app is its own module, and the
// examples share no code.

/// A screen with a retain cycle on demand, for the Leaks plugin to flag.
@MainActor
enum ExampleLeak {
    /// Launched with this argument, the app shows and closes a sheet without a leak, then the
    /// leaking one, once it first goes idle, so the leak can be checked without a hand.
    static let launchArgument = "-LeakOnLaunch"

    /// Shows the leaking screen as a sheet; its Close button dismisses it, and it stays alive.
    static func presentLeakingScreen() {
        presenter?.presentAsSheet(ExampleLeakingViewController())
    }

    /// Once the main run loop first waits, shows and closes each sheet in turn, each step when the
    /// one before has appeared or disappeared.
    static func presentAndDismissAfterLaunch() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { _, _ in
            DispatchQueue.main.async {
                guard let presenter else { return }
                let released = ExampleReleasedViewController()
                released.onAppear = { [unowned released] in presenter.dismiss(released) }
                released.onDisappear = {
                    let leaking = ExampleLeakingViewController()
                    leaking.onAppear = { [unowned leaking] in presenter.dismiss(leaking) }
                    presenter.presentAsSheet(leaking)
                }
                presenter.presentAsSheet(released)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// The main window's content: the view controller to present from.
    private static var presenter: NSViewController? {
        (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first)?.contentViewController
    }
}

/// The screen's data, which opts in to lifetime tracking: one should be alive at a time.
final class ExampleLeakModel {
    var refreshCount = 0

    init() {
        LeakDetector.trackLifetime(of: self)
    }
}

/// A sheet whose closure captures it strongly, so it outlives its dismissal, and its model with it.
final class ExampleLeakingViewController: NSViewController {
    /// Called once the sheet is on screen; -LeakOnLaunch closes it from here.
    var onAppear: (() -> Void)?
    private let model = ExampleLeakModel()
    private var onRefresh: (() -> Void)?

    override func loadView() {
        // The deliberate retain cycle: the screen holds the closure, and the closure holds the screen.
        onRefresh = { self.model.refreshCount += 1 }
        let label = NSTextField(
            wrappingLabelWithString: "This sheet leaks: a closure it keeps holds it. Close it, then open the drawer's Leaks plugin."
        )
        let close = NSButton(title: "Close", target: self, action: #selector(close))
        close.keyEquivalent = "\r"
        let stack = NSStackView(views: [label, close])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.frame = CGRect(x: 0, y: 0, width: 360, height: 140)
        view = stack
        onRefresh?()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        onAppear?()
        onAppear = nil
    }

    @objc private func close() {
        dismiss(self)
    }
}

/// The same sheet with the closure capturing it weakly: it deallocates once closed, and the plugin
/// doesn't list it.
final class ExampleReleasedViewController: NSViewController {
    /// Called once the sheet is on screen, and once it is gone.
    var onAppear: (() -> Void)?
    var onDisappear: (() -> Void)?
    private var refreshCount = 0
    private var onRefresh: (() -> Void)?

    override func loadView() {
        onRefresh = { [weak self] in self?.refreshCount += 1 }
        view = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 140))
        onRefresh?()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        onAppear?()
        onAppear = nil
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        onDisappear?()
        onDisappear = nil
    }
}

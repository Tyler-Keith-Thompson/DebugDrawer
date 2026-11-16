// The macOS example has its own copy of this file, in AppKit: each app is its own module, and the
// examples share no code. `bazel build //...` also compiles this library for the Mac, where UIKit
// doesn't exist, so that build gets a stand-in that does nothing.
#if canImport(UIKit)
    import CoreFoundation
    import DebugDrawerLeakDetectorPlugin
    import UIKit

    /// A screen with a retain cycle on demand, for the Leaks plugin to flag.
    @MainActor
    enum ExampleLeak {
        /// Launched with this argument, the app presents and dismisses a screen without a leak, then
        /// the leaking one, once it first goes idle, so the leak can be checked without a hand.
        static let launchArgument = "-LeakOnLaunch"

        /// Presents the leaking screen over the app; its Close button dismisses it, and it stays alive.
        static func presentLeakingScreen() {
            topViewController?.present(ExampleLeakingViewController(), animated: true)
        }

        /// Once the main run loop first waits, presents and dismisses each screen in turn, without
        /// animation, each step on the completion of the one before.
        static func presentAndDismissAfterLaunch() {
            let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { _, _ in
                DispatchQueue.main.async {
                    guard let presenter = topViewController else { return }
                    presenter.present(ExampleReleasedViewController(), animated: false) {
                        presenter.dismiss(animated: false) {
                            presenter.present(ExampleLeakingViewController(), animated: false) {
                                presenter.dismiss(animated: false)
                            }
                        }
                    }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        /// The view controller on top of the app's own window: the one to present from. The scene's
        /// first window rather than its key one, which is the drawer's while the drawer is open.
        private static var topViewController: UIViewController? {
            let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first
            return sequence(first: window?.rootViewController, next: { $0?.presentedViewController }).compactMap(\.self).last
        }
    }

    /// The screen's data, which opts in to lifetime tracking: one should be alive at a time.
    final class ExampleLeakModel {
        var refreshCount = 0

        init() {
            LeakDetector.trackLifetime(of: self)
        }
    }

    /// A screen whose closure captures it strongly, so it outlives its dismissal, and its model with it.
    final class ExampleLeakingViewController: UIViewController {
        private let model = ExampleLeakModel()
        private var onRefresh: (() -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            // The deliberate retain cycle: the screen holds the closure, and the closure holds the screen.
            onRefresh = { self.model.refreshCount += 1 }
            view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = "This screen leaks: a closure it keeps holds it. Close it, then open the drawer's Leaks plugin."
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            let close = UIButton(configuration: .borderedProminent(), primaryAction: UIAction(title: "Close") { [weak self] _ in
                self?.dismiss(animated: true)
            })
            let stack = UIStackView(arrangedSubviews: [label, close])
            stack.axis = .vertical
            stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            onRefresh?()
        }
    }

    /// The same screen with the closure capturing it weakly: it deallocates once dismissed, and the
    /// plugin doesn't list it.
    final class ExampleReleasedViewController: UIViewController {
        private var refreshCount = 0
        private var onRefresh: (() -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            onRefresh = { [weak self] in self?.refreshCount += 1 }
            view.backgroundColor = .systemBackground
            onRefresh?()
        }
    }
#else
    /// The Mac build's stand-in: the leaking screen is UIKit's.
    @MainActor
    enum ExampleLeak {
        static let launchArgument = "-LeakOnLaunch"

        static func presentLeakingScreen() {}

        static func presentAndDismissAfterLaunch() {}
    }
#endif

import DebugDrawer
import UIKit

/// The UIKit example's screen: the activity the scene continued last, a bar button that toggles
/// the drawer and one that shows the test bench.
final class ExampleUIKitViewController: UIViewController {
    private let continued = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIKit Example"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ladybug"),
            primaryAction: UIAction { _ in DebugDrawer.shared.toggle() }
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Debug Drawer"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Test Bench",
            primaryAction: UIAction { [weak self] _ in
                self?.navigationController?.pushViewController(ExampleUIKitTestBenchViewController(), animated: true)
            }
        )

        let heading = UILabel()
        heading.text = "Last Continued Activity"
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.adjustsFontForContentSizeCategory = true

        continued.text = "None"
        continued.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular))
        continued.adjustsFontForContentSizeCategory = true
        continued.textColor = .secondaryLabel
        continued.numberOfLines = 0

        let detail = UILabel()
        detail.text = "No SwiftUI root: the scene delegate attaches the drawer with DebugDrawer.shared.attach(to:)."
        detail.font = .preferredFont(forTextStyle: .body)
        detail.adjustsFontForContentSizeCategory = true
        detail.numberOfLines = 0

        let activity = UIStackView(arrangedSubviews: [heading, continued])
        activity.axis = .vertical
        activity.spacing = 2
        activity.isAccessibilityElement = true
        activity.accessibilityLabel = "Last Continued Activity"
        activity.accessibilityValue = continued.text

        let stack = UIStackView(arrangedSubviews: [detail, activity])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    /// Shows the activity the scene delegate continued: "scene(_:continue:): https://example.com/path".
    func showContinued(_ activity: NSUserActivity) {
        let userInfo = (activity.userInfo ?? [:])
            .map { ("\($0.key)", "\($0.value)") }
            .sorted { $0.0 < $1.0 }
            .map { "\($0) = \($1)" }
            .joined(separator: ", ")
        let detail = activity.webpageURL?.absoluteString ?? "\(activity.activityType) {\(userInfo)}"
        loadViewIfNeeded()
        continued.text = "scene(_:continue:): \(detail)"
        continued.superview?.accessibilityValue = continued.text
    }
}

import ExampleTestBench
import UIKit

/// The test bench in UIKit: a section per plugin, a row per action, and what the action did as the
/// row's secondary text.
final class ExampleUIKitTestBenchViewController: UITableViewController {
    private let sections = TestBench.sections
    private var outcomes: [TestBenchAction.ID: String] = [:]

    init() {
        super.init(style: .insetGrouped)
        title = "Test Bench"
    }

    // Made in code only; a storyboard never holds one, so this never runs.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("ExampleUIKitTestBenchViewController is made in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "action")
    }

    override func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].plugin
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].actions.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let action = sections[indexPath.section].actions[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "action", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = action.title
        content.textProperties.color = action.isDestructive ? .systemRed : .tintColor
        content.secondaryText = outcomes[action.id]
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessibilityTraits = .button
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let action = sections[indexPath.section].actions[indexPath.row]
        show("Running…", for: action, at: indexPath)
        Task {
            let outcome = await action.run()
            show(outcome, for: action, at: indexPath)
        }
    }

    private func show(_ outcome: String, for action: TestBenchAction, at indexPath: IndexPath) {
        outcomes[action.id] = outcome
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}

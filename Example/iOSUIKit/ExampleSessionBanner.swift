import Combine
import DebugDrawer
import ExampleTestBench
import UIKit

/// The UIKit host's indicator for a sidecar session: a banner shown for as long as the receiver's
/// published state is active, saying until when and what the session changed, with an End button.
/// The library draws nothing; the host styles its own. In release the sessions never open, so it
/// stays hidden.
final class ExampleSessionBanner: UIView {
    private let title = UILabel()
    private let detail = UILabel()
    private var observation: AnyCancellable?

    init(sessions: DebugDrawerSessions, logLevel: ExampleLogLevel) {
        super.init(frame: .zero)
        backgroundColor = .systemOrange
        isHidden = true

        let icon = UIImageView(image: UIImage(systemName: "antenna.radiowaves.left.and.right"))
        icon.tintColor = .white
        icon.isAccessibilityElement = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        title.text = "Debug session active"
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .white
        detail.font = .preferredFont(forTextStyle: .footnote)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = .white
        detail.numberOfLines = 0

        let labels = UIStackView(arrangedSubviews: [title, detail])
        labels.axis = .vertical
        labels.spacing = 2
        labels.isAccessibilityElement = true
        labels.accessibilityIdentifier = "SidecarSessionIndicator"

        var configuration = UIButton.Configuration.filled()
        configuration.title = "End Session"
        configuration.baseBackgroundColor = .black.withAlphaComponent(0.25)
        let end = UIButton(configuration: configuration, primaryAction: UIAction { _ in sessions.end() })
        end.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, labels, end])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        ])

        observation = sessions.$snapshot.combineLatest(logLevel.$snapshot)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak labels] state, level in
                self?.isHidden = !state.isActive
                guard let session = state.session else { return }
                let expires = session.expires.formatted(date: .omitted, time: .shortened)
                self?.detail.text = "Ends at \(expires) · Log level \(level.level)"
                labels?.accessibilityLabel = "Debug session active, ends at \(expires), log level \(level.level)"
            }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used: the banner is made in code")
    }
}

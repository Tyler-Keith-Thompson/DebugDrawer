import Combine
import DebugDrawerReceiver
import Foundation
import os

// The localization capability's model, and the lookup a host reads its strings through. A release
// build may not intercept anything (the charter's N1), and the drawer's live modes replace
// `Bundle`'s lookups, so here the host opts each string in by reading it through `localizedString`,
// which asks `Bundle` or Foundation as usual and then applies the mode a sidecar set. The mode is
// behind a lock, not on the main actor: strings are looked up on any thread and must return at
// once, which no hop to an actor allows. `OSAllocatedUnfairLock` rather than `Mutex`, which needs
// iOS 18. Rejected: replacing `Bundle`'s lookups as the plugin does (interception in a release
// build), a `Bundle` subclass the host passes to SwiftUI's `Text` (SwiftUI resolves a
// `LocalizedStringKey` through Foundation's private methods, not the public lookup a subclass
// overrides), and Foundation's `NSShowNonLocalizedStrings`-style defaults (read once at launch, so a
// session couldn't turn them on or, as it ends, off).

/// Show-keys and pseudo-localization for a production build, set from a sidecar during its
/// session: the strings the app reads through ``localizedString(forKey:value:table:bundle:)`` or
/// ``localizedString(_:)`` come back as their keys, or pseudo-localized, until the session ends.
///
/// The host reads the strings a reviewer should see through it, and enables the capability:
///
/// ```swift
/// receiver.enable(.localizationReview())
///
/// titleLabel.text = LocalizationReview.shared.localizedString(forKey: "settings.title")
/// Text(LocalizationReview.shared.localizedString("settings.title"))
/// ```
///
/// A sidecar connects to ``pluginID`` with ``Snapshot`` and ``Command``. Outside a session, and in
/// an app that hasn't enabled it, every command is refused and the mode is
/// ``Localization/Mode/standard``, so each string is what the bundle returns.
@MainActor
public final class LocalizationReview: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerLocalization", category: "LocalizationReview")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.LocalizationReview"

    /// The review the app's strings are read through: the one the capability drives unless the
    /// host passes another.
    public nonisolated static let shared = LocalizationReview()

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// What the strings read through the review show now.
        public var mode: Localization.Mode

        /// A snapshot.
        ///
        /// - Parameter mode: What the strings show.
        public init(mode: Localization.Mode) {
            self.mode = mode
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Shows the strings in `mode` from now on; ``Localization/Mode/standard`` shows their
        /// translations again, and is what the session's end performs.
        case setMode(Localization.Mode)
    }

    /// The mode now.
    @Published public private(set) var snapshot = Snapshot(mode: .standard)

    private nonisolated let currentMode = OSAllocatedUnfairLock(initialState: Localization.Mode.standard)

    /// A review showing each string's translation until a sidecar sets a mode.
    public nonisolated init() {}

    /// What the strings read through the review show now, read from any thread.
    public nonisolated var mode: Localization.Mode {
        currentMode.withLock { $0 }
    }

    /// Does what `command` asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .setMode(mode):
            guard mode != snapshot.mode else { return }
            currentMode.withLock { $0 = mode }
            snapshot = Snapshot(mode: mode)
            Self.logger.notice("Localization review mode is now \(mode.rawValue, privacy: .public)")
        }
    }

    /// The string `bundle` holds for `key`, as `Bundle.localizedString(forKey:value:table:)`
    /// returns it, in the review's mode: as it is, its key, or pseudo-localized. Format
    /// specifiers survive pseudo-localization, so the result still formats with the same
    /// arguments; a plural from a `.stringsdict` loses its variants, so read one through
    /// ``localizedString(_:)``, which formats it first.
    ///
    /// - Parameters:
    ///   - key: The string's key.
    ///   - value: What to return when the table has no `key`.
    ///   - table: The table's name; `nil` is `Localizable`.
    ///   - bundle: The bundle holding the table.
    /// - Returns: The string, in the mode.
    /// - Complexity: O(*n*) beyond the lookup, where *n* is the string's length.
    public nonisolated func localizedString(forKey key: String, value: String? = nil, table: String? = nil, bundle: Bundle = .main) -> String {
        let translation = bundle.localizedString(forKey: key, value: value, table: table)
        return Self.apply(mode, to: translation, key: key)
    }

    /// The string `resource` resolves to, as `String(localized:)` resolves it, with its arguments
    /// and plural variant, in the review's mode: as it is, the resource's key, or
    /// pseudo-localized.
    ///
    /// - Parameter resource: The string's key, table, bundle and arguments.
    /// - Returns: The string, in the mode.
    /// - Complexity: O(*n*) beyond the lookup, where *n* is the string's length.
    public nonisolated func localizedString(_ resource: LocalizedStringResource) -> String {
        let translation = String(localized: resource)
        return Self.apply(mode, to: translation, key: resource.key)
    }

    /// `translation` once `mode` applies: as it is, `key` (unless empty), or pseudo-localized.
    private nonisolated static func apply(_ mode: Localization.Mode, to translation: String, key: String) -> String {
        switch mode {
        case .standard:
            translation
        case .showingKeys:
            key.isEmpty ? translation : key
        case .pseudoLocalized:
            PseudoLocalization.transform(translation)
        }
    }
}

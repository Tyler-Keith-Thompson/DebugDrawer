import Combine
import DebugDrawerReceiver
import os

// The accessibility capability's model: what a sidecar overrides of the environment the host's
// SwiftUI views read, applied by `accessibilityEnvironmentOverrides(_:)` on the host's root view.
// Three settings, the ones an accessibility review of a production build checks first: Dynamic
// Type, Increase Contrast and Reduce Motion. Each is `nil` while the system's value applies. The
// model holds no SwiftUI types (a model's snapshot is Codable, and SwiftUI's `DynamicTypeSize`
// isn't), so `DynamicTypeSize` mirrors SwiftUI's, case for case; the modifier translates. It
// duplicates the Accessibility plugin's internal mirror rather than sharing it: the plugin's is
// debug-only and part of its own opaque snapshot. Rejected: color scheme, layout direction and
// locale (not accessibility settings a reviewer asks for, and a locale a sidecar picks would change
// the formats of what the app shows), and the plugin's whole set of settings (Bold Text, Reduce
// Transparency, Differentiate Without Color, Invert Colors can follow as the need shows).

/// Dynamic Type, Increase Contrast and Reduce Motion overridden from a sidecar during its
/// session, for the SwiftUI views under `accessibilityEnvironmentOverrides(_:)`.
///
/// The host applies the overrides to its root view and enables the capability:
///
/// ```swift
/// receiver.enable(.accessibilityEnvironmentOverrides())
///
/// ContentView()
///     .accessibilityEnvironmentOverrides()
/// ```
///
/// A sidecar connects to ``pluginID`` with ``Snapshot`` and ``Command``. Outside a session, and in
/// an app that hasn't enabled it, every command is refused and every value is the system's.
@MainActor
public final class AccessibilityEnvironmentOverrides: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerAccessibility", category: "AccessibilityEnvironmentOverrides")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.AccessibilityEnvironment"

    /// The overrides the capability drives and the modifier applies unless the host passes others.
    public static let shared = AccessibilityEnvironmentOverrides()

    /// SwiftUI's `DynamicTypeSize`, smallest first, as a value a sidecar can send.
    public enum DynamicTypeSize: String, CaseIterable, Codable, Sendable {
        /// SwiftUI's `xSmall`.
        case xSmall
        /// SwiftUI's `small`.
        case small
        /// SwiftUI's `medium`.
        case medium
        /// SwiftUI's `large`, the system's default.
        case large
        /// SwiftUI's `xLarge`.
        case xLarge
        /// SwiftUI's `xxLarge`.
        case xxLarge
        /// SwiftUI's `xxxLarge`, the largest size outside the accessibility sizes.
        case xxxLarge
        /// SwiftUI's `accessibility1`.
        case accessibility1
        /// SwiftUI's `accessibility2`.
        case accessibility2
        /// SwiftUI's `accessibility3`.
        case accessibility3
        /// SwiftUI's `accessibility4`.
        case accessibility4
        /// SwiftUI's `accessibility5`, the largest.
        case accessibility5
    }

    /// What a sidecar sees: each override, `nil` while the system's value applies.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The Dynamic Type size the views read, SwiftUI's `dynamicTypeSize`.
        public var dynamicTypeSize: DynamicTypeSize?
        /// Whether Increase Contrast is on, SwiftUI's `colorSchemeContrast` (`increased` or
        /// `standard`).
        public var increaseContrast: Bool?
        /// Whether Reduce Motion is on, SwiftUI's `accessibilityReduceMotion`.
        public var reduceMotion: Bool?

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - dynamicTypeSize: The Dynamic Type size, or `nil` for the system's.
        ///   - increaseContrast: Increase Contrast, or `nil` for the system's.
        ///   - reduceMotion: Reduce Motion, or `nil` for the system's.
        public init(dynamicTypeSize: DynamicTypeSize? = nil, increaseContrast: Bool? = nil, reduceMotion: Bool? = nil) {
            self.dynamicTypeSize = dynamicTypeSize
            self.increaseContrast = increaseContrast
            self.reduceMotion = reduceMotion
        }
    }

    /// What a sidecar asks. A `nil` value returns that setting to the system's.
    public enum Command: Codable, Equatable, Sendable {
        /// Overrides the Dynamic Type size, or returns it to the system's.
        case setDynamicTypeSize(DynamicTypeSize?)
        /// Overrides Increase Contrast, or returns it to the system's.
        case setIncreaseContrast(Bool?)
        /// Overrides Reduce Motion, or returns it to the system's.
        case setReduceMotion(Bool?)
        /// Returns every setting to the system's; what the session's end performs.
        case reset
    }

    /// The overrides now.
    @Published public private(set) var snapshot = Snapshot()

    /// Overrides with none set, so every value is the system's.
    public init() {}

    /// Does what `command` asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        var next = snapshot
        switch command {
        case let .setDynamicTypeSize(size): next.dynamicTypeSize = size
        case let .setIncreaseContrast(isOn): next.increaseContrast = isOn
        case let .setReduceMotion(isOn): next.reduceMotion = isOn
        case .reset: next = Snapshot()
        }
        // Only a change republishes, which re-renders the views under the overrides.
        guard next != snapshot else { return }
        snapshot = next
        Self.logger.notice("Accessibility environment overrides changed")
    }
}

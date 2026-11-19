import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The model composes the overrides rather than replacing them: `.debugAccessibilityOverrides()`
    // takes no arguments and applies `AccessibilityOverrides.shared`, so the overrides stay one
    // store for the process, and the model reads and writes them through `AccessibilityOverrideStore`.
    // The system's settings come from `AccessibilitySystemSettings` rather than the drawer view's
    // environment, so the model can say what they are without a view.

    /// The Accessibility plugin's state and behavior, without its views: the overrides, the
    /// system's own accessibility settings and the app's locales, read as an
    /// ``AccessibilitySnapshot`` and changed with an ``AccessibilityCommand``.
    ///
    /// The plugin makes one and joins its view to it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: AccessibilityModel())
    /// ```
    ///
    /// Every model edits ``AccessibilityOverrides/shared``, the overrides
    /// `.debugAccessibilityOverrides()` applies. Release builds get a stand-in whose snapshot holds
    /// nothing and which ignores every command.
    @MainActor
    public final class AccessibilityModel: DebugDrawerPluginModel {
        let overrides: any AccessibilityOverrideStore
        let system: any AccessibilitySystemSettings
        private var subscription: AnyCancellable?

        /// A model over ``AccessibilityOverrides/shared`` and the device's accessibility settings.
        public convenience init() {
            self.init(overrides: AccessibilityOverrides.shared, system: _AccessibilitySystemSettings())
        }

        /// - Parameters:
        ///   - overrides: Where the overrides live.
        ///   - system: The system's own accessibility settings.
        init(overrides: any AccessibilityOverrideStore, system: any AccessibilitySystemSettings) {
            self.overrides = overrides
            self.system = system
            subscription = overrides.changes.merge(with: system.changes)
                .sink { [weak self] in self?.objectWillChange.send() }
        }

        public var snapshot: AccessibilitySnapshot {
            AccessibilitySnapshot(overrides: overrides.values, system: system.values, availableLocales: overrides.localeIdentifiers)
        }

        public func perform(_ command: AccessibilityCommand) {
            switch command.action {
            case let .setColorScheme(scheme): overrides.values.colorScheme = scheme
            case let .setDynamicTypeSize(size): overrides.values.dynamicTypeSize = size
            case let .setLayoutDirection(direction): overrides.values.layoutDirection = direction
            case let .setLocale(identifier): overrides.values.locale = identifier
            case let .setSetting(setting, value): overrides.values[setting] = value
            case .reset: overrides.values = AccessibilityOverrideValues()
            }
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds override nothing: this stand-in's snapshot holds nothing, and it ignores every
    /// command.
    @MainActor
    public final class AccessibilityModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public init() {}

        /// Always empty.
        public var snapshot: AccessibilitySnapshot {
            AccessibilitySnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: AccessibilityCommand) {}
    }
#endif

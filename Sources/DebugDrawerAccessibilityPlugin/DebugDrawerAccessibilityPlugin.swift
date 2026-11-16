#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - View helper

    private extension View {
        @ViewBuilder
        func applyIf<V>(_ value: V?, transform: (Self, V) -> some View) -> some View {
            if let value {
                transform(self, value)
            } else {
                self
            }
        }
    }

    // MARK: - Conditional environment modifier

    /// Applies an environment override only when the value is non-nil.
    /// When nil, passes through without modifying the environment.
    /// Uses `_makeImmutable` pattern to keep view tree stable.
    private struct ConditionalEnvironment<V>: ViewModifier {
        let keyPath: WritableKeyPath<EnvironmentValues, V>
        let value: V?

        init(_ keyPath: WritableKeyPath<EnvironmentValues, V>, value: V?) {
            self.keyPath = keyPath
            self.value = value
        }

        func body(content: Content) -> some View {
            if let value {
                content.environment(keyPath, value)
            } else {
                content
            }
        }
    }

    // MARK: - Override state

    @MainActor
    public final class AccessibilityOverrides: ObservableObject {
        public static let shared = AccessibilityOverrides()

        @Published public var colorScheme: ColorScheme?
        @Published public var dynamicTypeSize: DynamicTypeSize?
        @Published public var layoutDirection: LayoutDirection?
        @Published public var locale: Locale?
        /// System accessibility settings; nil means the system's value is used.
        @Published public var reduceMotion: Bool?
        @Published public var increaseContrast: Bool?
        @Published public var boldText: Bool?
        @Published public var reduceTransparency: Bool?
        @Published public var differentiateWithoutColor: Bool?
        @Published public var invertColors: Bool?

        /// Available localizations discovered from the app bundle.
        public let availableLocales: [Locale]

        private init() {
            let ids = Bundle.main.localizations
                .filter { $0 != "Base" }
                .sorted()
            availableLocales = ids.map { Locale(identifier: $0) }
        }

        public func reset() {
            colorScheme = nil
            dynamicTypeSize = nil
            layoutDirection = nil
            locale = nil
            reduceMotion = nil
            increaseContrast = nil
            boldText = nil
            reduceTransparency = nil
            differentiateWithoutColor = nil
            invertColors = nil
        }

        public var hasOverrides: Bool {
            colorScheme != nil || dynamicTypeSize != nil ||
                layoutDirection != nil || locale != nil ||
                reduceMotion != nil || increaseContrast != nil || boldText != nil ||
                reduceTransparency != nil || differentiateWithoutColor != nil || invertColors != nil
        }
    }

    // MARK: - Environment modifier

    public struct AccessibilityOverridesModifier: ViewModifier {
        @ObservedObject private var overrides = AccessibilityOverrides.shared

        public init() {}

        public func body(content: Content) -> some View {
            // Each override is only applied when non-nil.
            // We use a single Group to keep the view tree shape stable
            // (no @ViewBuilder branching that would cause SwiftUI to
            // destroy and recreate the content).
            let modified = content
                .modifier(ConditionalEnvironment(\.dynamicTypeSize, value: overrides.dynamicTypeSize))
                .modifier(ConditionalEnvironment(\.layoutDirection, value: overrides.layoutDirection))
                .modifier(ConditionalEnvironment(\.locale, value: overrides.locale))
                // The public keys are get-only; SwiftUI reads them from these settable
                // underscored keys, which are what previews use to force a value.
                .modifier(ConditionalEnvironment(\._accessibilityReduceMotion, value: overrides.reduceMotion))
                .modifier(ConditionalEnvironment(\._colorSchemeContrast,
                                                 value: overrides.increaseContrast.map { $0 ? .increased : .standard }))
                // legibilityWeight is itself optional: wrap explicitly so "no override"
                // stays nil instead of becoming an override to nil.
                .modifier(ConditionalEnvironment(\.legibilityWeight,
                                                 value: overrides.boldText.map { Optional($0 ? LegibilityWeight.bold : .regular) }))
                .modifier(ConditionalEnvironment(\._accessibilityReduceTransparency, value: overrides.reduceTransparency))
                .modifier(ConditionalEnvironment(\._accessibilityDifferentiateWithoutColor,
                                                 value: overrides.differentiateWithoutColor))
                .modifier(ConditionalEnvironment(\._accessibilityInvertColors, value: overrides.invertColors))
                .preferredColorScheme(overrides.colorScheme)
            return modified
        }
    }

    public extension View {
        func debugAccessibilityOverrides() -> some View {
            modifier(AccessibilityOverridesModifier())
        }
    }

    // MARK: - Plugin

    public struct AccessibilityPlugin: DebugDrawerPlugin {
        public var title = "Accessibility"
        public var icon = "accessibility"

        public init() {}

        public var body: some View {
            AccessibilityPluginView()
        }
    }

    struct AccessibilityPluginView: View {
        @ObservedObject private var overrides = AccessibilityOverrides.shared

        // The drawer sits outside `.debugAccessibilityOverrides()`, so these are the system's values.
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.colorSchemeContrast) private var systemContrast
        @Environment(\.legibilityWeight) private var systemLegibilityWeight
        @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
        @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiateWithoutColor
        @Environment(\.accessibilityInvertColors) private var systemInvertColors

        private let typeSizes: [(String, DynamicTypeSize)] = [
            ("XS", .xSmall), ("S", .small), ("M", .medium),
            ("L", .large), ("XL", .xLarge), ("XXL", .xxLarge),
            ("XXXL", .xxxLarge), ("A1", .accessibility1),
            ("A2", .accessibility2), ("A3", .accessibility3),
            ("A4", .accessibility4), ("A5", .accessibility5),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                // Color scheme
                section("Color Scheme") {
                    Picker(selection: colorSchemeBinding) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    } label: { EmptyView() }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                }

                // Dynamic Type
                section("Dynamic Type") {
                    HStack {
                        Slider(
                            value: typeSizeSliderBinding,
                            in: 0 ... Double(typeSizes.count - 1),
                            step: 1
                        )
                        .controlSize(.small)

                        Text(currentSizeLabel)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }

                    // Preview text at current size
                    if let size = overrides.dynamicTypeSize {
                        Text("The quick brown fox")
                            .dynamicTypeSize(size)
                            .font(.body)
                            .padding(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                    }
                }

                // Layout direction
                section("Layout Direction") {
                    #if os(macOS)
                        Picker(selection: layoutBinding) {
                            Text("System").tag(0)
                            Text("LTR").tag(1)
                            Text("RTL").tag(2)
                        } label: { EmptyView() }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                    #else
                        // iOS has a SwiftUI bug where setting .leftToRight explicitly
                        // after .rightToLeft causes a 180-degree flip. Use a toggle instead.
                        Toggle("Right-to-Left", isOn: Binding(
                            get: { overrides.layoutDirection == .rightToLeft },
                            set: { overrides.layoutDirection = $0 ? .rightToLeft : nil }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    #endif
                }

                // Locale
                if !overrides.availableLocales.isEmpty {
                    section("Locale") {
                        Picker(selection: localeBinding) {
                            Text("System").tag("")
                            ForEach(overrides.availableLocales, id: \.identifier) { loc in
                                Text(localeName(loc))
                                    .tag(loc.identifier)
                            }
                        } label: { EmptyView() }
                            .controlSize(.small)
                    }
                }

                section("Accessibility Settings") {
                    AccessibilitySettingsSection(system: .init(
                        reduceMotion: systemReduceMotion,
                        increaseContrast: systemContrast == .increased,
                        boldText: systemLegibilityWeight == .bold,
                        reduceTransparency: systemReduceTransparency,
                        differentiateWithoutColor: systemDifferentiateWithoutColor,
                        invertColors: systemInvertColors
                    ))
                }

                if overrides.hasOverrides {
                    Divider()

                    HStack {
                        overrideBadges

                        Spacer()

                        Button("Reset All") { overrides.reset() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }

        // MARK: - Helpers

        private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                content()
            }
        }

        private var overrideBadges: some View {
            HStack(spacing: 4) {
                if overrides.colorScheme != nil {
                    badge(overrides.colorScheme == .dark ? "Dark" : "Light")
                }
                if let size = overrides.dynamicTypeSize,
                   let match = typeSizes.first(where: { $0.1 == size })
                {
                    badge(match.0)
                }
                if overrides.layoutDirection == .rightToLeft {
                    badge("RTL")
                }
                if overrides.layoutDirection == .leftToRight {
                    badge("LTR")
                }
                if let loc = overrides.locale {
                    badge(loc.identifier)
                }
                ForEach(settingBadges, id: \.self) { badge($0) }
            }
        }

        /// Short labels for the overridden accessibility settings, such as "Motion: On".
        private var settingBadges: [String] {
            [("Motion", overrides.reduceMotion), ("Contrast", overrides.increaseContrast),
             ("Bold", overrides.boldText), ("Transparency", overrides.reduceTransparency),
             ("No Color", overrides.differentiateWithoutColor), ("Invert", overrides.invertColors)]
                .compactMap { name, value in value.map { "\(name): \($0 ? "On" : "Off")" } }
        }

        private func badge(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(3)
        }

        private func localeName(_ locale: Locale) -> String {
            let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return "\(name) (\(locale.identifier))"
        }

        // MARK: - Bindings

        private var colorSchemeBinding: Binding<Int> {
            Binding(
                get: {
                    switch overrides.colorScheme {
                    case .none: 0
                    case .light: 1
                    case .dark: 2
                    default: 0
                    }
                },
                set: {
                    overrides.colorScheme = switch $0 {
                    case 1: .light
                    case 2: .dark
                    default: nil
                    }
                }
            )
        }


        private var layoutBinding: Binding<Int> {
            Binding(
                get: {
                    switch overrides.layoutDirection {
                    case .none: 0
                    case .leftToRight: 1
                    case .rightToLeft: 2
                    default: 0
                    }
                },
                set: {
                    overrides.layoutDirection = switch $0 {
                    case 1: .leftToRight
                    case 2: .rightToLeft
                    default: nil
                    }
                }
            )
        }

        private var typeSizeSliderBinding: Binding<Double> {
            Binding(
                get: {
                    if let size = overrides.dynamicTypeSize,
                       let idx = typeSizes.firstIndex(where: { $0.1 == size })
                    {
                        return Double(idx)
                    }
                    return 3
                },
                set: {
                    let idx = Int($0)
                    guard idx >= 0, idx < typeSizes.count else { return }
                    overrides.dynamicTypeSize = typeSizes[idx].1
                }
            )
        }

        private var currentSizeLabel: String {
            if let size = overrides.dynamicTypeSize,
               let match = typeSizes.first(where: { $0.1 == size })
            {
                return match.0
            }
            return "L"
        }

        private var localeBinding: Binding<String> {
            Binding(
                get: { overrides.locale?.identifier ?? "" },
                set: {
                    overrides.locale = $0.isEmpty ? nil : Locale(identifier: $0)
                }
            )
        }
    }

    // MARK: - System accessibility settings

    /// A row per system accessibility setting: its name, the system's value, and a System/On/Off override.
    struct AccessibilitySettingsSection: View {
        struct SystemValues: Equatable {
            var reduceMotion = false
            var increaseContrast = false
            var boldText = false
            var reduceTransparency = false
            var differentiateWithoutColor = false
            var invertColors = false
        }

        let system: SystemValues
        @ObservedObject var overrides = AccessibilityOverrides.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                row("Reduce Motion", system: system.reduceMotion, override: $overrides.reduceMotion)
                row("Increase Contrast", system: system.increaseContrast, override: $overrides.increaseContrast)
                row("Bold Text", system: system.boldText, override: $overrides.boldText)
                row("Reduce Transparency", system: system.reduceTransparency,
                    override: $overrides.reduceTransparency)
                row("Differentiate Without Color", system: system.differentiateWithoutColor,
                    override: $overrides.differentiateWithoutColor)
                row("Invert Colors", system: system.invertColors, override: $overrides.invertColors)
            }
        }

        private func row(_ title: String, system: Bool, override: Binding<Bool?>) -> some View {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 10))
                    Text("System: \(system ? "On" : "Off")")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(selection: Binding(
                    get: { override.wrappedValue.map { $0 ? 1 : 2 } ?? 0 },
                    set: { override.wrappedValue = $0 == 0 ? nil : $0 == 1 }
                )) {
                    Text("System").tag(0)
                    Text("On").tag(1)
                    Text("Off").tag(2)
                } label: { EmptyView() }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .fixedSize()
            }
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installAccessibility() {
            registerGlobal(AccessibilityPlugin())
        }
    }
#else
    import SwiftUI

    public extension View {
        func debugAccessibilityOverrides() -> some View { self }
    }
#endif

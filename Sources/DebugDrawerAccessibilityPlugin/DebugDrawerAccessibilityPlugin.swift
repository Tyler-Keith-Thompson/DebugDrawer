#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Plugin

    public struct AccessibilityPlugin: DebugDrawerPlugin {
        public var title = "Accessibility"
        public var category = "Interface"
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
            ("A4", .accessibility4), ("A5", .accessibility5)
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                // Color scheme
                section("Color Scheme") {
                    Picker("Color Scheme", selection: colorSchemeBinding) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel("Color Scheme")
                    .accessibilityElement(children: .contain)
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
                        .accessibilityLabel("Dynamic Type size")
                        .accessibilityValue(currentSizeLabel)

                        Text(currentSizeLabel)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        Button("System") { overrides.dynamicTypeSize = nil }
                            .font(.caption2)
                            .controlSize(.mini)
                            .disabled(overrides.dynamicTypeSize == nil)
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
                        Picker("Layout Direction", selection: layoutBinding) {
                            Text("System").tag(0)
                            Text("LTR").tag(1)
                            Text("RTL").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Layout Direction")
                        .accessibilityElement(children: .contain)
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
                        Picker("Locale", selection: localeBinding) {
                            Text("System").tag("")
                            ForEach(overrides.availableLocales, id: \.identifier) { loc in
                                Text(localeName(loc))
                                    .tag(loc.identifier)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Locale")
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
                    .accessibilityAddTraits(.isHeader)
                content()
            }
        }

        private var overrideBadges: some View {
            HStack(spacing: 4) {
                if overrides.colorScheme != nil {
                    badge(overrides.colorScheme == .dark ? "Dark" : "Light")
                }
                if let size = overrides.dynamicTypeSize,
                   let match = typeSizes.first(where: { $0.1 == size }) {
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
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
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
                       let idx = typeSizes.firstIndex(where: { $0.1 == size }) {
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
               let match = typeSizes.first(where: { $0.1 == size }) {
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installAccessibility() {
            registerGlobal(AccessibilityPlugin())
        }
    }
#endif

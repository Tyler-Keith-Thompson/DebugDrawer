import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

public struct AccessibilityPlugin: DebugDrawerPlugin {
    public var title = "Accessibility"
    public var category = "Interface"
    public var icon = "accessibility"

    public init() {}

    public var body: some View {
        #if DEBUG
            AccessibilityPluginView()
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    func installAccessibility() {
        #if DEBUG
            registerGlobal(AccessibilityPlugin())
        #endif
    }
}

#if DEBUG
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
            DebugDrawerSection("Color Scheme") {
                Picker("Color Scheme", selection: colorSchemeBinding) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Color Scheme")
                .accessibilityElement(children: .contain)
            }

            DebugDrawerSection("Dynamic Type") {
                HStack {
                    Slider(
                        value: typeSizeSliderBinding,
                        in: 0 ... Double(typeSizes.count - 1),
                        step: 1
                    )
                    .accessibilityLabel("Dynamic Type size")
                    .accessibilityValue(currentSizeLabel)

                    Text(currentSizeLabel)
                        .debugDrawerFont(.value)
                        .debugDrawerForegroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)

                    Button("System") { overrides.dynamicTypeSize = nil }
                        .debugDrawerButtonStyle(.borderless)
                        .disabled(overrides.dynamicTypeSize == nil)
                        .accessibilityLabel("System text size")
                }

                // A sample of text at the chosen size.
                if let size = overrides.dynamicTypeSize {
                    Text("The quick brown fox")
                        .dynamicTypeSize(size)
                        .debugDrawerFont(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            DebugDrawerSection("Layout Direction") {
                #if os(macOS)
                    Picker("Layout Direction", selection: layoutBinding) {
                        Text("System").tag(0)
                        Text("LTR").tag(1)
                        Text("RTL").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Layout Direction")
                    .accessibilityElement(children: .contain)
                #else
                    // iOS has a SwiftUI bug where setting .leftToRight explicitly
                    // after .rightToLeft causes a 180-degree flip. Use a toggle instead.
                    DebugDrawerRow("Right-to-Left", isOn: Binding(
                        get: { overrides.layoutDirection == .rightToLeft },
                        set: { overrides.layoutDirection = $0 ? .rightToLeft : nil }
                    ))
                #endif
            }

            if !overrides.availableLocales.isEmpty {
                DebugDrawerSection("Locale") {
                    DebugDrawerRow("Locale") {
                        Picker("Locale", selection: localeBinding) {
                            Text("System").tag("")
                            ForEach(overrides.availableLocales, id: \.identifier) { loc in
                                Text(localeName(loc))
                                    .tag(loc.identifier)
                            }
                        }
                        .accessibilityLabel("Locale")
                    }
                }
            }

            DebugDrawerSection("Accessibility Settings") {
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
                DebugDrawerSection("Overrides") {
                    ForEach(activeOverrides, id: \.label) { item in
                        DebugDrawerKeyValueRow(item.label, value: item.value)
                    }
                }
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Reset All", role: .destructive) { overrides.reset() }
                        .debugDrawerButtonStyle(.destructive)
                }
            }
        }

        // MARK: - Helpers

        /// What the developer has overridden, each as a label and its value ("Motion", "On").
        private var activeOverrides: [ActiveOverride] {
            var items: [ActiveOverride] = []
            if let scheme = overrides.colorScheme {
                items.append(ActiveOverride(label: "Color Scheme", value: scheme == .dark ? "Dark" : "Light"))
            }
            if let size = overrides.dynamicTypeSize,
               let match = typeSizes.first(where: { $0.1 == size }) {
                items.append(ActiveOverride(label: "Text Size", value: match.0))
            }
            if overrides.layoutDirection == .rightToLeft {
                items.append(ActiveOverride(label: "Layout", value: "RTL"))
            }
            if overrides.layoutDirection == .leftToRight {
                items.append(ActiveOverride(label: "Layout", value: "LTR"))
            }
            if let loc = overrides.locale {
                items.append(ActiveOverride(label: "Locale", value: loc.identifier))
            }
            let settings: [(String, Bool?)] = [
                ("Motion", overrides.reduceMotion), ("Contrast", overrides.increaseContrast),
                ("Bold", overrides.boldText), ("Transparency", overrides.reduceTransparency),
                ("No Color", overrides.differentiateWithoutColor), ("Invert", overrides.invertColors)
            ]
            items += settings.compactMap { name, value in
                value.map { ActiveOverride(label: name, value: $0 ? "On" : "Off") }
            }
            return items
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

    /// One override the developer has set, as the Overrides section lists it.
    private struct ActiveOverride {
        let label: String
        let value: String
    }

#endif

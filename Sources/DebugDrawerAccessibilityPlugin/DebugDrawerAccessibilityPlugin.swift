#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Override state

    @MainActor
    public final class AccessibilityOverrides: ObservableObject {
        public static let shared = AccessibilityOverrides()

        @Published public var colorScheme: ColorScheme?
        @Published public var dynamicTypeSize: DynamicTypeSize?
        @Published public var layoutDirection: LayoutDirection?
        @Published public var locale: Locale?

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
        }

        public var hasOverrides: Bool {
            colorScheme != nil || dynamicTypeSize != nil ||
                layoutDirection != nil || locale != nil
        }
    }

    // MARK: - Environment modifier

    public struct AccessibilityOverridesModifier: ViewModifier {
        @ObservedObject private var overrides = AccessibilityOverrides.shared

        public init() {}

        public func body(content: Content) -> some View {
            content
                .environment(\.dynamicTypeSize, overrides.dynamicTypeSize ?? .large)
                .environment(\.layoutDirection, overrides.layoutDirection ?? .leftToRight)
                .environment(\.locale, overrides.locale ?? .current)
                .preferredColorScheme(overrides.colorScheme)
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
        @State private var showAuditor = true

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
                    Picker(selection: layoutBinding) {
                        Text("System").tag(0)
                        Text("LTR").tag(1)
                        Text("RTL").tag(2)
                    } label: { EmptyView() }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
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

                #if os(macOS)
                    Divider()

                    // Auditor
                    DisclosureGroup("Accessibility Audit", isExpanded: $showAuditor) {
                        A11yAuditorView()
                            .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                #endif
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
                if let loc = overrides.locale {
                    badge(loc.identifier)
                }
            }
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installAccessibility() {
            registerGlobal(AccessibilityPlugin())
        }
    }
#endif

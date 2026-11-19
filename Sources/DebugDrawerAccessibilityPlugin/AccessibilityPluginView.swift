#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The Accessibility plugin's view. It draws ``AccessibilityModel``'s snapshots from its
    /// transport and sends it commands; the names, labels and the sample text are its own.
    struct AccessibilityPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<AccessibilitySnapshot, AccessibilityCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(
            transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<AccessibilitySnapshot, AccessibilityCommand> =
                .direct(to: AccessibilityModel())
        ) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            let overrides = snapshot.overrides

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
                        in: 0 ... Double(AccessibilityOverrideValues.DynamicTypeSize.allCases.count - 1),
                        step: 1
                    )
                    .accessibilityLabel("Dynamic Type size")
                    .accessibilityValue(currentSizeLabel)

                    Text(currentSizeLabel)
                        .debugDrawerFont(.value)
                        .debugDrawerForegroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)

                    Button("System") { send(.setDynamicTypeSize(nil)) }
                        .debugDrawerButtonStyle(.borderless)
                        .disabled(overrides.dynamicTypeSize == nil)
                        .accessibilityLabel("System text size")
                }

                // A sample of text at the chosen size.
                if let size = overrides.dynamicTypeSize {
                    Text("The quick brown fox")
                        .dynamicTypeSize(DynamicTypeSize(size))
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
                        get: { transport.snapshot.overrides.layoutDirection == .rightToLeft },
                        set: { send(.setLayoutDirection($0 ? .rightToLeft : nil)) }
                    ))
                #endif
            }

            if !snapshot.availableLocales.isEmpty {
                DebugDrawerSection("Locale") {
                    DebugDrawerRow("Locale") {
                        Picker("Locale", selection: localeBinding) {
                            Text("System").tag("")
                            ForEach(snapshot.availableLocales, id: \.self) { identifier in
                                Text(localeName(identifier))
                                    .tag(identifier)
                            }
                        }
                        .accessibilityLabel("Locale")
                    }
                }
            }

            DebugDrawerSection("Accessibility Settings") {
                AccessibilitySettingsSection(system: snapshot.system, transport: transport)
            }

            if overrides.hasOverrides {
                DebugDrawerSection("Overrides") {
                    ForEach(activeOverrides(overrides), id: \.label) { item in
                        DebugDrawerKeyValueRow(item.label, value: item.value)
                    }
                }
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Reset All", role: .destructive) { send(.reset) }
                        .debugDrawerButtonStyle(.destructive)
                }
            }
        }

        private func send(_ action: AccessibilityCommand.Action) {
            transport.send(AccessibilityCommand(action))
        }

        // MARK: - Helpers

        /// What the developer has overridden, each as a label and its value ("Motion", "On").
        private func activeOverrides(_ overrides: AccessibilityOverrideValues) -> [ActiveOverride] {
            var items: [ActiveOverride] = []
            if let scheme = overrides.colorScheme {
                items.append(ActiveOverride(label: "Color Scheme", value: scheme == .dark ? "Dark" : "Light"))
            }
            if let size = overrides.dynamicTypeSize {
                items.append(ActiveOverride(label: "Text Size", value: size.label))
            }
            if overrides.layoutDirection == .rightToLeft {
                items.append(ActiveOverride(label: "Layout", value: "RTL"))
            }
            if overrides.layoutDirection == .leftToRight {
                items.append(ActiveOverride(label: "Layout", value: "LTR"))
            }
            if let identifier = overrides.locale {
                items.append(ActiveOverride(label: "Locale", value: identifier))
            }
            items += AccessibilitySetting.allCases.compactMap { setting in
                overrides[setting].map { ActiveOverride(label: setting.shortTitle, value: $0 ? "On" : "Off") }
            }
            return items
        }

        private func localeName(_ identifier: String) -> String {
            let name = Locale.current.localizedString(forIdentifier: identifier) ?? identifier
            return "\(name) (\(identifier))"
        }

        // MARK: - Bindings

        private var colorSchemeBinding: Binding<Int> {
            Binding(
                get: {
                    switch transport.snapshot.overrides.colorScheme {
                    case .none: 0
                    case .light: 1
                    case .dark: 2
                    }
                },
                set: {
                    let scheme: AccessibilityOverrideValues.ColorScheme? = switch $0 {
                    case 1: .light
                    case 2: .dark
                    default: nil
                    }
                    send(.setColorScheme(scheme))
                }
            )
        }

        private var layoutBinding: Binding<Int> {
            Binding(
                get: {
                    switch transport.snapshot.overrides.layoutDirection {
                    case .none: 0
                    case .leftToRight: 1
                    case .rightToLeft: 2
                    }
                },
                set: {
                    let direction: AccessibilityOverrideValues.LayoutDirection? = switch $0 {
                    case 1: .leftToRight
                    case 2: .rightToLeft
                    default: nil
                    }
                    send(.setLayoutDirection(direction))
                }
            )
        }

        private var typeSizeSliderBinding: Binding<Double> {
            Binding(
                get: {
                    if let size = transport.snapshot.overrides.dynamicTypeSize,
                       let index = AccessibilityOverrideValues.DynamicTypeSize.allCases.firstIndex(of: size) {
                        return Double(index)
                    }
                    return Double(AccessibilityOverrideValues.DynamicTypeSize.allCases.firstIndex(of: .large) ?? 0)
                },
                set: {
                    let sizes = AccessibilityOverrideValues.DynamicTypeSize.allCases
                    let index = Int($0)
                    guard sizes.indices.contains(index) else { return }
                    send(.setDynamicTypeSize(sizes[index]))
                }
            )
        }

        private var currentSizeLabel: String {
            (transport.snapshot.overrides.dynamicTypeSize ?? .large).label
        }

        private var localeBinding: Binding<String> {
            Binding(
                get: { transport.snapshot.overrides.locale ?? "" },
                set: { send(.setLocale($0.isEmpty ? nil : $0)) }
            )
        }
    }

    /// One override the developer has set, as the Overrides section lists it.
    private struct ActiveOverride {
        let label: String
        let value: String
    }

    extension AccessibilityOverrideValues.DynamicTypeSize {
        /// The size as the slider names it ("XL", "A3").
        fileprivate var label: String {
            switch self {
            case .xSmall: "XS"
            case .small: "S"
            case .medium: "M"
            case .large: "L"
            case .xLarge: "XL"
            case .xxLarge: "XXL"
            case .xxxLarge: "XXXL"
            case .accessibility1: "A1"
            case .accessibility2: "A2"
            case .accessibility3: "A3"
            case .accessibility4: "A4"
            case .accessibility5: "A5"
            }
        }
    }

    extension AccessibilitySetting {
        /// The setting's name in the Overrides section ("Motion").
        fileprivate var shortTitle: String {
            switch self {
            case .reduceMotion: "Motion"
            case .increaseContrast: "Contrast"
            case .boldText: "Bold"
            case .reduceTransparency: "Transparency"
            case .differentiateWithoutColor: "No Color"
            case .invertColors: "Invert"
            }
        }
    }
#endif

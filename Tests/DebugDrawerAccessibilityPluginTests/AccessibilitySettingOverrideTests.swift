#if DEBUG
    import Combine
    @testable import DebugDrawerAccessibilityPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    // ViewInspector's offline environment doesn't resolve the get-only accessibility keys from
    // their underscored setters, so the probe is hosted for real and inspected through
    // `Inspection`, which hands back the live view with SwiftUI's resolved environment.
    @MainActor
    final class Inspection<V>: InspectionEmissary {
        let notice = PassthroughSubject<UInt, Never>()
        var callbacks: [UInt: (V) -> Void] = [:]

        func visit(_ view: V, _ line: UInt) {
            if let callback = callbacks.removeValue(forKey: line) {
                callback(view)
            }
        }
    }

    /// A host view that reads each accessibility setting the way an app does.
    struct Probe: View {
        let inspection = Inspection<Self>()

        @Environment(\.accessibilityReduceMotion) var reduceMotion
        @Environment(\.colorSchemeContrast) var contrast
        @Environment(\.legibilityWeight) var legibilityWeight
        @Environment(\.accessibilityReduceTransparency) var reduceTransparency
        @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
        @Environment(\.accessibilityInvertColors) var invertColors

        var body: some View {
            Text("probe")
                .onReceive(inspection.notice) { self.inspection.visit(self, $0) }
        }
    }

    /// One setting: its override, how the OS would apply a system value above the
    /// overrides, and how a host view reads it.
    private struct Setting {
        let name: String
        let override: ReferenceWritableKeyPath<AccessibilityOverrides, Bool?>
        let system: @MainActor @Sendable (AnyView, Bool) -> AnyView
        let read: @MainActor @Sendable (Probe) -> Bool
    }

    extension SharedAccessibilityOverrides {
        @MainActor
        @Suite(.timeLimit(.minutes(1)))
        struct AccessibilitySettingOverrideTests {
            private let overrides = AccessibilityOverrides(localizations: [])

            /// A model over `overrides`, for the views under test.
            private var model: AccessibilityModel {
                AccessibilityModel(overrides: overrides, system: _AccessibilitySystemSettings())
            }

            private let settings: [Setting] = [
                Setting(name: "Reduce Motion", override: \.reduceMotion,
                        system: { AnyView($0.environment(\._accessibilityReduceMotion, $1)) },
                        read: { $0.reduceMotion }),
                Setting(name: "Increase Contrast", override: \.increaseContrast,
                        system: { AnyView($0.environment(\._colorSchemeContrast, $1 ? .increased : .standard)) },
                        read: { $0.contrast == .increased }),
                Setting(name: "Bold Text", override: \.boldText,
                        system: { AnyView($0.environment(\.legibilityWeight, $1 ? .bold : .regular)) },
                        read: { $0.legibilityWeight == .bold }),
                Setting(name: "Reduce Transparency", override: \.reduceTransparency,
                        system: { AnyView($0.environment(\._accessibilityReduceTransparency, $1)) },
                        read: { $0.reduceTransparency }),
                Setting(name: "Differentiate Without Color", override: \.differentiateWithoutColor,
                        system: { AnyView($0.environment(\._accessibilityDifferentiateWithoutColor, $1)) },
                        read: { $0.differentiateWithoutColor }),
                Setting(name: "Invert Colors", override: \.invertColors,
                        system: { AnyView($0.environment(\._accessibilityInvertColors, $1)) },
                        read: { $0.invertColors })
            ]

            /// Hosts a probe under `.debugAccessibilityOverrides()` with `systemValue` applied
            /// above it, and expects what the probe reads.
            private func expectHostReads(_ expected: Bool, _ setting: Setting, systemValue: Bool, _ message: String,
                                         sourceLocation: SourceLocation = #_sourceLocation) async throws {
                let probe = Probe()
                let read = setting.read
                let description = "\(setting.name), system \(systemValue): \(message)"
                let overridden = AnyView(probe.modifier(AccessibilityOverridesModifier(overrides: overrides)))
                try await ViewHosting.host(setting.system(overridden, systemValue)) {
                    try await probe.inspection.inspect { view in
                        let actual = try read(view.actualView())
                        #expect(actual == expected, "\(description)", sourceLocation: sourceLocation)
                    }
                }
            }

            // ViewHosting hosts the view in a window, which UIKit can't make in xctest, which runs
            // package tests on Mac Catalyst without an NSApplication.
            #if !targetEnvironment(macCatalyst)
                @Test("A hosted view reads the override while one is set, and the system's value while it is cleared")
                func hostReadsOverrideWhenSetAndSystemValueWhenCleared() async throws {
                    for setting in settings {
                        for systemValue in [false, true] {
                            overrides[keyPath: setting.override] = nil
                            try await expectHostReads(systemValue, setting, systemValue: systemValue,
                                                      "cleared should read the system value")

                            overrides[keyPath: setting.override] = !systemValue
                            try await expectHostReads(!systemValue, setting, systemValue: systemValue,
                                                      "the override should win")

                            overrides[keyPath: setting.override] = nil
                            try await expectHostReads(systemValue, setting, systemValue: systemValue,
                                                      "clearing should restore the system value")
                        }
                    }
                }
            #endif

            @Test("Reset All clears every setting's override")
            func resetAllClearsEverySetting() {
                for setting in settings {
                    overrides[keyPath: setting.override] = true
                }
                #expect(overrides.hasOverrides)
                overrides.reset()
                for setting in settings {
                    #expect(overrides[keyPath: setting.override] == nil, "\(setting.name)")
                }
                #expect(!overrides.hasOverrides)
            }

            @Test("The settings section lists every setting with the system's value, On or Off")
            func settingsSectionListsEverySettingWithItsSystemValue() throws {
                let section = AccessibilitySettingsSection(system: .init(reduceMotion: true, increaseContrast: true), transport: .direct(to: model))
                let texts = try section.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                for setting in settings {
                    #expect(texts.contains(setting.name), "missing \(setting.name) in \(texts)")
                }
                #expect(texts.filter { $0 == "System: On" }.count == 2, "\(texts)")
                #expect(texts.filter { $0 == "System: Off" }.count == 4, "\(texts)")
            }

            @Test("A setting's picker sets the override On or Off, and System clears it")
            func settingsSectionPickerSetsAndClearsTheOverride() throws {
                let section = AccessibilitySettingsSection(system: .init(), transport: .direct(to: model))
                let pickers = try section.inspect().findAll(ViewType.Picker.self)
                #expect(pickers.count == settings.count)
                try pickers[0].select(value: 1)
                #expect(overrides.reduceMotion == true)
                try pickers[0].select(value: 2)
                #expect(overrides.reduceMotion == false)
                try pickers[0].select(value: 0)
                #expect(overrides.reduceMotion == nil)
            }

            @Test("The plugin shows the settings section, offers Reset All only while an override is set, and Reset All clears them")
            func pluginShowsSectionAndResetAllClearsOverrides() throws {
                let model = model
                let atRest = AccessibilityPluginView(transport: .direct(to: model))
                #expect(throws: Never.self) { try atRest.inspect().find(AccessibilitySettingsSection.self) }
                #expect(throws: (any Error).self) { try atRest.inspect().find(button: "Reset All") }
                overrides.reduceMotion = true
                overrides.invertColors = false
                let view = AccessibilityPluginView(transport: .direct(to: model))
                #expect(throws: Never.self) { try view.inspect().find(text: "Motion") }
                #expect(throws: Never.self) { try view.inspect().find(text: "Invert") }
                try view.inspect().find(button: "Reset All").tap()
                #expect(!overrides.hasOverrides)
            }
        }
    }
#endif

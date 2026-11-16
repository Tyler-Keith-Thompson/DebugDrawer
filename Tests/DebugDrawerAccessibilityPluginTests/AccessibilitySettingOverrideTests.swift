#if DEBUG
    import Combine
    @testable import DebugDrawerAccessibilityPlugin
    import SwiftUI
    import ViewInspector
    import XCTest

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

    @MainActor
    final class AccessibilitySettingOverrideTests: XCTestCase {
        private let overrides = AccessibilityOverrides.shared

        override func tearDown() async throws {
            await MainActor.run {
                AccessibilityOverrides.shared.reset()
                ViewHosting.expel()
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
        /// above it, and asserts what the probe reads.
        private func assertHostReads(_ expected: Bool, _ setting: Setting, systemValue: Bool,
                                     _ message: String, line: UInt = #line) async throws {
            let probe = Probe()
            ViewHosting.host(view: setting.system(AnyView(probe.debugAccessibilityOverrides()), systemValue))
            defer { ViewHosting.expel() }
            let read = setting.read
            let description = "\(setting.name), system \(systemValue): \(message)"
            try await probe.inspection.inspect { view in
                XCTAssertEqual(try read(view.actualView()), expected, description, line: line)
            }
        }

        func testHostReadsOverrideWhenSetAndSystemValueWhenCleared() async throws {
            for setting in settings {
                for systemValue in [false, true] {
                    overrides[keyPath: setting.override] = nil
                    try await assertHostReads(systemValue, setting, systemValue: systemValue,
                                              "cleared should read the system value")

                    overrides[keyPath: setting.override] = !systemValue
                    try await assertHostReads(!systemValue, setting, systemValue: systemValue,
                                              "the override should win")

                    overrides[keyPath: setting.override] = nil
                    try await assertHostReads(systemValue, setting, systemValue: systemValue,
                                              "clearing should restore the system value")
                }
            }
        }

        func testResetAllClearsEverySetting() {
            for setting in settings {
                overrides[keyPath: setting.override] = true
            }
            XCTAssertTrue(overrides.hasOverrides)
            overrides.reset()
            for setting in settings {
                XCTAssertNil(overrides[keyPath: setting.override], setting.name)
            }
            XCTAssertFalse(overrides.hasOverrides)
        }

        func testSettingsSectionListsEverySettingWithItsSystemValue() throws {
            let section = AccessibilitySettingsSection(system: .init(reduceMotion: true, increaseContrast: true))
            let texts = try section.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            for setting in settings {
                XCTAssertTrue(texts.contains(setting.name), "missing \(setting.name) in \(texts)")
            }
            XCTAssertEqual(texts.filter { $0 == "System: On" }.count, 2, "\(texts)")
            XCTAssertEqual(texts.filter { $0 == "System: Off" }.count, 4, "\(texts)")
        }

        func testSettingsSectionPickerSetsAndClearsTheOverride() throws {
            let section = AccessibilitySettingsSection(system: .init())
            let pickers = try section.inspect().findAll(ViewType.Picker.self)
            XCTAssertEqual(pickers.count, settings.count)
            try pickers[0].select(value: 1)
            XCTAssertEqual(overrides.reduceMotion, true)
            try pickers[0].select(value: 2)
            XCTAssertEqual(overrides.reduceMotion, false)
            try pickers[0].select(value: 0)
            XCTAssertNil(overrides.reduceMotion)
        }

        func testPluginShowsSectionAndResetAllClearsOverrides() throws {
            XCTAssertNoThrow(try AccessibilityPluginView().inspect().find(AccessibilitySettingsSection.self))
            XCTAssertThrowsError(try AccessibilityPluginView().inspect().find(button: "Reset All"))
            overrides.reduceMotion = true
            overrides.invertColors = false
            let view = AccessibilityPluginView()
            XCTAssertNoThrow(try view.inspect().find(text: "Motion: On"))
            XCTAssertNoThrow(try view.inspect().find(text: "Invert: Off"))
            try view.inspect().find(button: "Reset All").tap()
            XCTAssertFalse(overrides.hasOverrides)
        }
    }
#endif

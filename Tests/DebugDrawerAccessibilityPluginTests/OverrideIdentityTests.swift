#if DEBUG
    import Combine
    @testable import DebugDrawerAccessibilityPlugin
    import SwiftUI
    import ViewInspector
    import XCTest

    /// Counts how many times SwiftUI creates the host's state: once, unless the tree is rebuilt.
    @MainActor
    private final class Lifetime: ObservableObject {
        static var created = 0
        init() { Self.created += 1 }
    }

    /// A host view with state of its own, reporting its state and environment on every change.
    private struct StatefulHost: View {
        @StateObject private var lifetime = Lifetime()
        @State private var token = UUID()
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.layoutDirection) private var layoutDirection
        @Environment(\.locale) private var locale
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.legibilityWeight) private var legibilityWeight

        let reports: PassthroughSubject<(token: UUID, environment: String), Never>

        private var environment: String {
            "size=\(dynamicTypeSize) dir=\(layoutDirection) locale=\(locale.identifier) "
                + "motion=\(reduceMotion) bold=\(legibilityWeight == .bold)"
        }

        var body: some View {
            Text("host")
                .onAppear { reports.send((token, environment)) }
                .onChange(of: environment) { _, new in reports.send((token, new)) }
        }
    }

    @MainActor
    final class OverrideIdentityTests: XCTestCase {
        private let overrides = AccessibilityOverrides.shared
        private let reports = PassthroughSubject<(token: UUID, environment: String), Never>()
        private var tokens: [UUID] = []
        private var latest = ""
        private var cancellable: AnyCancellable?

        override func setUp() async throws {
            await MainActor.run {
                AccessibilityOverrides.shared.reset()
                Lifetime.created = 0
            }
        }

        override func tearDown() async throws {
            await MainActor.run {
                AccessibilityOverrides.shared.reset()
                ViewHosting.expel()
            }
        }

        /// Changes overrides, then waits until the hosted view reports an environment containing `expected`.
        private func change(_ apply: () -> Void, until expected: String, line: UInt = #line) async {
            let reported = expectation(description: "host sees \(expected)")
            reported.assertForOverFulfill = false
            if latest.contains(expected) { reported.fulfill() }
            cancellable = reports.sink { [weak self] report in
                self?.tokens.append(report.token)
                self?.latest = report.environment
                if report.environment.contains(expected) { reported.fulfill() }
            }
            apply()
            await fulfillment(of: [reported], timeout: 5)
        }

        func testTogglingOverridesKeepsHostState() async throws {
            await change({
                ViewHosting.host(view: StatefulHost(reports: reports).debugAccessibilityOverrides())
            }, until: "size=")
            let first = try XCTUnwrap(tokens.first)

            await change({ overrides.dynamicTypeSize = .accessibility2 }, until: "size=accessibility2")
            await change({ overrides.dynamicTypeSize = nil }, until: "size=large")
            await change({ overrides.layoutDirection = .rightToLeft }, until: "dir=rightToLeft")
            await change({ overrides.locale = Locale(identifier: "fr") }, until: "locale=fr")
            await change({ overrides.reduceMotion = true }, until: "motion=true")
            await change({ overrides.boldText = true }, until: "bold=true")
            await change({ overrides.reset() }, until: "size=large dir=leftToRight")

            XCTAssertEqual(Lifetime.created, 1, "the host's @StateObject was recreated: its tree was rebuilt")
            XCTAssertEqual(Set(tokens), [first], "the host's @State was reset: its tree was rebuilt")
        }

        /// Sets every override, then returns each one to System from its own control,
        /// checking that the others stay set.
        func testEachOverrideReturnsToSystemIndividually() throws {
            overrides.colorScheme = .dark
            overrides.dynamicTypeSize = .xLarge
            overrides.layoutDirection = .rightToLeft
            overrides.locale = Locale(identifier: "fr")
            overrides.reduceMotion = true
            overrides.increaseContrast = true
            overrides.boldText = false
            overrides.reduceTransparency = true
            overrides.differentiateWithoutColor = true
            overrides.invertColors = false

            var expectedSet = 10
            func setCount() -> Int {
                [overrides.colorScheme != nil, overrides.dynamicTypeSize != nil, overrides.layoutDirection != nil,
                 overrides.locale != nil, overrides.reduceMotion != nil, overrides.increaseContrast != nil,
                 overrides.boldText != nil, overrides.reduceTransparency != nil,
                 overrides.differentiateWithoutColor != nil, overrides.invertColors != nil].filter { $0 }.count
            }
            func returned(_ name: String, _ isNil: Bool, line: UInt = #line) {
                expectedSet -= 1
                XCTAssertTrue(isNil, "\(name) didn't return to System", line: line)
                XCTAssertEqual(setCount(), expectedSet, "returning \(name) to System changed another override", line: line)
            }

            let view = try AccessibilityPluginView().inspect()
            // Pickers in order: color scheme, layout direction (macOS), then the six settings.
            // The locale picker only exists when the bundle has localizations, so it's set directly.
            try view.find(button: "System").tap()
            returned("Dynamic Type", overrides.dynamicTypeSize == nil)

            let pickers = view.findAll(ViewType.Picker.self)
            try pickers[0].select(value: 0)
            returned("Color Scheme", overrides.colorScheme == nil)

            #if os(macOS)
                try pickers[1].select(value: 0)
            #else
                try view.find(ViewType.Toggle.self).tap()
            #endif
            returned("Layout Direction", overrides.layoutDirection == nil)

            let settings = try view.find(AccessibilitySettingsSection.self).findAll(ViewType.Picker.self)
            let settingValues: [(String, () -> Bool?)] = [
                ("Reduce Motion", { self.overrides.reduceMotion }),
                ("Increase Contrast", { self.overrides.increaseContrast }),
                ("Bold Text", { self.overrides.boldText }),
                ("Reduce Transparency", { self.overrides.reduceTransparency }),
                ("Differentiate Without Color", { self.overrides.differentiateWithoutColor }),
                ("Invert Colors", { self.overrides.invertColors })
            ]
            XCTAssertEqual(settings.count, settingValues.count)
            for (picker, (name, value)) in zip(settings, settingValues) {
                try picker.select(value: 0)
                returned(name, value() == nil)
            }

            XCTAssertNotNil(overrides.locale, "the locale should be the only override left")
        }
    }
#endif

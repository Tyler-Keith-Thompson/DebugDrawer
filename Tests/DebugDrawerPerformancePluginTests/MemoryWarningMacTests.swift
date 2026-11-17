// The Mac has no memory warning to simulate, so the plugin builds none there (MemoryWarning.swift
// sits under `#if os(iOS) || os(tvOS) || os(visionOS)`); this pins that its view offers none.
#if os(macOS)
    @testable import DebugDrawerPerformancePlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct MemoryWarningMacTests {
        @Test("On the Mac the plugin offers no memory warning")
        func noMemoryWarningOnTheMac() throws {
            let sut = PerformancePluginView()

            let buttons = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }
            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(!buttons.contains("Simulate Memory Warning"))
            #expect(!texts.contains { $0.localizedCaseInsensitiveContains("memory warning") })
        }
    }
#endif

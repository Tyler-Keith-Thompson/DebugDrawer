#if DEBUG && os(macOS)
    import DebugDrawer
    import DebugDrawerLocalization
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The Strings plugin as a function of the capability's snapshot.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarLocalizationReviewTests {
        @Test("The picker offers every mode, marks the app's, and picking one sends it")
        func pickerSendsMode() throws {
            var sent: [LocalizationReview.Command] = []
            let sut = LocalizationReviewSidecarView(snapshot: LocalizationReview.Snapshot(mode: .standard)) { sent.append($0) }

            let picker = try sut.inspect().find(ViewType.Picker.self)
            try picker.select(value: Localization.Mode.pseudoLocalized)
            try picker.select(value: Localization.Mode.showingKeys)

            #expect(sent == [.setMode(.pseudoLocalized), .setMode(.showingKeys)])
            #expect(throws: Never.self) { try picker.find(text: "Standard") }
            #expect(throws: Never.self) { try picker.find(text: "Pseudo-localized") }
            #expect(throws: Never.self) { try picker.find(text: "Keys") }
        }

        @Test("The shipped Strings plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.localizationReview

            #expect([sut.id, sut.title, sut.icon] == [LocalizationReview.pluginID, "Strings", "character.bubble"])
        }
    }
#endif

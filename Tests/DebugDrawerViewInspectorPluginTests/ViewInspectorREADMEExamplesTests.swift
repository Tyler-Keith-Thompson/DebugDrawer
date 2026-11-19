// The README's View Inspector example, verbatim, so the README cannot drift from the code. It
// lives here rather than in DebugDrawerTests, which links core alone. ViewInspector is linked on
// Apple platforms only, and the views are tested on the Mac.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerViewInspectorPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    // README: View Inspector: which views keep re-rendering
    struct OrderRow: View {
        let title: String
        let total: String

        var body: some View {
            HStack {
                Text(title)
                Spacer()
                Text(total)
            }
            .trackRenders("OrderRow")
        }
    }

    // In the suite that takes turns installing the plugin: the counts go to the tracker of the
    // drawer that installed it last, which another test's drawer of its own would otherwise be.
    extension RenderTrackingInstalls {
        @MainActor
        @Suite("README examples: View Inspector")
        struct ViewInspectorREADMEExamplesTests {
            @Test("View Inspector: a tracked row shows its title and total, and its body is counted under OrderRow")
            func trackRenders() throws {
                // The README's app installs the plugin at launch, which starts the counting.
                DebugDrawer.shared.installViewInspector()
                let sut = OrderRow(title: "Coffee beans", total: "$18.00")
                let before = RenderTracker.shared.counts["OrderRow", default: 0]
                let expectedTexts = ["Coffee beans", "$18.00"]

                let actualTexts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                let actual = RenderTracker.shared.counts["OrderRow", default: 0]

                #expect(actualTexts == expectedTexts)
                #expect(actual > before)
            }
        }
    }
#endif

// iOS's menus are wider than the Mac's and grow with Dynamic Type, so the editor is measured on
// the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerDeepLinkPlugin
    import SwiftUI
    import Testing
    import UIKit

    // The drawer is 340 points wide on iOS (DebugDrawerOverlay), and sets a plugin's body in by
    // 12 + 30 points at its leading edge and 12 at its trailing one (DrawerPluginSection), which
    // grow with the text to at most 1.25 times: below the accessibility sizes, where the editor's
    // rows can sit in columns, a plugin's body is 286 points wide at the default text size and no narrower than
    // 272.5 at any. Each size is measured at both.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserInfoEditorWidthTests {
        @Test(
            "In an iPad's drawer, a Boolean row fits the plugin's width at every text size below the accessibility ones",
            arguments: [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge], [CGFloat(286), 272.5]
        )
        func booleanRowFits(size: DynamicTypeSize, width: CGFloat) {
            let fields = [UserInfoField(key: "gift", kind: .boolean, isOn: false)]
            let controller = UIHostingController(rootView: UserInfoEditor(fields: .constant(fields))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            controller.safeAreaRegions = []

            let actual = controller.sizeThatFits(in: CGSize(width: width, height: 8000)).width

            #expect(actual <= width)
        }

        @Test(
            "In an iPad's drawer, a Boolean row beside a String row fits the plugin's width at every text size below the accessibility ones",
            arguments: [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge], [CGFloat(286), 272.5]
        )
        func booleanBesideStringFits(size: DynamicTypeSize, width: CGFloat) {
            let fields = [
                UserInfoField(kind: .boolean),
                UserInfoField(kind: .string)
            ]
            let controller = UIHostingController(rootView: UserInfoEditor(fields: .constant(fields))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            controller.safeAreaRegions = []

            let actual = controller.sizeThatFits(in: CGSize(width: width, height: 8000)).width

            #expect(actual <= width)
        }

        @Test(
            "In an iPad's drawer, rows of every type together fit the plugin's width at every text size below the accessibility ones",
            arguments: [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge], [CGFloat(286), 272.5]
        )
        func mixedRowsFit(size: DynamicTypeSize, width: CGFloat) {
            let fields = [
                UserInfoField(key: "orderID", kind: .number, text: "42"),
                UserInfoField(key: "title", kind: .string, text: "Ada's order"),
                UserInfoField(key: "gift", kind: .boolean, isOn: true)
            ]
            let controller = UIHostingController(rootView: UserInfoEditor(fields: .constant(fields))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            controller.safeAreaRegions = []

            let actual = controller.sizeThatFits(in: CGSize(width: width, height: 8000)).width

            #expect(actual <= width)
        }

        @Test("At the default text size in an iPad's drawer, rows of every type stay in columns, shorter than the rows stacked")
        func defaultSizeKeepsColumns() {
            let width: CGFloat = 286
            let fields = [
                UserInfoField(key: "orderID", kind: .number, text: "42"),
                UserInfoField(key: "title", kind: .string, text: "Ada's order"),
                UserInfoField(key: "gift", kind: .boolean, isOn: true)
            ]
            let controller = UIHostingController(rootView: UserInfoEditor(fields: .constant(fields))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, .large))
            controller.safeAreaRegions = []
            // Too narrow for the grid, so the rows stack.
            let stacked = controller.sizeThatFits(in: CGSize(width: 200, height: 8000)).height

            let actual = controller.sizeThatFits(in: CGSize(width: width, height: 8000)).height

            #expect(actual < stacked)
        }
    }
#endif

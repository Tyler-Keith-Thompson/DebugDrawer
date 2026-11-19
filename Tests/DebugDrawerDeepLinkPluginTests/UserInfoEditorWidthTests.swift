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
    //
    // SwiftUI sizes a view in whole pixels, so a width off the screen's pixel grid comes back
    // rounded to it: on a 3x iPhone, 272.5 points is 817.5 px and the editor measures 818 px
    // (272.67 points), while at 817 px it measures 817. So the widths are compared in pixels, the
    // limit rounded up to the pixel it ends in: at most part of one pixel over, never a point.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserInfoEditorWidthTests {
        @Test(
            "In an iPad's drawer, a Boolean row fits the plugin's width at every text size below the accessibility ones",
            arguments: [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge], [CGFloat(286), 272.5]
        )
        func booleanRowFits(size: DynamicTypeSize, width: CGFloat) throws {
            let fields = [UserInfoField(key: "gift", kind: .boolean, isOn: false)]
            let controller = UIHostingController(rootView: UserInfoEditor(fields: .constant(fields))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            controller.safeAreaRegions = []

            let actual = try Self.pixels(controller, fittingWidth: width)

            #expect(actual.width <= actual.limit)
        }

        @Test(
            "In an iPad's drawer, a Boolean row beside a String row fits the plugin's width at every text size below the accessibility ones",
            arguments: [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge], [CGFloat(286), 272.5]
        )
        func booleanBesideStringFits(size: DynamicTypeSize, width: CGFloat) throws {
            let fields = [
                UserInfoField(kind: .boolean),
                UserInfoField(kind: .string)
            ]
            let controller = UIHostingController(rootView: UserInfoEditor(fields: .constant(fields))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            controller.safeAreaRegions = []

            let actual = try Self.pixels(controller, fittingWidth: width)

            #expect(actual.width <= actual.limit)
        }

        @Test(
            "In an iPad's drawer, rows of every type together fit the plugin's width at every text size below the accessibility ones",
            arguments: [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge], [CGFloat(286), 272.5]
        )
        func mixedRowsFit(size: DynamicTypeSize, width: CGFloat) throws {
            let fields = [
                UserInfoField(key: "orderID", kind: .number, text: "42"),
                UserInfoField(key: "title", kind: .string, text: "Ada's order"),
                UserInfoField(key: "gift", kind: .boolean, isOn: true)
            ]
            let controller = UIHostingController(rootView: UserInfoEditor(fields: .constant(fields))
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, size))
            controller.safeAreaRegions = []

            let actual = try Self.pixels(controller, fittingWidth: width)

            #expect(actual.width <= actual.limit)
        }

        /// The editor's fitting width for `width` points, and `width` itself as the limit, both in
        /// pixels at the controller's display scale: the fitting width to the nearest pixel (it is
        /// on the grid already, give or take floating point), the limit rounded up to a whole pixel.
        static func pixels(_ controller: UIHostingController<some View>, fittingWidth width: CGFloat) throws -> (width: CGFloat, limit: CGFloat) {
            let scale = controller.traitCollection.displayScale
            try #require(scale > 0, "the controller has no display scale to measure pixels in")
            let fitting = controller.sizeThatFits(in: CGSize(width: width, height: 8000)).width
            return ((fitting * scale).rounded(), (width * scale).rounded(.up))
        }

        // This pins the iPad's layout. Mac Catalyst's editor comes out no shorter at 286 points than
        // at 200, where the iPad's rows stack.
        #if !targetEnvironment(macCatalyst)
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
        #endif
    }
#endif

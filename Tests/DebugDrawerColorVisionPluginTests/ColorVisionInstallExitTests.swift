// Installing registers the plugin with the drawer of the process that runs it and sets the shared
// model, so these run in a child process each, in a file of their own, as exit tests need one. The
// README's example is here, verbatim, rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerColorVisionPlugin
    import Foundation
    import SwiftUI
    import Testing

    struct Order: Identifiable {
        let id: Int
        let isLate: Bool

        static let samples = [Order(id: 1, isLate: true), Order(id: 2, isLate: false)]
    }

    // The README's example, verbatim.
    struct ShopApp: App {
        init() {
            // At startup:
            ColorVision.install()
        }

        var body: some Scene {
            WindowGroup {
                OrdersView(orders: Order.samples)
            }
        }
    }

    // A screen's content, inside its ScrollView:
    struct OrdersView: View {
        let orders: [Order]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("Orders")
                        .font(.title)
                    ForEach(orders) { order in
                        DeliveryBadge(isLate: order.isLate)
                    }
                }
                .debugColorVision()
            }
        }
    }

    // In a List, each row's content:
    struct OrderHistory: View {
        let orders: [Order]

        var body: some View {
            List(orders) { order in
                DeliveryBadge(isLate: order.isLate)
                    .debugColorVision()
            }
        }
    }

    // A view whose colors carry meaning:
    struct DeliveryBadge: View {
        let isLate: Bool

        var body: some View {
            Label(isLate ? "Late" : "On time", systemImage: "clock")
                .foregroundStyle(isLate ? .red : .green)
        }
    }

    @Suite("Color Vision install, in a child process")
    struct ColorVisionInstallExitTests {
        @Test("Install registers the plugin, with a HUD readout, in the Interface category, and starts with no simulation")
        func install() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    ColorVision.install()
                    let plugin = DebugDrawer.shared.globalPlugins.first { $0.title == "Color Vision" }
                    return plugin?.hasHUD == true && plugin?.category == "Interface" && ColorVisionModel.shared.simulation == nil
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once and sets the simulation it names")
        func installAgain() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    ColorVision.install(simulating: .protanopia)
                    let first = ColorVisionModel.shared.simulation
                    ColorVision.install(simulating: .grayscale)
                    let plugins = DebugDrawer.shared.globalPlugins.count { $0.title == "Color Vision" }
                    return plugins == 1 && first == .protanopia && ColorVisionModel.shared.simulation == .grayscale
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Color Vision")
        func readme() async {
            await #expect(processExitsWith: .success) {
                let isInstalled = await MainActor.run {
                    _ = ShopApp()
                    return DebugDrawer.shared.globalPlugins.count { $0.title == "Color Vision" } == 1
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif

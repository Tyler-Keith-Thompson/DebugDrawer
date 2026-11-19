#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerEnergyPlugin
    import Foundation
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct EnergyPluginViewTests {
        @Test("The plugin's view draws a snapshot it was handed, as a viewer in another process gets it")
        func drawsAReceivedSnapshot() throws {
            let snapshot = EnergySnapshot(
                isMonitoring: true,
                cpuUsage: 61.4,
                cpuHistory: [12, 61.4],
                processorCount: 4,
                batteryLevel: 15,
                batteryHistory: [BatterySample(timestamp: .distantPast, level: 15, isCharging: false)],
                isCharging: false,
                powerSource: "Battery",
                thermalState: .serious,
                isLowPowerModeEnabled: true
            )
            let (stream, _) = AsyncStream<EnergySnapshot>.makeStream()
            let sut = EnergyPluginView(transport: DebugDrawerPluginTransport(initial: snapshot, snapshots: stream) { _ in })

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual.contains("Very High"), "\(actual)")
            #expect(actual.contains("61.4%"), "\(actual)")
            #expect(actual.contains("15%"), "\(actual)")
            #expect(actual.contains("Thermal State — Serious"), "\(actual)")
            #expect(actual.contains("Battery"), "\(actual)")
        }
    }
#endif

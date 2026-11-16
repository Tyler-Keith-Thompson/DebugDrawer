#if DEBUG
    @testable import DebugDrawerEnergyPlugin
    import Darwin
    import ViewInspector
    import XCTest

    @MainActor
    final class EnergySamplingTests: XCTestCase {
        private func sendRefs(_ port: mach_port_t) throws -> mach_port_urefs_t {
            var refs: mach_port_urefs_t = 0
            let result = mach_port_get_refs(mach_task_self_, port, MACH_PORT_RIGHT_SEND, &refs)
            XCTAssertEqual(result, KERN_SUCCESS)
            return refs
        }

        func testSamplingCPUDoesNotLeakThreadPorts() throws {
            // mach_thread_self() itself adds a reference, released at the end.
            let port = mach_thread_self()
            defer { mach_port_deallocate(mach_task_self_, port) }

            let before = try sendRefs(port)
            for _ in 0 ..< 50 {
                _ = EnergyMonitor.processCPUUsage()
            }
            XCTAssertEqual(try sendRefs(port), before, "each sample leaked a send right on every thread port")
        }

        // MARK: Battery monitoring

        /// Stands in for `UIDevice.current.isBatteryMonitoringEnabled`, counting writes.
        private final class FakeBatteryMonitoring: BatteryMonitoringSwitch {
            var isEnabled: Bool { didSet { writes += 1 } }
            var writes = 0
            init(_ isEnabled: Bool) { self.isEnabled = isEnabled }
        }

        func testBatteryMonitoringReturnsToTheHostsValueWhenSamplingStops() {
            for hostValue in [false, true] {
                let device = FakeBatteryMonitoring(hostValue)
                let monitor = EnergyMonitor(batteryMonitoring: device)

                monitor.start()
                XCTAssertTrue(device.isEnabled, "battery monitoring is on while sampling")
                monitor.stop()
                XCTAssertEqual(device.isEnabled, hostValue, "host's value \(hostValue) wasn't restored")

                // Stopping again doesn't touch it.
                device.isEnabled = !hostValue
                monitor.stop()
                XCTAssertEqual(device.isEnabled, !hostValue)
            }
        }

        func testBatteryMonitoringIsSetOnceWhenSamplingStartsNotOnEverySample() {
            let device = FakeBatteryMonitoring(false)
            let monitor = EnergyMonitor(batteryMonitoring: device)
            monitor.start()
            monitor.start()
            XCTAssertEqual(device.writes, 1)
            monitor.stop()
            XCTAssertEqual(device.writes, 2)
        }

        // MARK: Label

        func testCPUThresholdIsLabelledCPULoadNotEnergyImpact() throws {
            let monitor = EnergyMonitor(batteryMonitoring: nil)
            monitor.start()
            defer { monitor.stop() }
            let texts = try EnergyPluginView(monitor: monitor).inspect()
                .findAll(ViewType.Text.self).map { try $0.string() }
            XCTAssertTrue(texts.contains("CPU Load"), "\(texts)")
            XCTAssertFalse(texts.contains("Energy Impact"), "\(texts)")
            XCTAssertTrue(texts.contains(monitor.cpuLoad), "\(texts)")
        }
    }
#endif

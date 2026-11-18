#if DEBUG
    import Darwin
    @testable import DebugDrawerEnergyPlugin
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct EnergySamplingTests {
        private func sendRefs(_ port: mach_port_t) -> mach_port_urefs_t {
            var refs: mach_port_urefs_t = 0
            let result = mach_port_get_refs(mach_task_self_, port, MACH_PORT_RIGHT_SEND, &refs)
            #expect(result == KERN_SUCCESS)
            return refs
        }

        @Test("Sampling the CPU leaves no send right behind on the thread ports")
        func samplingCPUDoesNotLeakThreadPorts() {
            // mach_thread_self() itself adds a reference, released at the end.
            let port = mach_thread_self()
            defer { mach_port_deallocate(mach_task_self_, port) }

            let before = sendRefs(port)
            for _ in 0 ..< 50 {
                _ = EnergyMonitor.processCPUUsage()
            }
            #expect(sendRefs(port) == before, "each sample leaked a send right on every thread port")
        }

        // MARK: Battery monitoring

        /// Stands in for `UIDevice.current.isBatteryMonitoringEnabled`, counting writes.
        private final class FakeBatteryMonitoring: BatteryMonitoringSwitch {
            var isEnabled: Bool { didSet { writes += 1 } }
            var writes = 0
            init(_ isEnabled: Bool) { self.isEnabled = isEnabled }
        }

        @Test("Battery monitoring is on while sampling and returns to the host's value when sampling stops", arguments: [false, true])
        func batteryMonitoringReturnsToTheHostsValueWhenSamplingStops(hostValue: Bool) {
            let device = FakeBatteryMonitoring(hostValue)
            let monitor = EnergyMonitor(batteryMonitoring: device)

            monitor.start()
            #expect(device.isEnabled, "battery monitoring is on while sampling")
            monitor.stop()
            #expect(device.isEnabled == hostValue, "host's value \(hostValue) wasn't restored")

            // Stopping again doesn't touch it.
            device.isEnabled = !hostValue
            monitor.stop()
            #expect(device.isEnabled == !hostValue)
        }

        @Test("Battery monitoring is set once when sampling starts and once when it stops, not on every sample")
        func batteryMonitoringIsSetOnceWhenSamplingStartsNotOnEverySample() {
            let device = FakeBatteryMonitoring(false)
            let monitor = EnergyMonitor(batteryMonitoring: device)
            monitor.start()
            monitor.start()
            #expect(device.writes == 1)
            monitor.stop()
            #expect(device.writes == 2)
        }

        // MARK: Label

        @Test("The CPU threshold is labelled CPU Load, not Energy Impact, beside the current load")
        func cpuThresholdIsLabelledCPULoadNotEnergyImpact() throws {
            let monitor = EnergyMonitor(batteryMonitoring: nil)
            monitor.start()
            defer { monitor.stop() }
            let texts = try EnergyPluginView(monitor: monitor).inspect()
                .findAll(ViewType.Text.self).map { try $0.string() }
            #expect(texts.contains("CPU Load"), "\(texts)")
            #expect(!texts.contains("Energy Impact"), "\(texts)")
            #expect(texts.contains(monitor.cpuLoad), "\(texts)")
        }
    }
#endif

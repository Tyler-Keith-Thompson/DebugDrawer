#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerEnergyPlugin
    import Foundation
    import Testing

    /// The 1 s timer: records starts and stops, and ticks when the test says.
    @MainActor
    private final class FakeTimer: SamplingTimer {
        private(set) var starts = 0
        private(set) var stops = 0
        private var tick: (@MainActor () -> Void)?

        var isRunning: Bool {
            tick != nil
        }

        func start(_ tick: @escaping @MainActor () -> Void) {
            starts += 1
            self.tick = tick
        }

        func stop() {
            stops += 1
            tick = nil
        }

        func deliverTick() {
            tick?()
        }
    }

    /// The battery the test sets: counts reads, and posts a change when the test says.
    @MainActor
    private final class FakeBattery: BatteryReader {
        var reading = BatteryReading(level: 80, isCharging: false, powerSource: "Battery")
        private(set) var reads = 0
        private var change: (@MainActor () -> Void)?

        var isObserved: Bool {
            change != nil
        }

        func read() -> BatteryReading {
            reads += 1
            return reading
        }

        func startObserving(_ change: @escaping @MainActor () -> Void) {
            self.change = change
        }

        func stopObserving() {
            change = nil
        }

        func post() {
            change?()
        }
    }

    /// The thermal state the test sets: counts reads, and posts a change when the test says.
    @MainActor
    private final class FakeThermal: ThermalStateReader {
        var state = ProcessInfo.ThermalState.nominal
        private(set) var reads = 0
        private var change: (@MainActor () -> Void)?

        var isObserved: Bool {
            change != nil
        }

        var thermalState: ProcessInfo.ThermalState {
            reads += 1
            return state
        }

        func startObserving(_ change: @escaping @MainActor () -> Void) {
            self.change = change
        }

        func stopObserving() {
            change = nil
        }

        func post() {
            change?()
        }
    }

    /// Low Power Mode as the test sets it: counts reads, and posts a change when the test says.
    @MainActor
    private final class FakeLowPowerMode: LowPowerModeReader {
        var isOn = false
        private(set) var reads = 0
        private var change: (@MainActor () -> Void)?

        var isObserved: Bool {
            change != nil
        }

        var isLowPowerModeEnabled: Bool {
            reads += 1
            return isOn
        }

        func startObserving(_ change: @escaping @MainActor () -> Void) {
            self.change = change
        }

        func stopObserving() {
            change = nil
        }

        func post() {
            change?()
        }
    }

    /// The process's CPU as the test sets it, on a fixed number of cores; counts reads.
    @MainActor
    private final class FakeCPU: ProcessCPUReader {
        var usage: Double = 3
        let processorCount: Int
        private(set) var reads = 0

        init(processorCount: Int = 8) {
            self.processorCount = processorCount
        }

        func cpuUsage() -> Double {
            reads += 1
            return usage
        }
    }

    /// A time of day the test moves by hand.
    private final class FakeClock: WallClock {
        var now: Date

        init(_ now: Date) {
            self.now = now
        }
    }

    // The monitor is read and driven here as an out-of-process reader would: through its snapshot
    // and commands, encoded and decoded, with no view. Every service is a fake; nothing reads the
    // battery, the thermal state, Low Power Mode, the kernel's threads or the clock.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct EnergyModelTests {
        @Test("A sampled snapshot encodes to JSON and decodes equal")
        func sampledSnapshotRoundTrips() throws {
            let battery = FakeBattery()
            battery.reading = BatteryReading(level: 64, isCharging: true, powerSource: "AC Power")
            let thermal = FakeThermal()
            thermal.state = .serious
            let lowPowerMode = FakeLowPowerMode()
            lowPowerMode.isOn = true
            let cpu = FakeCPU(processorCount: 6)
            cpu.usage = 42.5
            let timer = FakeTimer()
            let clock = FakeClock(Date(timeIntervalSince1970: 1_800_000_000))
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: timer, battery: battery, thermal: thermal,
                lowPowerMode: lowPowerMode, cpu: cpu, clock: clock
            )
            model.perform(EnergyCommand(.start))
            clock.now = Date(timeIntervalSince1970: 1_800_000_001)
            cpu.usage = 7
            timer.deliverTick()
            let expected = EnergySnapshot(
                isMonitoring: true,
                cpuUsage: 7,
                cpuHistory: [42.5, 7],
                processorCount: 6,
                batteryLevel: 64,
                batteryHistory: [
                    BatterySample(timestamp: Date(timeIntervalSince1970: 1_800_000_000), level: 64, isCharging: true),
                    BatterySample(timestamp: Date(timeIntervalSince1970: 1_800_000_001), level: 64, isCharging: true)
                ],
                isCharging: true,
                powerSource: "AC Power",
                thermalState: .serious,
                isLowPowerModeEnabled: true
            )

            let encoded = try JSONEncoder().encode(model.snapshot)
            let actual = try JSONDecoder().decode(EnergySnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.cpuLoad == .moderate)
        }

        @Test("An unsampled snapshot holds no readings and encodes to JSON and decodes equal")
        func unsampledSnapshotRoundTrips() throws {
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: FakeTimer(), battery: FakeBattery(), thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: FakeCPU(processorCount: 4), clock: FakeClock(.distantPast)
            )
            let expected = EnergySnapshot(processorCount: 4)

            let encoded = try JSONEncoder().encode(model.snapshot)
            let actual = try JSONDecoder().decode(EnergySnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.batteryLevel == -1)
            #expect(actual.powerSource == "Unknown")
            #expect(!actual.isMonitoring)
        }

        @Test("Each command encodes to JSON and decodes to the same action",
              arguments: [EnergyCommand.Action.start, .stop, .reset])
        func commandRoundTrips(action: EnergyCommand.Action) throws {
            let command = EnergyCommand(action)

            let encoded = try JSONEncoder().encode(command)
            let actual = try JSONDecoder().decode(EnergyCommand.self, from: encoded)

            #expect(actual.action == action)
        }

        @Test("Each system thermal state reaches the snapshot as the plugin's own state, with its label and severity",
              arguments: [
                  (ProcessInfo.ThermalState.nominal, EnergyThermalState.nominal, "Nominal"),
                  (.fair, .fair, "Fair"),
                  (.serious, .serious, "Serious"),
                  (.critical, .critical, "Critical")
              ])
        func thermalStates(system: ProcessInfo.ThermalState, expected: EnergyThermalState, expectedLabel: String) throws {
            let thermal = FakeThermal()
            thermal.state = system
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: FakeTimer(), battery: FakeBattery(), thermal: thermal,
                lowPowerMode: FakeLowPowerMode(), cpu: FakeCPU(), clock: FakeClock(.distantPast)
            )
            model.perform(EnergyCommand(.start))

            let decoded = try JSONDecoder().decode(EnergySnapshot.self, from: JSONEncoder().encode(model.snapshot))
            let actual = EnergyReading(decoded)

            #expect(decoded.thermalState == expected)
            #expect(actual.thermalLabel == expectedLabel)
            #expect(model.thermalLabel == expectedLabel)
        }

        @Test("The thermal severity is ok while nominal, a warning while fair or serious, an error while critical, and neutral when unknown",
              arguments: [
                  (EnergyThermalState.nominal, DebugDrawerIssueGlyph.Severity.ok),
                  (.fair, .warning),
                  (.serious, .warning),
                  (.critical, .error),
                  (.unknown, .neutral)
              ])
        func thermalSeverity(state: EnergyThermalState, expected: DebugDrawerIssueGlyph.Severity) {
            let reading = EnergyReading(EnergySnapshot(thermalState: state))

            let actual = reading.thermalSeverity

            #expect(actual == expected)
        }

        @Test("An unknown thermal state reads as Unknown")
        func unknownThermalState() {
            let reading = EnergyReading(EnergySnapshot(thermalState: .unknown))

            let actual = reading.thermalLabel

            #expect(actual == "Unknown")
        }

        @Test("The CPU load is low under 5%, moderate under 20%, high under 50% and very high from there",
              arguments: [
                  (0.0, CPULoad.low, "Low"),
                  (4.99, .low, "Low"),
                  (5.0, .moderate, "Moderate"),
                  (19.99, .moderate, "Moderate"),
                  (20.0, .high, "High"),
                  (49.99, .high, "High"),
                  (50.0, .veryHigh, "Very High"),
                  (250.0, .veryHigh, "Very High")
              ])
        func cpuLoadLevels(usage: Double, expected: CPULoad, expectedLabel: String) throws {
            let cpu = FakeCPU()
            cpu.usage = usage
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: FakeTimer(), battery: FakeBattery(), thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: cpu, clock: FakeClock(.distantPast)
            )
            model.perform(EnergyCommand(.start))

            let actual = try JSONDecoder().decode(EnergySnapshot.self, from: JSONEncoder().encode(model.snapshot))

            #expect(actual.cpuLoad == expected)
            #expect(EnergyReading(actual).cpuLoad == expectedLabel)
            #expect(model.cpuLoad == expectedLabel)
        }

        @Test("The CPU severity is none while low or moderate, a warning while high and an error while very high",
              arguments: [
                  (CPULoad.low, DebugDrawerIssueGlyph.Severity?.none),
                  (.moderate, nil),
                  (.high, .warning),
                  (.veryHigh, .error)
              ])
        func cpuLoadSeverity(load: CPULoad, expected: DebugDrawerIssueGlyph.Severity?) {
            let usage: Double = switch load {
            case .low: 1
            case .moderate: 10
            case .high: 30
            case .veryHigh: 90
            }
            let reading = EnergyReading(EnergySnapshot(cpuUsage: usage))

            let actual = reading.cpuLoadSeverity

            #expect(actual == expected)
        }

        @Test("A battery change the system posts while sampling reaches the snapshot at once, without a history sample")
        func batteryChangeArrives() {
            let battery = FakeBattery()
            battery.reading = BatteryReading(level: 50, isCharging: false, powerSource: "Battery")
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: FakeTimer(), battery: battery, thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: FakeCPU(), clock: FakeClock(.distantPast)
            )
            let sut = DebugDrawerPluginTransport.direct(to: model)
            sut.send(EnergyCommand(.start))
            var changes = 0
            let subscription = sut.objectWillChange.sink { changes += 1 }
            defer { subscription.cancel() }

            battery.reading = BatteryReading(level: 49, isCharging: true, powerSource: "AC Power")
            battery.post()

            #expect(sut.snapshot.batteryLevel == 49)
            #expect(sut.snapshot.isCharging)
            #expect(sut.snapshot.powerSource == "AC Power")
            #expect(sut.snapshot.batteryHistory.map(\.level) == [50])
            #expect(changes > 0)
        }

        @Test("Low Power Mode turning on and off while sampling reaches the snapshot at once")
        func lowPowerModeChangeArrives() {
            let lowPowerMode = FakeLowPowerMode()
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: FakeTimer(), battery: FakeBattery(), thermal: FakeThermal(),
                lowPowerMode: lowPowerMode, cpu: FakeCPU(), clock: FakeClock(.distantPast)
            )
            model.perform(EnergyCommand(.start))
            let offAtStart = model.snapshot.isLowPowerModeEnabled

            lowPowerMode.isOn = true
            lowPowerMode.post()
            let onAfterPost = model.snapshot.isLowPowerModeEnabled
            lowPowerMode.isOn = false
            lowPowerMode.post()

            #expect(!offAtStart)
            #expect(onAfterPost)
            #expect(!model.snapshot.isLowPowerModeEnabled)
        }

        @Test("A thermal state change the system posts while sampling reaches the snapshot at once")
        func thermalChangeArrives() {
            let thermal = FakeThermal()
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: FakeTimer(), battery: FakeBattery(), thermal: thermal,
                lowPowerMode: FakeLowPowerMode(), cpu: FakeCPU(), clock: FakeClock(.distantPast)
            )
            model.perform(EnergyCommand(.start))

            thermal.state = .critical
            thermal.post()

            #expect(model.snapshot.thermalState == .critical)
        }

        @Test("Start samples at once and on each tick, observing the system's changes; stop ends both")
        func startAndStop() {
            let timer = FakeTimer()
            let battery = FakeBattery()
            let thermal = FakeThermal()
            let lowPowerMode = FakeLowPowerMode()
            let cpu = FakeCPU()
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: timer, battery: battery, thermal: thermal,
                lowPowerMode: lowPowerMode, cpu: cpu, clock: FakeClock(.distantPast)
            )

            model.perform(EnergyCommand(.start))
            timer.deliverTick()
            let whileSampling = model.snapshot
            let observedWhileSampling = battery.isObserved && thermal.isObserved && lowPowerMode.isObserved
            model.perform(EnergyCommand(.stop))

            #expect(whileSampling.isMonitoring)
            #expect(whileSampling.cpuHistory.count == 2)
            #expect(whileSampling.batteryHistory.count == 2)
            #expect(observedWhileSampling)
            #expect(timer.starts == 1)
            #expect(timer.stops == 1)
            #expect(!timer.isRunning)
            #expect(!battery.isObserved)
            #expect(!thermal.isObserved)
            #expect(!lowPowerMode.isObserved)
            #expect(!model.snapshot.isMonitoring)
            #expect(model.snapshot.cpuHistory.count == 2)
        }

        @Test("Reset empties the CPU and battery history and keeps the latest readings and the sampling")
        func reset() {
            let timer = FakeTimer()
            let cpu = FakeCPU()
            cpu.usage = 12
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: timer, battery: FakeBattery(), thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: cpu, clock: FakeClock(.distantPast)
            )
            model.perform(EnergyCommand(.start))
            timer.deliverTick()

            model.perform(EnergyCommand(.reset))
            let afterReset = model.snapshot
            timer.deliverTick()

            #expect(afterReset.cpuHistory.isEmpty)
            #expect(afterReset.batteryHistory.isEmpty)
            #expect(afterReset.cpuUsage == 12)
            #expect(afterReset.batteryLevel == 80)
            #expect(afterReset.isMonitoring)
            #expect(model.snapshot.cpuHistory == [12])
            #expect(model.snapshot.batteryHistory.map(\.level) == [80])
        }

        @Test("Nothing is read before start or after stop, ticks and posted changes included")
        func nothingSampledOutsideStartAndStop() {
            let timer = FakeTimer()
            let battery = FakeBattery()
            let thermal = FakeThermal()
            let lowPowerMode = FakeLowPowerMode()
            let cpu = FakeCPU()
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: timer, battery: battery, thermal: thermal,
                lowPowerMode: lowPowerMode, cpu: cpu, clock: FakeClock(.distantPast)
            )
            battery.post()
            thermal.post()
            lowPowerMode.post()
            timer.deliverTick()
            let readsBeforeStart = [battery.reads, thermal.reads, lowPowerMode.reads, cpu.reads]
            model.perform(EnergyCommand(.start))
            model.perform(EnergyCommand(.stop))
            let readsAtStop = [battery.reads, thermal.reads, lowPowerMode.reads, cpu.reads]
            let snapshotAtStop = model.snapshot

            timer.deliverTick()
            battery.post()
            thermal.post()
            lowPowerMode.post()

            #expect(readsBeforeStart == [0, 0, 0, 0])
            #expect(timer.starts == 1)
            #expect(readsAtStop == [1, 1, 1, 1])
            #expect([battery.reads, thermal.reads, lowPowerMode.reads, cpu.reads] == readsAtStop)
            #expect(model.snapshot == snapshotAtStop)
        }

        @Test("Commands sent through a transport run in the order sent, each landing before send returns")
        func commandOrder() {
            let timer = FakeTimer()
            let cpu = FakeCPU()
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: timer, battery: FakeBattery(), thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: cpu, clock: FakeClock(.distantPast)
            )
            let sut = DebugDrawerPluginTransport.direct(to: model)

            cpu.usage = 1
            sut.send(EnergyCommand(.start))
            let afterStart = sut.snapshot.cpuHistory
            cpu.usage = 2
            timer.deliverTick()
            sut.send(EnergyCommand(.reset))
            let afterReset = sut.snapshot.cpuHistory
            sut.send(EnergyCommand(.stop))
            let monitoringAfterStop = sut.snapshot.isMonitoring
            sut.send(EnergyCommand(.start))
            cpu.usage = 3
            timer.deliverTick()

            #expect(afterStart == [1])
            #expect(afterReset.isEmpty)
            #expect(!monitoringAfterStop)
            #expect(sut.snapshot.cpuHistory == [2, 3])
            #expect(timer.starts == 2)
            #expect(timer.stops == 1)
        }

        @Test("Battery samples carry the clock's time, and the history keeps the newest 120 of each")
        func historyIsStampedAndBounded() {
            let timer = FakeTimer()
            let clock = FakeClock(Date(timeIntervalSince1970: 0))
            let cpu = FakeCPU()
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: timer, battery: FakeBattery(), thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: cpu, clock: clock
            )
            model.perform(EnergyCommand(.start))
            for second in 1 ... 130 {
                clock.now = Date(timeIntervalSince1970: TimeInterval(second))
                cpu.usage = Double(second)
                timer.deliverTick()
            }

            let actual = model.snapshot

            #expect(actual.cpuHistory.count == 120)
            #expect(actual.cpuHistory.first == 11)
            #expect(actual.cpuHistory.last == 130)
            #expect(actual.batteryHistory.count == 120)
            #expect(actual.batteryHistory.first?.timestamp == Date(timeIntervalSince1970: 11))
            #expect(actual.batteryHistory.last?.timestamp == Date(timeIntervalSince1970: 130))
        }

        @Test("Without a battery nothing joins the battery history, and the snapshot says so")
        func noBattery() {
            let battery = FakeBattery()
            battery.reading = BatteryReading(level: -1, isCharging: false, powerSource: "AC Power")
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: FakeTimer(), battery: battery, thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: FakeCPU(), clock: FakeClock(.distantPast)
            )

            model.perform(EnergyCommand(.start))

            #expect(model.snapshot.batteryLevel == -1)
            #expect(model.snapshot.batteryHistory.isEmpty)
            #expect(model.snapshot.powerSource == "AC Power")
        }

        @Test("Installs are counted per drawer: the last one's uninstall stops sampling and drops the readings; a stranger's does nothing")
        func installCounting() {
            final class Drawer {}
            let first = Drawer()
            let second = Drawer()
            let stranger = Drawer()
            let timer = FakeTimer()
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: timer, battery: FakeBattery(), thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: FakeCPU(), clock: FakeClock(.distantPast)
            )
            model.install(in: ObjectIdentifier(first))
            model.install(in: ObjectIdentifier(second))
            model.addViewer()

            model.uninstall(from: ObjectIdentifier(stranger))
            let afterStranger = model.snapshot
            model.uninstall(from: ObjectIdentifier(first))
            let afterFirst = model.snapshot
            model.uninstall(from: ObjectIdentifier(second))

            #expect(afterStranger.isMonitoring)
            #expect(afterFirst.isMonitoring)
            #expect(afterFirst.cpuHistory.count == 1)
            #expect(!model.snapshot.isMonitoring)
            #expect(model.snapshot == EnergySnapshot(processorCount: 8))
            #expect(timer.stops == 1)
        }

        @Test("The plugin over a monitor of fakes, installed in two real drawers, samples while either shows it and drops its readings with the last")
        func pluginInTwoDrawers() throws {
            let firstSuite = "EnergyModelTests.\(UUID().uuidString)"
            let secondSuite = "EnergyModelTests.\(UUID().uuidString)"
            let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
            let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
            defer {
                firstDefaults.removePersistentDomain(forName: firstSuite)
                secondDefaults.removePersistentDomain(forName: secondSuite)
            }
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let timer = FakeTimer()
            let model = EnergyMonitor(
                batteryMonitoring: nil, timer: timer, battery: FakeBattery(), thermal: FakeThermal(),
                lowPowerMode: FakeLowPowerMode(), cpu: FakeCPU(), clock: FakeClock(.distantPast)
            )
            let sut = EnergyPlugin(monitor: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            second.pluginContentDidAppear(id: sut.id)
            let monitoringWhileShown = model.snapshot.isMonitoring
            first.unregisterGlobal(id: sut.id)
            let afterFirstRemoved = model.snapshot
            second.unregisterGlobal(id: sut.id)

            #expect(monitoringWhileShown)
            #expect(afterFirstRemoved.isMonitoring)
            #expect(afterFirstRemoved.cpuHistory.count == 1)
            #expect(!model.snapshot.isMonitoring)
            #expect(model.snapshot.cpuHistory.isEmpty)
            #expect(timer.stops == 1)
        }
    }
#endif

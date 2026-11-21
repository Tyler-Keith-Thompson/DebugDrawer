#if DEBUG
    import Combine
    @testable import DebugDrawer
    import DebugDrawerAppInfo
    @testable import DebugDrawerAppInfoPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    /// Stands in for the 2 s refresh timer: records starts and stops, and ticks when the test says.
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

    /// Stands in for the network path monitor: records starts and stops, and reports a status
    /// when the test says.
    @MainActor
    private final class FakeWatcher: NetworkPathWatcher {
        private(set) var starts = 0
        private(set) var stops = 0
        private var update: (@Sendable (NetworkReachability) -> Void)?

        var isWatching: Bool {
            update != nil
        }

        func start(_ update: @escaping @Sendable (NetworkReachability) -> Void) {
            starts += 1
            self.update = update
        }

        func stop() {
            stops += 1
            update = nil
        }

        func report(_ status: NetworkReachability) {
            update?(status)
        }
    }

    @MainActor
    @Suite("App Info's model, driven through commands over fake sources", .timeLimit(.minutes(1)))
    struct AppInfoModelTests {
        private static let launch = Date(timeIntervalSince1970: 1_700_000_000)

        private static let bundleInfo = BundleInfo(
            identifier: "com.example.App",
            version: "1.2.3",
            build: "45",
            buildMetadata: AppInfoBuildMetadata(gitCommit: "plist-sha", gitBranch: "main", ciBuildNumber: nil)
        )

        private static let deviceInfo = DeviceInfo(
            operatingSystemName: "iOS",
            operatingSystemVersion: "Version 18.4 (Build 22E240)",
            isSandboxed: nil,
            activeProcessorCount: 8,
            physicalMemory: 8 * 1024 * 1024 * 1024,
            screen: DeviceInfo.Screen(width: 1032, height: 1376, scale: 2),
            architecture: "arm64"
        )

        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = temporarySuiteName("AppInfoModelTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("A snapshot with every fact read comes back equal from JSON, and so does an empty one")
        func snapshotRoundTrips() throws {
            let expected = AppInfoSnapshot(
                isSampling: true,
                bundle: Self.bundleInfo,
                buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: nil, ciBuildNumber: "812"),
                device: Self.deviceInfo,
                processIdentifier: 4321,
                argumentCount: 3,
                processStart: ProcessStart(date: Self.launch, isTraced: true),
                footprintMB: 182.4,
                uptime: 134.5,
                network: .wifi,
                signing: AppSigning(profile: .embedded(AppInfoFixtures.profile), entitlements: AppInfoFixtures.profile.entitlements),
                isProfileExpired: true
            )
            let empty = AppInfoSnapshot()

            let actual = try JSONDecoder().decode(AppInfoSnapshot.self, from: JSONEncoder().encode(expected))
            let actualEmpty = try JSONDecoder().decode(AppInfoSnapshot.self, from: JSONEncoder().encode(empty))

            #expect(actual == expected)
            #expect(actualEmpty == empty)
        }

        @Test("An unreadable profile, a list of devices for all, and every reachability come back equal from JSON")
        func valuesRoundTrip() throws {
            let signings: [AppSigning] = [
                AppSigning(profile: .unreadable, entitlements: Entitlements(source: .codeSignature, entries: [
                    Entitlement(key: "com.apple.security.app-sandbox", value: .boolean(true))
                ])),
                AppSigning(profile: .none, entitlements: nil)
            ]
            let reachabilities: [NetworkReachability] = [.unknown, .offline, .wifi, .cellular, .wiredEthernet, .online]
            var profile = AppInfoFixtures.profile
            profile.devices = .all

            let actualSignings = try JSONDecoder().decode([AppSigning].self, from: JSONEncoder().encode(signings))
            let actualReachabilities = try JSONDecoder().decode([NetworkReachability].self, from: JSONEncoder().encode(reachabilities))
            let actualProfile = try JSONDecoder().decode(ProvisioningProfile.self, from: JSONEncoder().encode(profile))

            #expect(actualSignings == signings)
            #expect(actualReachabilities == reachabilities)
            #expect(actualProfile == profile)
        }

        @Test("Every command comes back from JSON as the same action")
        func commandsRoundTrip() throws {
            let expected: [AppInfoCommand.Action] = [.start, .stop, .refresh]

            let actual = try expected.map {
                try JSONDecoder().decode(AppInfoCommand.self, from: JSONEncoder().encode(AppInfoCommand($0))).action
            }

            #expect(actual == expected)
        }

        @Test("A new model reads nothing, starts no timer and watches no network; its snapshot is empty")
        func nothingBeforeStart() {
            let bundle = FakeBundleInfoSource(Self.bundleInfo)
            let device = FakeDeviceInfoSource(Self.deviceInfo)
            let process = FakeProcessMetricsSource(start: ProcessStart(date: Self.launch, isTraced: false), footprintMB: 100)
            let signing = FakeSigningInformation()
            let timer = FakeTimer()
            let watcher = FakeWatcher()

            let sut = AppInfoModel(bundle: bundle, device: device, process: process, signing: signing, timer: timer, pathWatcher: watcher)

            #expect(sut.snapshot == AppInfoSnapshot())
            #expect(bundle.reads == 0)
            #expect(device.reads == 0)
            #expect(process.startReads == 0)
            #expect(process.footprintReads == 0)
            #expect(signing.reads == 0)
            #expect(timer.starts == 0)
            #expect(watcher.starts == 0)
        }

        @Test("Start reads the bundle, device, process and signing into the snapshot, and the facts word them")
        func infoFields() throws {
            let clock = FakeWallClock(Self.launch.addingTimeInterval(134))
            let sut = try AppInfoModel(
                bundle: FakeBundleInfoSource(Self.bundleInfo),
                device: FakeDeviceInfoSource(Self.deviceInfo),
                process: FakeProcessMetricsSource(
                    start: ProcessStart(date: Self.launch, isTraced: true), footprintMB: 182.4, processIdentifier: 4321, argumentCount: 3
                ),
                signing: FakeSigningInformation(profile: AppInfoFixtures.profileData()),
                clock: clock,
                timer: FakeTimer(),
                pathWatcher: FakeWatcher()
            )
            let transport = DebugDrawerPluginTransport.direct(to: sut)
            let expected = AppInfoSnapshot(
                isSampling: true,
                bundle: Self.bundleInfo,
                device: Self.deviceInfo,
                processIdentifier: 4321,
                argumentCount: 3,
                processStart: ProcessStart(date: Self.launch, isTraced: true),
                footprintMB: 182.4,
                uptime: 134,
                signing: AppSigning(profile: .embedded(AppInfoFixtures.profile), entitlements: AppInfoFixtures.profile.entitlements),
                isProfileExpired: false
            )
            let expectedFacts: [String: String] = [
                "Bundle ID": "com.example.App",
                "Version": "1.2.3",
                "Build": "45",
                "Commit": "plist-sha",
                "Branch": "main",
                "CI Build": "—",
                "Footprint": "182.4 MB",
                "Uptime": "2m 14s",
                "PID": "4321",
                "Arch": "arm64",
                "Arguments": "3",
                "iOS": "Version 18.4 (Build 22E240)",
                "Debugger": "Attached",
                "Active CPU": "8",
                "Physical Mem": "8 GB",
                "Screen": "1032×1376 @2x",
                "Network": "Unknown",
                "Launched": AppInfoFacts.launchFormatter.string(from: Self.launch)
            ]

            transport.send(AppInfoCommand(.start))

            let actual = transport.snapshot
            let facts = AppInfoFacts(snapshot: actual)
            let actualFacts = Dictionary(uniqueKeysWithValues: facts.sections.flatMap(\.facts).map { ($0.label, $0.value) })
            #expect(actual == expected)
            #expect(actualFacts == expectedFacts)
            #expect(!facts.sections.flatMap(\.facts).contains { $0.label == "Sandbox" })
        }

        @Test("Each tick reads the footprint and uptime again, and changes the snapshot once")
        func metricsArrive() {
            let clock = FakeWallClock(Self.launch.addingTimeInterval(10))
            let process = FakeProcessMetricsSource(start: ProcessStart(date: Self.launch, isTraced: false), footprintMB: 100)
            let timer = FakeTimer()
            let sut = AppInfoModel(
                bundle: FakeBundleInfoSource(),
                device: FakeDeviceInfoSource(),
                process: process,
                signing: FakeSigningInformation(),
                clock: clock,
                timer: timer,
                pathWatcher: FakeWatcher()
            )
            sut.perform(AppInfoCommand(.start))
            let afterStart = sut.snapshot
            var changes = 0
            let subscription = sut.objectWillChange.sink { changes += 1 }

            process.footprint = 120
            clock.now = Self.launch.addingTimeInterval(12)
            timer.deliverTick()
            let actual = sut.snapshot
            subscription.cancel()

            #expect(afterStart.footprintMB == 100)
            #expect(afterStart.uptime == 10)
            #expect(actual.footprintMB == 120)
            #expect(actual.uptime == 12)
            #expect(changes == 1)
            #expect(process.footprintReads == 2)
            #expect(process.startReads == 1)
        }

        @Test("Refresh reads everything once without starting the timer; refreshing again reads again")
        func refresh() {
            let bundle = FakeBundleInfoSource(Self.bundleInfo)
            let process = FakeProcessMetricsSource(footprintMB: 50)
            let signing = FakeSigningInformation()
            let timer = FakeTimer()
            let sut = AppInfoModel(
                bundle: bundle, device: FakeDeviceInfoSource(), process: process, signing: signing, timer: timer, pathWatcher: FakeWatcher()
            )
            let transport = DebugDrawerPluginTransport.direct(to: sut)

            transport.send(AppInfoCommand(.refresh))
            let first = transport.snapshot
            process.footprint = 75
            transport.send(AppInfoCommand(.refresh))
            let actual = transport.snapshot

            #expect(first.footprintMB == 50)
            #expect(!first.isSampling)
            #expect(actual.footprintMB == 75)
            #expect(actual.bundle == Self.bundleInfo)
            #expect(bundle.reads == 2)
            #expect(process.footprintReads == 2)
            #expect(signing.reads == 1, "the signing is read once and kept")
            #expect(timer.starts == 0)
        }

        @Test("Start and stop count viewers with the drawers: the timer runs from the first to the last")
        func startAndStopCount() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let timer = FakeTimer()
            let model = AppInfoModel(
                bundle: FakeBundleInfoSource(), device: FakeDeviceInfoSource(), process: FakeProcessMetricsSource(),
                signing: FakeSigningInformation(), timer: timer, pathWatcher: FakeWatcher()
            )
            let plugin = AppInfoPlugin(buildMetadata: AppInfoBuildMetadata(), model: model)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            drawer.registerGlobal(plugin)

            transport.send(AppInfoCommand(.start))
            drawer.pluginContentDidAppear(id: plugin.id)
            transport.send(AppInfoCommand(.stop))
            let runningWhileTheDrawerShowsIt = timer.isRunning
            let samplingWhileTheDrawerShowsIt = transport.snapshot.isSampling
            drawer.pluginContentDidDisappear(id: plugin.id)
            transport.send(AppInfoCommand(.stop))

            #expect(runningWhileTheDrawerShowsIt)
            #expect(samplingWhileTheDrawerShowsIt)
            #expect(timer.starts == 1)
            #expect(timer.stops == 1)
            #expect(!timer.isRunning)
            #expect(!transport.snapshot.isSampling)
        }

        @Test("Nothing is read after stop: the timer is stopped and the snapshot keeps its last reading")
        func nothingAfterStop() {
            let process = FakeProcessMetricsSource(footprintMB: 100)
            let device = FakeDeviceInfoSource()
            let timer = FakeTimer()
            let sut = AppInfoModel(
                bundle: FakeBundleInfoSource(), device: device, process: process,
                signing: FakeSigningInformation(), timer: timer, pathWatcher: FakeWatcher()
            )
            sut.perform(AppInfoCommand(.start))
            sut.perform(AppInfoCommand(.stop))
            let afterStop = sut.snapshot

            process.footprint = 300
            timer.deliverTick()

            #expect(sut.snapshot == afterStop)
            #expect(sut.snapshot.footprintMB == 100)
            #expect(process.footprintReads == 1)
            #expect(device.reads == 1)
        }

        @Test("Commands land in the order sent, each before send returns")
        func commandOrder() {
            let process = FakeProcessMetricsSource(footprintMB: 10)
            let timer = FakeTimer()
            let sut = AppInfoModel(
                bundle: FakeBundleInfoSource(), device: FakeDeviceInfoSource(), process: process,
                signing: FakeSigningInformation(), timer: timer, pathWatcher: FakeWatcher()
            )
            let transport = DebugDrawerPluginTransport.direct(to: sut)
            var seen: [(Bool, Double)] = []

            transport.send(AppInfoCommand(.refresh))
            seen.append((transport.snapshot.isSampling, transport.snapshot.footprintMB))
            process.footprint = 20
            transport.send(AppInfoCommand(.start))
            seen.append((transport.snapshot.isSampling, transport.snapshot.footprintMB))
            process.footprint = 30
            transport.send(AppInfoCommand(.stop))
            seen.append((transport.snapshot.isSampling, transport.snapshot.footprintMB))
            transport.send(AppInfoCommand(.refresh))
            seen.append((transport.snapshot.isSampling, transport.snapshot.footprintMB))

            #expect(seen.map(\.0) == [false, true, false, false])
            #expect(seen.map(\.1) == [10, 20, 20, 30])
            #expect(timer.starts == 1)
            #expect(timer.stops == 1)
        }

        @Test("Two drawers holding the plugin watch the network once; a stranger's uninstall changes nothing; the last drops the status")
        func installCounting() async throws {
            let (first, cleanUpFirst) = try Self.drawer()
            let (second, cleanUpSecond) = try Self.drawer()
            let (stranger, cleanUpStranger) = try Self.drawer()
            defer {
                cleanUpFirst()
                cleanUpSecond()
                cleanUpStranger()
            }
            let watcher = FakeWatcher()
            let timer = FakeTimer()
            let model = AppInfoModel(
                bundle: FakeBundleInfoSource(), device: FakeDeviceInfoSource(), process: FakeProcessMetricsSource(),
                signing: FakeSigningInformation(), timer: timer, pathWatcher: watcher
            )
            let sut = AppInfoPlugin(buildMetadata: AppInfoBuildMetadata(), model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            first.pluginContentDidAppear(id: sut.id)

            watcher.report(.wifi)
            for await snapshot in model.$snapshot.values where snapshot.network == .wifi {
                break
            }
            sut.uninstall(from: stranger)
            let watchingAfterTheStranger = watcher.isWatching
            first.unregisterGlobal(id: sut.id)
            let watchingWhileTheSecondHoldsIt = watcher.isWatching
            let networkWhileTheSecondHoldsIt = model.snapshot.network
            second.unregisterGlobal(id: sut.id)

            #expect(watchingAfterTheStranger)
            #expect(watchingWhileTheSecondHoldsIt)
            #expect(networkWhileTheSecondHoldsIt == .wifi)
            #expect(watcher.starts == 1)
            #expect(watcher.stops == 1)
            #expect(model.snapshot.network == .unknown)
            #expect(!timer.isRunning)
            #expect(!model.snapshot.isSampling)
        }

        @Test("The build metadata the plugin was installed with wins over the bundle's, field by field")
        func installedBuildMetadata() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let model = AppInfoModel(
                bundle: FakeBundleInfoSource(Self.bundleInfo), device: FakeDeviceInfoSource(), process: FakeProcessMetricsSource(),
                signing: FakeSigningInformation(), timer: FakeTimer(), pathWatcher: FakeWatcher()
            )
            let metadata = AppInfoBuildMetadata(gitCommit: "4f9c2e1", ciBuildNumber: "812")
            let expected = AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "main", ciBuildNumber: "812")
            drawer.registerGlobal(AppInfoPlugin(buildMetadata: metadata, model: model))

            model.perform(AppInfoCommand(.refresh))

            #expect(model.snapshot.buildMetadata == metadata)
            #expect(model.snapshot.build == expected)
        }
    }
#endif

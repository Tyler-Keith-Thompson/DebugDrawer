// The environment overrides as a sidecar drives them and a host's SwiftUI view reads them: a real
// DebugDrawerReceiver serving the app-group store, the sidecar's DebugDrawerAppGroupStoreTransport
// (a debug-build type) on the same directory, and a probe view hosted under
// `accessibilityEnvironmentOverrides(_:)`. Contrast and Reduce Motion are get-only environment
// keys, which ViewInspector's offline `inspect()` doesn't resolve, so the probe is hosted for real
// and read through `Inspection`. The "system" values are set above the modifier, as the OS sets
// them above an app's root view. Each test makes overrides of its own, so tests running at once
// don't share them.
#if DEBUG
    import Combine
    import DebugDrawer
    import DebugDrawerAccessibility
    import DebugDrawerReceiver
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    final class Inspection<V>: InspectionEmissary {
        let notice = PassthroughSubject<UInt, Never>()
        var callbacks: [UInt: (V) -> Void] = [:]

        func visit(_ view: V, _ line: UInt) {
            if let callback = callbacks.removeValue(forKey: line) {
                callback(view)
            }
        }
    }

    /// A host view that reads the three settings the way an app does.
    struct Probe: View {
        let inspection = Inspection<Self>()

        @Environment(\.dynamicTypeSize) var dynamicTypeSize
        @Environment(\.colorSchemeContrast) var contrast
        @Environment(\.accessibilityReduceMotion) var reduceMotion

        var body: some View {
            Text("probe")
                .onReceive(inspection.notice) { self.inspection.visit(self, $0) }
        }
    }

    /// What the probe read.
    private struct Reading: Equatable {
        let dynamicTypeSize: DynamicTypeSize
        let contrast: ColorSchemeContrast
        let reduceMotion: Bool
    }

    // Serialized: ViewHosting hosts every view in one shared window, so two hosted at once would
    // replace each other.
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct AccessibilityEnvironmentReceiverTests {
        /// The values the "system" sets above the overrides.
        private let system = Reading(dynamicTypeSize: .large, contrast: .standard, reduceMotion: false)

        /// Hosts a probe under `overrides`, with the system's values above it, and returns what it
        /// reads.
        private func read(under overrides: AccessibilityEnvironmentOverrides) async throws -> Reading {
            let probe = Probe()
            let hosted = probe
                .accessibilityEnvironmentOverrides(overrides)
                .environment(\.dynamicTypeSize, system.dynamicTypeSize)
                .environment(\._colorSchemeContrast, system.contrast)
                .environment(\._accessibilityReduceMotion, system.reduceMotion)
            var reading: Reading?
            try await ViewHosting.host(hosted) {
                try await probe.inspection.inspect { view in
                    let probe = try view.actualView()
                    reading = Reading(dynamicTypeSize: probe.dynamicTypeSize, contrast: probe.contrast, reduceMotion: probe.reduceMotion)
                }
            }
            return try #require(reading)
        }

        // ViewHosting hosts the view in a window, which UIKit can't make in xctest, which runs
        // package tests on Mac Catalyst without an NSApplication.
        #if !targetEnvironment(macCatalyst)
            @Test("A view reads the system's values before a session, a sidecar's overrides while it is open, and the system's again after it ends")
            func overridesApplyForTheSession() async throws {
                let directory = FileManager.default.temporaryDirectory.appending(path: "AccessibilityEnvironmentReceiverTests-\(UUID().uuidString)")
                let overrides = AccessibilityEnvironmentOverrides()
                let sessions = DebugDrawerSessions(maximumDuration: 300)
                let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
                receiver.enable(.accessibilityEnvironmentOverrides(overrides))
                try receiver.start()
                defer { receiver.stop() }
                let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
                let sessionControl = try await sidecar.connect(
                    toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
                )
                var sessionStates = sessionControl.snapshots().makeAsyncIterator()
                let expectedOverridden = AccessibilityEnvironmentOverrides.Snapshot(
                    dynamicTypeSize: .accessibility3, increaseContrast: true, reduceMotion: true
                )
                let expectedDuring = Reading(dynamicTypeSize: .accessibility3, contrast: .increased, reduceMotion: true)

                let before = try await read(under: overrides)
                sessionControl.send(.open(duration: 60))
                // Served once the session is open.
                let environment = try await sidecar.connect(
                    toPlugin: AccessibilityEnvironmentOverrides.pluginID,
                    snapshot: AccessibilityEnvironmentOverrides.Snapshot.self,
                    command: AccessibilityEnvironmentOverrides.Command.self
                )
                var published = environment.snapshots().makeAsyncIterator()
                while let state = await sessionStates.next(), !state.isActive {}
                environment.send(.setDynamicTypeSize(.accessibility3))
                environment.send(.setIncreaseContrast(true))
                environment.send(.setReduceMotion(true))
                var overridden: AccessibilityEnvironmentOverrides.Snapshot?
                while let snapshot = await published.next() {
                    if snapshot == expectedOverridden {
                        overridden = snapshot
                        break
                    }
                }
                let during = try await read(under: overrides)
                sessionControl.send(.end)
                while let state = await sessionStates.next(), state.isActive {}
                let reverted = overrides.snapshot
                let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: AccessibilityEnvironmentOverrides.pluginID)
                let servedAfterSession = FileManager.default.fileExists(atPath: snapshotFile.path)
                let after = try await read(under: overrides)

                #expect(before == system)
                #expect(overridden == expectedOverridden)
                #expect(during == expectedDuring)
                #expect(reverted == AccessibilityEnvironmentOverrides.Snapshot())
                #expect(!servedAfterSession)
                #expect(after == system)
                #expect(sessions.auditLog.filter { $0.capability == AccessibilityEnvironmentOverrides.pluginID }.map(\.event) == [
                    .commandApplied, .commandApplied, .commandApplied, .changeReverted
                ])
            }

            @Test("Overriding one setting leaves the others at the system's values, and returning it to the system's clears it")
            func oneSettingAtATime() async throws {
                let overrides = AccessibilityEnvironmentOverrides()

                overrides.perform(.setReduceMotion(true))
                let reduced = try await read(under: overrides)
                overrides.perform(.setReduceMotion(nil))
                overrides.perform(.setIncreaseContrast(false))
                overrides.perform(.setDynamicTypeSize(.xSmall))
                let small = try await read(under: overrides)

                #expect(reduced == Reading(dynamicTypeSize: .large, contrast: .standard, reduceMotion: true))
                #expect(small == Reading(dynamicTypeSize: .xSmall, contrast: .standard, reduceMotion: false))
            }

            @Test("Every Dynamic Type size a sidecar can send reaches the view as SwiftUI's size of the same name",
                  arguments: zip(AccessibilityEnvironmentOverrides.DynamicTypeSize.allCases, DynamicTypeSize.allCases))
            func everySize(size: AccessibilityEnvironmentOverrides.DynamicTypeSize, expected: DynamicTypeSize) async throws {
                let overrides = AccessibilityEnvironmentOverrides()

                overrides.perform(.setDynamicTypeSize(size))
                let actual = try await read(under: overrides).dynamicTypeSize

                #expect(actual == expected)
            }
        #endif

        @Test("Outside a session a sidecar's override is refused, and nothing is overridden")
        func refusedOutsideSession() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "AccessibilityEnvironmentReceiverTests-\(UUID().uuidString)")
            let overrides = AccessibilityEnvironmentOverrides()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.accessibilityEnvironmentOverrides(overrides))
            try receiver.start()
            defer { receiver.stop() }
            // Outside a session the capability isn't served, so a sidecar can't connect to it: the
            // command is left in the store as its transport would leave it.
            let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
            let command = try StoreDocument(TransportMessage(
                kind: .command, pluginID: AccessibilityEnvironmentOverrides.pluginID,
                payload: TransportMessage.payload(AccessibilityEnvironmentOverrides.Command.setDynamicTypeSize(.accessibility5))
            )).encoded()
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            let expected = DebugDrawerAuditEntry.Event.commandRefused(.noActiveSession)

            try layout.write(command, to: layout.commands.appending(path: "0.json"))
            var refusal: DebugDrawerAuditEntry?
            for await entry in arrivals where entry.capability == AccessibilityEnvironmentOverrides.pluginID {
                refusal = entry
                break
            }

            #expect(refusal?.event == expected)
            #expect(overrides.snapshot == AccessibilityEnvironmentOverrides.Snapshot())
        }

        @Test("Reset returns every setting to the system's, and a command that changes nothing publishes nothing")
        func resetAndNoChange() {
            let overrides = AccessibilityEnvironmentOverrides()
            var published: [AccessibilityEnvironmentOverrides.Snapshot] = []
            let subscription = overrides.$snapshot.dropFirst().sink { published.append($0) }
            defer { subscription.cancel() }

            overrides.perform(.setReduceMotion(nil))
            overrides.perform(.reset)
            overrides.perform(.setIncreaseContrast(true))
            overrides.perform(.setIncreaseContrast(true))
            overrides.perform(.reset)

            #expect(published == [
                AccessibilityEnvironmentOverrides.Snapshot(increaseContrast: true),
                AccessibilityEnvironmentOverrides.Snapshot()
            ])
        }
    }
#endif

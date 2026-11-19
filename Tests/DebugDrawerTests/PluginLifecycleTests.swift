#if DEBUG
    #if os(macOS)
        import AppKit
    #endif
    @testable import DebugDrawer
    import Foundation
    import SwiftUI
    import Testing

    /// What a ``LifecycleRecordingPlugin`` heard, and from which drawer.
    @MainActor
    private final class LifecycleLog {
        struct Event: Equatable {
            let hook: String
            let drawer: ObjectIdentifier
        }

        var events: [Event] = []

        var hooks: [String] {
            events.map(\.hook)
        }
    }

    /// A plugin that records each lifecycle hook the drawer calls.
    private struct LifecycleRecordingPlugin: DebugDrawerPlugin {
        var id = "lifecycle.recording"
        let log: LifecycleLog
        var title = "Recording"
        var icon = "record.circle"
        var body: some View { Text("Recording") }
        var hud: Text? { Text("REC") }

        func install(in drawer: DebugDrawer) {
            log.events.append(.init(hook: "install", drawer: ObjectIdentifier(drawer)))
        }

        func uninstall(from drawer: DebugDrawer) {
            log.events.append(.init(hook: "uninstall", drawer: ObjectIdentifier(drawer)))
        }

        func didBecomeVisible(in drawer: DebugDrawer) {
            log.events.append(.init(hook: "visible", drawer: ObjectIdentifier(drawer)))
        }

        func didBecomeHidden(in drawer: DebugDrawer) {
            log.events.append(.init(hook: "hidden", drawer: ObjectIdentifier(drawer)))
        }
    }

    /// A plugin that adopts none of the hooks.
    private struct HooklessPlugin: DebugDrawerPlugin {
        var title = "Hookless"
        var icon = "circle"
        var body: some View { Text("Hookless") }
    }

    @MainActor
    @Suite("Plugin lifecycle")
    struct PluginLifecycleTests {
        @Test("A global plugin is installed, shown, hidden and uninstalled, in that order")
        func globalHooksInOrder() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let log = LifecycleLog()
            let expected = ["install", "visible", "hidden", "uninstall"]

            sut.registerGlobal(LifecycleRecordingPlugin(log: log))
            sut.pluginContentDidAppear(id: "lifecycle.recording")
            sut.pluginContentDidDisappear(id: "lifecycle.recording")
            sut.unregisterGlobal(id: "lifecycle.recording")

            #expect(log.hooks == expected)
            #expect(log.events.allSatisfy { $0.drawer == ObjectIdentifier(sut) })
        }

        @Test("A plugin shown in two places becomes visible once and hidden once the last one goes")
        func visibilityIsCountedAcrossViews() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let log = LifecycleLog()
            sut.registerGlobal(LifecycleRecordingPlugin(log: log))
            let expectedWhileOneRemains = ["install", "visible"]
            let expected = ["install", "visible", "hidden"]

            sut.pluginContentDidAppear(id: "lifecycle.recording")
            sut.pluginContentDidAppear(id: "lifecycle.recording")
            sut.pluginContentDidDisappear(id: "lifecycle.recording")
            let actualWhileOneRemains = log.hooks
            sut.pluginContentDidDisappear(id: "lifecycle.recording")

            #expect(actualWhileOneRemains == expectedWhileOneRemains)
            #expect(log.hooks == expected)
        }

        @Test("Unregistering a global plugin removes it and calls its uninstall hook")
        func unregisteringUninstalls() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let log = LifecycleLog()
            sut.registerGlobal(LifecycleRecordingPlugin(log: log))
            let expected = ["install", "uninstall"]

            sut.unregisterGlobal(id: "lifecycle.recording")

            #expect(sut.globalPlugins.isEmpty)
            #expect(!sut.hasPlugins)
            #expect(log.hooks == expected)
        }

        @Test("A plugin removed while on screen is hidden before it is uninstalled, and its views' leaving changes nothing")
        func removedWhileVisible() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let log = LifecycleLog()
            sut.registerGlobal(LifecycleRecordingPlugin(log: log))
            sut.pluginContentDidAppear(id: "lifecycle.recording")
            let expected = ["install", "visible", "hidden", "uninstall"]

            sut.unregisterGlobal(id: "lifecycle.recording")
            sut.pluginContentDidDisappear(id: "lifecycle.recording")

            #expect(log.hooks == expected)
            #expect(sut.visibleContentCounts.isEmpty)
        }

        @Test("Unregistering an ID the drawer doesn't hold calls no hook")
        func unregisteringAnUnknownID() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let log = LifecycleLog()
            sut.registerGlobal(LifecycleRecordingPlugin(log: log))
            let expected = ["install"]

            sut.unregisterGlobal(id: "lifecycle.other")
            sut.pluginContentDidAppear(id: "lifecycle.other")

            #expect(log.hooks == expected)
            #expect(sut.globalPlugins.count == 1)
        }

        @Test("Registering a global plugin whose ID is already registered installs nothing again")
        func duplicateIsNotInstalled() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let log = LifecycleLog()
            let expected = ["install"]

            sut.registerGlobal(LifecycleRecordingPlugin(log: log))
            sut.registerGlobal(LifecycleRecordingPlugin(log: log))

            #expect(log.hooks == expected)
        }

        @Test("A local plugin is installed as it registers and uninstalled as its registration is removed")
        func localHooks() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let log = LifecycleLog()
            let expected = ["install", "visible", "hidden", "uninstall"]

            let token = sut.registerLocal(LifecycleRecordingPlugin(log: log))
            sut.pluginContentDidAppear(id: "lifecycle.recording")
            sut.unregisterLocal(id: "lifecycle.recording", token: token)

            #expect(sut.localPlugins.isEmpty)
            #expect(log.hooks == expected)
        }

        @Test("A local plugin's new value, handed over by its view, is not installed again")
        func localUpdateKeepsTheInstall() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let log = LifecycleLog()
            let token = sut.registerLocal(LifecycleRecordingPlugin(log: log))
            let expected = ["install"]

            sut.updateLocal(LifecycleRecordingPlugin(log: log, title: "Renamed"), token: token)
            sut.moveLocal(token: token, to: ObjectIdentifier(sut))

            #expect(log.hooks == expected)
            #expect(sut.localPlugins.map(\.title) == ["Renamed"])
        }

        @Test("A local plugin a newer view registers again uninstalls the old registration, installs the new and keeps it visible")
        func localReplacementOnScreen() throws {
            let suite = "PluginLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let oldLog = LifecycleLog()
            let newLog = LifecycleLog()
            sut.registerLocal(LifecycleRecordingPlugin(log: oldLog))
            sut.pluginContentDidAppear(id: "lifecycle.recording")
            let expectedOld = ["install", "visible", "hidden", "uninstall"]
            let expectedNew = ["install", "visible", "hidden"]

            sut.registerLocal(LifecycleRecordingPlugin(log: newLog))
            sut.pluginContentDidDisappear(id: "lifecycle.recording")

            #expect(oldLog.hooks == expectedOld)
            #expect(newLog.hooks == expectedNew)
        }

        @Test("Two drawers hold their plugins apart: each installs and removes only its own")
        func twoDrawersShareNoPlugins() throws {
            let firstSuite = "PluginLifecycleTests.\(UUID().uuidString)"
            let secondSuite = "PluginLifecycleTests.\(UUID().uuidString)"
            let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
            let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
            defer {
                firstDefaults.removePersistentDomain(forName: firstSuite)
                secondDefaults.removePersistentDomain(forName: secondSuite)
            }
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let firstLog = LifecycleLog()
            let secondLog = LifecycleLog()
            first.registerGlobal(LifecycleRecordingPlugin(log: firstLog))
            second.registerGlobal(LifecycleRecordingPlugin(log: secondLog))
            second.registerGlobal(HooklessPlugin())
            let expectedFirst = [LifecycleLog.Event(hook: "install", drawer: ObjectIdentifier(first))]
            let expectedSecond = [
                LifecycleLog.Event(hook: "install", drawer: ObjectIdentifier(second)),
                LifecycleLog.Event(hook: "visible", drawer: ObjectIdentifier(second)),
                LifecycleLog.Event(hook: "hidden", drawer: ObjectIdentifier(second)),
                LifecycleLog.Event(hook: "uninstall", drawer: ObjectIdentifier(second))
            ]

            second.pluginContentDidAppear(id: "lifecycle.recording")
            second.unregisterGlobal(id: "lifecycle.recording")

            #expect(first.globalPlugins.map(\.id) == ["lifecycle.recording"])
            #expect(second.globalPlugins.map(\.title) == ["Hookless"])
            #expect(firstLog.events == expectedFirst)
            #expect(secondLog.events == expectedSecond)
            #expect(first.visibleContentCounts.isEmpty)
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.id == "lifecycle.recording" })
        }

        @Test("A drawer made with init() starts with no plugins, apart from the shared drawer")
        func aNewDrawerIsEmpty() {
            let sut = DebugDrawer()

            #expect(sut !== DebugDrawer.shared)
            #expect(!sut.hasPlugins)
        }

        #if os(macOS)
            @Test("A plugin's section body coming on screen makes it visible, and collapsing the section hides it")
            func aHostedSectionReportsVisibility() throws {
                let suite = "PluginLifecycleTests.\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let log = LifecycleLog()
                drawer.registerGlobal(LifecycleRecordingPlugin(log: log))
                let plugin = try #require(drawer.globalPlugins.first)
                let model = SectionModel()
                let window = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 400, height: 300),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: SectionScreen(model: model, plugin: plugin, drawer: drawer))
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }
                let expectedShown = ["install", "visible"]
                let expected = ["install", "visible", "hidden"]

                host.layoutSubtreeIfNeeded()
                let actualShown = log.hooks
                model.isExpanded = false
                host.layoutSubtreeIfNeeded()

                #expect(actualShown == expectedShown)
                #expect(log.hooks == expected)
            }
        #endif
    }

    #if os(macOS)
        /// Whether ``SectionScreen``'s section is expanded.
        @MainActor
        private final class SectionModel: ObservableObject {
            @Published var isExpanded = true
        }

        /// A plugin's section, as a drawer's outline shows it.
        private struct SectionScreen: View {
            @ObservedObject var model: SectionModel
            let plugin: AnyDebugDrawerPlugin
            let drawer: DebugDrawer

            var body: some View {
                DrawerPluginSection(plugin: plugin, isExpanded: model.isExpanded) {
                    Text(plugin.title)
                }
                .environment(\.showingDrawer, drawer)
            }
        }
    #endif
#endif

import DebugDrawer
import Foundation

// Every example app lists these same actions, so the test bench lives in one library they all link
// rather than in a copy per app: the SwiftUI apps show `TestBenchList`, the AppKit ones a Test
// Bench menu (`TestBenchMenu`) and the UIKit one a table of its own.

/// The example apps' test bench: actions that make each plugin record something on demand,
/// grouped by the plugin that shows it.
@MainActor
public enum TestBench {
    /// Launched with this argument and a comma-separated list of action identifiers, or `all`, the
    /// app runs them in turn once it has started: `-RunTestBench network.failure,console.levels`.
    /// `all` leaves out the actions that end or stall the app and the keychain write.
    public static let launchArgument = "-RunTestBench"
    /// Launched with this argument and a plugin's identifier, the app opens the drawer at that
    /// plugin once the actions `-RunTestBench` names have run: `-OpenDebugDrawerPlugin NetworkPlugin`.
    public static let openPluginArgument = "-OpenDebugDrawerPlugin"

    /// Every action, in the order the test bench lists them.
    public static let actions: [TestBenchAction] = [
        TestBenchAction(id: "console.levels", title: "Log at Every Level", plugin: "Console", perform: TestBenchConsole.logEveryLevel),
        TestBenchAction(id: "network.success", title: "GET example.com (200)", plugin: "Network", perform: TestBenchNetwork.fetchPage),
        TestBenchAction(
            id: "network.httpError", title: "GET a Missing Page (404)", plugin: "Network", perform: TestBenchNetwork.fetchMissingPage
        ),
        TestBenchAction(
            id: "network.failure", title: "GET an Unresolvable Host", plugin: "Network", perform: TestBenchNetwork.fetchUnresolvableHost
        ),
        TestBenchAction(
            id: "network.webSocket", title: "WebSocket: Echo Text and Binary, Ping, Close", plugin: "Network",
            perform: TestBenchNetwork.echoOverWebSocket
        ),
        TestBenchAction(
            id: "diskIO.mainThread", title: "Write, Read and Miss a File on the Main Thread", plugin: "Disk I/O",
            perform: TestBenchStorage.mainThreadFileIO
        ),
        TestBenchAction(
            id: "userDefaults.write", title: "Write UserDefaults Keys", plugin: "UserDefaults", perform: TestBenchStorage.writeDefaults
        ),
        TestBenchAction(
            id: "keychain.write", title: "Add a Generic Password", plugin: "Keychain", isIncludedInAll: false,
            perform: TestBenchStorage.addKeychainPassword
        ),
        TestBenchAction(id: "cookies.write", title: "Set Cookies", plugin: "HTTP Cookies", perform: TestBenchStorage.setCookies),
        TestBenchAction(id: "analytics.track", title: "Track an Event", plugin: "Analytics", perform: TestBenchDiagnostics.trackEvent),
        TestBenchAction(
            id: "leaks.retainCycle", title: "Leak Two Retain Cycles", plugin: "Leaks", perform: TestBenchDiagnostics.leakRetainCycles
        ),
        TestBenchAction(
            id: "hangs.mainThread", title: "Hang the Main Thread for 2 s", plugin: "Hangs", isIncludedInAll: false, isDestructive: true,
            perform: TestBenchDiagnostics.hangMainThread
        ),
        TestBenchAction(
            id: "crashReports.fatalError", title: "Crash the App", plugin: "Crash Reports", isIncludedInAll: false, isDestructive: true,
            perform: TestBenchDiagnostics.crash
        ),
        // As a sidecar app would, through the app's own store (ExampleSidecar). Left out of `all`,
        // so the other checks' screens show no session indicator.
        TestBenchAction(
            id: "sidecar.open", title: "Open a 60-Second Session", plugin: "Sidecar Session", isIncludedInAll: false,
            perform: { await ExampleSidecar.openSession(duration: 60) }
        ),
        TestBenchAction(
            id: "sidecar.elevateLogLevel", title: "Elevate the Log Level", plugin: "Sidecar Session", isIncludedInAll: false,
            perform: ExampleSidecar.elevateLogLevel
        ),
        TestBenchAction(
            id: "sidecar.end", title: "End the Session", plugin: "Sidecar Session", isIncludedInAll: false,
            perform: ExampleSidecar.endSession
        )
    ]

    /// The actions grouped by plugin, in the order each plugin's first action appears.
    public static var sections: [TestBenchSection] {
        let plugins = actions.map(\.plugin).reduce(into: [String]()) { plugins, plugin in
            if !plugins.contains(plugin) { plugins.append(plugin) }
        }
        return plugins.map { plugin in TestBenchSection(plugin: plugin, actions: actions.filter { $0.plugin == plugin }) }
    }

    /// Runs the actions `-RunTestBench` names, one after another, then opens the drawer at the plugin
    /// `-OpenDebugDrawerPlugin` names. Call it once the app has installed its plugins.
    public static func runFromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        let requested = value(after: launchArgument, in: arguments)
        let plugin = value(after: openPluginArgument, in: arguments)
        guard requested != nil || plugin != nil else { return }
        let names = Set((requested ?? "").split(separator: ",").map(String.init))
        let chosen = actions.filter { names.contains($0.id) || (names.contains("all") && $0.isIncludedInAll) }
        // Once the main run loop first waits, so the launch is over: Hangs doesn't count a stall
        // during launch, and the drawer is attached by then.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { _, _ in
            Task { @MainActor in
                for action in chosen {
                    _ = await action.run()
                }
                if let plugin {
                    // A toast is how a plugin asks the drawer to open at it.
                    DebugDrawer.shared.postToast("Opened by \(openPluginArgument)", fromPlugin: plugin)
                    DebugDrawer.shared.openToast()
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
}

import DebugDrawer
import DebugDrawerAccessibilityPlugin
import DebugDrawerAnalyticsPlugin
import DebugDrawerAppInfoPlugin
import DebugDrawerAppStateResetPlugin
import DebugDrawerBackgroundTasksPlugin
import DebugDrawerColorVisionPlugin
import DebugDrawerConsolePlugin
import DebugDrawerCookiesPlugin
import DebugDrawerCrashReportsPlugin
import DebugDrawerDatabaseBrowserPlugin
import DebugDrawerDeepLinkPlugin
import DebugDrawerDesignOverlayPlugin
import DebugDrawerDiskIOPlugin
import DebugDrawerEnergyPlugin
import DebugDrawerFeatureFlagsPlugin
import DebugDrawerFileBrowserPlugin
import DebugDrawerHangDetectorPlugin
import DebugDrawerKeychainPlugin
import DebugDrawerLaunchTimePlugin
import DebugDrawerLeakDetectorPlugin
import DebugDrawerLoadedLibrariesPlugin
import DebugDrawerLocalizationPlugin
import DebugDrawerLocationPlugin
import DebugDrawerMetricKitPlugin
import DebugDrawerNetworkPlugin
import DebugDrawerNotificationsPlugin
import DebugDrawerPerformancePlugin
import DebugDrawerPermissionsPlugin
import DebugDrawerScreenRecordingPlugin
import DebugDrawerScreenshotPlugin
import DebugDrawerTweaksPlugin
import DebugDrawerUserDefaultsPlugin
import DebugDrawerViewInspectorPlugin
import Foundation

// Every global plugin, each with its defaults, for the examples with no SwiftUI root: the UIKit app
// and the AppKit app link this one library rather than each keeping a copy, and show that such a
// host gets every plugin. The few that need the app's own values (tweaks, flags) get small ones here.
// The SwiftUI examples install the same plugins with their own sample data and launch arguments.

/// The plugins the UIKit and AppKit examples install.
@MainActor
public enum ExamplePlugins {
    /// Installs every global plugin. Each compiles in release too, where it does nothing; Background
    /// Tasks does nothing on macOS either, which has no BGTaskScheduler.
    ///
    /// - Parameter openURL: Where the Deep Link Tester sends the URLs it opens: the app's own
    ///   routing, which returns whether it took the URL.
    public static func install(openURL: @escaping @MainActor (URL) -> Bool) {
        // First, so a crash in the rest of startup is recorded.
        CrashReports.install()
        Localization.install()
        HangDetector.install()
        LeakDetector.install()
        MetricKitPayloads.install()
        PrivacyPermissions.install()
        PushNotifications.install()
        BackgroundTaskRequests.install()
        AnalyticsEvents.install()
        DatabaseBrowser.install()
        ScreenRecording.install()
        DesignOverlay.install()
        ColorVision.install()
        AppStateReset.install()
        UserDefaultsBrowser.install()
        FileBrowser.install()
        // No continueUserActivity handler: an activity the Deep Link Tester sends goes where the
        // system sends it, to the UIKit app's scene(_:continue:) or the AppKit app's
        // application(_:continue:restorationHandler:). A URL it opens goes to the app's own routing.
        DebugDrawer.shared.installDeepLink(openURL: openURL)
        DebugDrawer.shared.installNetwork()
        DebugDrawer.shared.installConsole()
        DebugDrawer.shared.installDiskIO()
        DebugDrawer.shared.installViewInspector()
        DebugDrawer.shared.installAccessibility()
        DebugDrawer.shared.installPerformance()
        DebugDrawer.shared.installEnergy()
        DebugDrawer.shared.installScreenshot()
        DebugDrawer.shared.installAppInfo()
        DebugDrawer.shared.installKeychain()
        DebugDrawer.shared.installLocation()
        DebugDrawer.shared.installLoadedLibraries()
        DebugDrawer.shared.installCookies()
        DebugDrawer.shared.installLaunchTime()
        DebugDrawer.shared.installTweaks {
            TweakSection("Greeting") {
                greeting
            }
        }
        DebugDrawer.shared.installFeatureFlags(provider: flags)
    }

    /// The text the screen's greeting would read.
    static let greeting = Tweak.text("Greeting", key: "exampleGreeting", default: "Hello from the example")

    /// The example's feature flags, held in memory.
    static let flags = ExampleFeatureFlagAdapter([
        FeatureFlag(key: "new-checkout", liveValue: .bool(false), title: "New checkout", detail: "The one-page payment sheet")
    ])
}

/// A sample adapter, standing in for a flag service's SDK: the flags' live values held in memory,
/// with the overrides the drawer applies winning over them.
final class ExampleFeatureFlagAdapter: FeatureFlagProvider {
    private let live: [FeatureFlag]
    private var overrides: [String: FeatureFlagValue] = [:]

    init(_ live: [FeatureFlag]) {
        self.live = live
    }

    func flags() -> [FeatureFlag] {
        live
    }

    func currentValue(forKey key: String) -> FeatureFlagValue? {
        overrides[key] ?? live.first { $0.key == key }?.liveValue
    }

    func setOverride(_ value: FeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

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

// The same global plugins the SwiftUI iOS example installs, each with its defaults: this app shows
// that a UIKit host gets every one of them. The examples share no code, so the few that need the
// app's own values (tweaks, flags) declare small ones here.

/// The plugins the UIKit example installs.
@MainActor
enum ExampleUIKitPlugins {
    /// Installs every global plugin. Each compiles in release too, where it does nothing.
    static func install() {
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
        // No handler: an activity the Deep Link Tester sends goes to the scene delegate's
        // scene(_:continue:).
        DebugDrawer.shared.installDeepLink()
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
    static let greeting = Tweak.text("Greeting", key: "uikitGreeting", default: "Hello from UIKit")

    /// The example's feature flags, held in memory.
    static let flags = ExampleUIKitFeatureFlags([
        FeatureFlag(key: "new-checkout", liveValue: .bool(false), title: "New checkout", detail: "The one-page payment sheet")
    ])
}

/// A sample adapter, standing in for a flag service's SDK: the flags' live values held in memory,
/// with the overrides the drawer applies winning over them.
final class ExampleUIKitFeatureFlags: FeatureFlagProvider {
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

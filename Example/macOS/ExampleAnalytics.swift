import DebugDrawerAnalyticsPlugin
import Foundation

// The iOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's analytics: it has no analytics service, so each event goes only to the
/// Analytics plugin, as a real app would record it beside the call to its SDK.
enum ExampleAnalytics {
    /// Launched with this argument, the app tracks one of each sample event at startup, so the
    /// plugin can be checked without a hand.
    static let launchArgument = "-TrackSampleAnalyticsEvents"

    /// Where the app would hand an event to its analytics SDK. In release it records nothing.
    static func track(_ name: String, properties: [String: AnalyticsValue] = [:]) {
        AnalyticsEvents.record(name, properties: properties, source: "Example")
    }

    /// The counter changed through one of its buttons.
    static func trackCounter(_ action: String, value: Int) {
        track("counter_changed", properties: ["action": .string(action), "value": .int(value)])
    }

    /// One of a few sample events, a different one each press, with properties of every kind.
    @MainActor
    static func trackSample() {
        let samples = sampleEvents
        track(samples[nextSample].name, properties: samples[nextSample].properties)
        nextSample = (nextSample + 1) % samples.count
    }

    /// Every sample event, once.
    static func trackAllSamples() {
        for sample in sampleEvents {
            track(sample.name, properties: sample.properties)
        }
    }

    /// The sample the next press tracks.
    @MainActor private static var nextSample = 0

    private static var sampleEvents: [(name: String, properties: [String: AnalyticsValue])] {
        [
            ("screen_viewed", ["screen": "Home", "dark_mode": false]),
            ("checkout_completed", [
                "plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil,
                "items": ["sku-1", "sku-2"], "shipping": ["country": "NZ", "express": true],
                "renews": .date(Date().addingTimeInterval(30 * 86400))
            ]),
            ("signed_in", ["method": "email", "auth_token": "t0k3n-shown-masked"]),
            ("onboarding_paywall_viewed_after_trial_reminder_notification", ["variant": "b", "step": 4])
        ]
    }
}

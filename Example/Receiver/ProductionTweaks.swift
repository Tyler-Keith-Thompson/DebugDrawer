import DebugDrawerTweaks

/// The example's tweaks: the greeting is production-safe, so a sidecar may change it in release;
/// the diagnostics toggle isn't, so it stays at its default there and a sidecar never sees it.
enum ProductionTweaks {
    static let greeting = Tweak.text("Greeting", key: "greeting", default: "Welcome").productionSafe()
    static let diagnostics = Tweak.toggle("Diagnostics", key: "diagnostics", default: false)
}

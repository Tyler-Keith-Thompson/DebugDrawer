import Combine

public extension Tweak {
    /// The tweak's current value: what the drawer or a sidecar last set, kept across launches, or
    /// ``defaultValue`` when nothing is stored or what is stored isn't one of its values.
    ///
    /// In release, ``defaultValue``, unless the tweak is ``productionSafe(_:)`` and the app has
    /// made the receiver's tweaks capability (`DebugDrawerReceiverCapability.tweaks(_:storage:scope:)`):
    /// then what a sidecar stored. Make the capability at startup, before the app reads a tweak.
    @MainActor var value: Value {
        TweakStore.shared.value(of: self)
    }

    /// The current value, then each new value as the drawer or a sidecar changes it, on the main
    /// thread. In release, ``defaultValue`` alone, unless the tweak is production-safe and offered
    /// to a sidecar, as ``value`` says.
    @MainActor var publisher: AnyPublisher<Value, Never> {
        TweakStore.shared.publisher(for: self)
    }
}

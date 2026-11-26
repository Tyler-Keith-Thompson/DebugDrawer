import DebugDrawerReceiver

// The capability lives with the tweaks, not in the receiver: the receiver knows models, not
// plugins, and a host that offers no tweaks links none of this. It is persistent by default, as a
// tweak is a setting the app keeps across launches; a host that wants a sidecar's changes gone
// with its session passes `.session(revertWith: .resetAll)`. The values persist in the tweaks'
// storage, so a session the app was killed in would leave them set: the receiver's record of
// unreverted changes resets them as the next launch enables the capability, which the tweaks keep
// no record of their own for.

public extension DebugDrawerReceiverCapability {
    /// The tweaks marked ``Tweak/productionSafe(_:)`` among `tweak`: a sidecar sees them with the
    /// values the app reads now and, within a session, sets or resets them; every other tweak is
    /// left out, and a command naming one is refused and audited. Changes go into `storage`, so
    /// each tweak's ``Tweak/value`` reads them, in a release build too, and they persist across
    /// launches.
    ///
    /// ```swift
    /// try receiver.enable(.tweaks(AppTweaks.backend, AppTweaks.timeout))
    /// ```
    ///
    /// Make it at startup, before the app reads a tweak: until then a release build reads every
    /// tweak's default.
    ///
    /// - Parameters:
    ///   - tweak: The tweaks a sidecar may change, if production-safe.
    ///   - storage: Where values persist; the same storage `installTweaks(storage:_:)` takes, in
    ///     a build that has the drawer. The standard defaults, under
    ///     ``UserDefaultsTweakStorage/defaultKeyPrefix``, unless given.
    ///   - scope: What becomes of a sidecar's changes when its session ends: kept, by default, or
    ///     reverted with a command such as ``TweaksModel/Command/resetAll``. Reverted also as the
    ///     next launch enables the capability, when the app was killed or quit during the
    ///     session.
    /// - Returns: The capability, under ``TweaksModel/pluginID``.
    /// - Throws: ``TweaksModel/InvalidTweaks`` when two of the tweaks share a key, a picker's
    ///   default isn't one of its options, or a stepper's default is outside its range or its step
    ///   isn't positive, whether production-safe or not. Nothing changes: the tweaks keep reading
    ///   the storage they read before.
    static func tweaks<each Value: Sendable & Equatable>(
        _ tweak: repeat Tweak<each Value>,
        storage: some TweakStorage = UserDefaultsTweakStorage(),
        scope: DebugDrawerChangeScope<TweaksModel> = .persistent
    ) throws(TweaksModel.InvalidTweaks) -> Self {
        var tweaks: [AnyTweak] = []
        for tweak in repeat each tweak {
            tweaks.append(AnyTweak(tweak))
        }
        // Checked before the shared store takes `storage`, so a refused list leaves what every
        // tweak reads as it was.
        try AnyTweak.check(tweaks)
        TweakStore.shared.use(storage)
        return try .tweaks(tweaks, store: .shared, scope: scope)
    }

    /// The production-safe ones among `tweaks`, over `store`.
    ///
    /// - Throws: ``TweaksModel/InvalidTweaks`` when two of `tweaks` share a key, or one can't hold
    ///   its own default.
    package static func tweaks(
        _ tweaks: [AnyTweak], store: TweakStore, scope: DebugDrawerChangeScope<TweaksModel>
    ) throws(TweaksModel.InvalidTweaks) -> Self {
        let model = try TweaksModel(tweaks: tweaks, store: store)
        return .model(model, id: TweaksModel.pluginID, scope: scope, refusal: model.refusal(of:))
    }
}

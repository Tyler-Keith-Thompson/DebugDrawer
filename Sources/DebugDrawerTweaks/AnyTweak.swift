/// A ``Tweak`` without its value type, for the drawer and the receiver's tweaks capability,
/// which edit stored values.
package struct AnyTweak: Sendable {
    package let title: String
    package let key: String
    package let isProductionSafe: Bool
    package let control: TweakControl
    package let defaultValue: TweakStoredValue
    /// The stored value the tweak reads as: what is stored, if it is one of the tweak's values,
    /// otherwise the default (a picker's removed option, a stepper's value clamped to its range).
    package let resolve: @Sendable (TweakStoredValue?) -> TweakStoredValue

    package init<Value>(_ tweak: Tweak<Value>) {
        title = tweak.title
        key = tweak.key
        isProductionSafe = tweak.isProductionSafe
        control = tweak.control
        defaultValue = tweak.storedValue(of: tweak.defaultValue)
        resolve = { tweak.storedValue(of: tweak.value(from: $0)) }
    }
}

// The check lives with the tweaks rather than in each container, so the drawer's plugin and the
// receiver's capability (real in every build) refuse the same declarations with the same error.
extension AnyTweak {
    /// Throws when two of `tweaks` share a key, so they would share a stored value, or one can't
    /// hold its own default.
    ///
    /// - Parameter tweaks: The tweaks a container is made with.
    /// - Throws: ``TweaksModel/InvalidTweaks``, for the first problem found.
    package static func check(_ tweaks: [AnyTweak]) throws(TweaksModel.InvalidTweaks) {
        guard Set(tweaks.map(\.key)).count == tweaks.count else { throw .duplicateKey }
        for tweak in tweaks {
            try tweak.checkDefault()
        }
    }

    /// Throws when the tweak's control can't hold its default: a picker's default not among its
    /// options, a stepper's outside its range or a step that isn't positive.
    private func checkDefault() throws(TweaksModel.InvalidTweaks) {
        switch control {
        case let .picker(options):
            guard options.contains(where: { $0.value == defaultValue }) else { throw .pickerDefaultNotAnOption }
        case let .stepper(range, step):
            guard let value = defaultValue.int, range.contains(value) else { throw .stepperDefaultOutOfRange }
            guard step > 0 else { throw .stepperStepNotPositive }
        case .toggle, .text:
            return
        }
    }
}

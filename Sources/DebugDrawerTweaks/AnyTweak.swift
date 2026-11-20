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

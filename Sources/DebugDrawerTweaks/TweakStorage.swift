import Foundation

/// Where tweak values persist between launches, by key.
///
/// The drawer and the receiver's tweaks capability read and write it on the main actor. The
/// default, ``UserDefaultsTweakStorage``, keeps them in the standard defaults; pass another to
/// `installTweaks(storage:_:)`, and the same to
/// `DebugDrawerReceiverCapability.tweaks(_:storage:scope:)`, to keep them elsewhere. In release
/// only the production-safe tweaks offered to a sidecar are read from it.
public protocol TweakStorage {
    /// The value stored for `key`, or `nil` if none is.
    func value(forKey key: String) -> TweakStoredValue?

    /// Stores `value` for `key`; `nil` removes the stored value, so the tweak reads its default.
    func setValue(_ value: TweakStoredValue?, forKey key: String)
}

/// Tweak values in `UserDefaults`, each under its key with a prefix in front, so they can't
/// collide with the app's own keys.
public struct UserDefaultsTweakStorage: TweakStorage {
    /// The prefix the default storage puts in front of every key.
    public static let defaultKeyPrefix = "com.debugdrawer.tweaks."

    /// The defaults the values live in.
    public let defaults: UserDefaults
    /// What goes in front of each tweak's key to make its defaults key.
    public let keyPrefix: String

    /// - Parameters:
    ///   - defaults: The defaults to keep values in; the standard defaults unless given.
    ///   - keyPrefix: What goes in front of each tweak's key.
    public init(defaults: UserDefaults = .standard, keyPrefix: String = Self.defaultKeyPrefix) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func value(forKey key: String) -> TweakStoredValue? {
        switch defaults.object(forKey: keyPrefix + key) {
        case let string as String:
            .string(string)
        // A Bool and an Int both come back as an NSNumber; only a Bool's is a CFBoolean.
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            .bool(number.boolValue)
        case let number as NSNumber:
            .int(number.intValue)
        default:
            nil
        }
    }

    public func setValue(_ value: TweakStoredValue?, forKey key: String) {
        switch value {
        case let .bool(bool): defaults.set(bool, forKey: keyPrefix + key)
        case let .int(int): defaults.set(int, forKey: keyPrefix + key)
        case let .string(string): defaults.set(string, forKey: keyPrefix + key)
        case nil: defaults.removeObject(forKey: keyPrefix + key)
        }
    }
}

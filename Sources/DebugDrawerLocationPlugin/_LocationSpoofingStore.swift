#if DEBUG
    import Foundation

    /// The switch and coordinate kept in a defaults suite: the drawer's own, apart from the app's
    /// defaults. The switch is a Boolean and the latitude and longitude a number each, under keys
    /// of their own; no coordinate removes both.
    struct _LocationSpoofingStore: LocationSpoofingStore {
        static let enabledKey = "com.debugdrawer.location.enabled"
        static let latitudeKey = "com.debugdrawer.location.latitude"
        static let longitudeKey = "com.debugdrawer.location.longitude"

        // nonisolated(unsafe): UserDefaults is documented thread-safe but not marked Sendable, and
        // the simulator reads the store from whatever thread a manager is called on.
        nonisolated(unsafe) let defaults: UserDefaults

        init(defaults: UserDefaults) {
            self.defaults = defaults
        }

        var isEnabled: Bool {
            get { defaults.bool(forKey: Self.enabledKey) }
            nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
        }

        var coordinate: LocationCoordinate? {
            get {
                guard let latitude = defaults.object(forKey: Self.latitudeKey) as? Double,
                      let longitude = defaults.object(forKey: Self.longitudeKey) as? Double
                else { return nil }
                return LocationCoordinate(latitude: latitude, longitude: longitude)
            }
            nonmutating set {
                defaults.set(newValue?.latitude, forKey: Self.latitudeKey)
                defaults.set(newValue?.longitude, forKey: Self.longitudeKey)
            }
        }
    }
#endif

import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that swizzles and registers nothing.

/// Spoofs the location the app's `CLLocationManager`s report: a fixed coordinate, a preset, or a
/// GPX route played back in time.
///
/// While spoofing is on and a coordinate is set or a route plays, a manager that calls
/// `startUpdatingLocation` gets the simulated location instead of real updates, then each new
/// coordinate or route point as it changes; `requestLocation` and `location` answer with it too.
/// A manager already updating when spoofing begins stops getting real updates, and turning
/// spoofing off starts them again. The switch and the coordinate are kept across launches.
///
/// Only `CLLocationManager`'s location updates are covered. These still report the real
/// location, which on the iOS simulator is the one Xcode or `simctl location` sets:
///
/// - `CLLocationUpdate.liveUpdates()` and `CLMonitor`: no public API reaches what they yield.
/// - MapKit's user location (`showsUserLocation`, `UserAnnotation`, `MapUserLocationButton`).
/// - Region monitoring, significant-change and visit updates, and heading.
///
/// Authorization isn't simulated: `authorizationStatus` is the real one, and a spoofed location
/// is delivered whether or not the app is authorized.
///
/// Its state and behavior are ``LocationModel``'s, which the plugin's view draws through a
/// `DebugDrawerPluginTransport`.
public struct LocationPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "LocationPlugin"
    }

    public var title = "Location Simulator"
    public var category = "App"
    public var icon = "location.circle"

    #if DEBUG
        /// The model the plugin shows, or `nil` for the shared one.
        private let model: LocationModel?

        public init() {
            model = nil
        }

        /// - Parameter model: The model to show and install in place of the shared one.
        init(model: LocationModel) {
            self.model = model
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            LocationPluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Swaps `CLLocationManager`'s location methods for the simulator's as `drawer` adds the
    /// plugin, so spoofing kept from the last launch is in effect at once. Release builds swap
    /// nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once no drawer holds the plugin, stops a route playing, hands every manager the simulator
    /// tracked back to Core Location (one given a simulated location gets its real updates
    /// started again) and gives each swapped method its original implementation back. The switch
    /// and the coordinate stay saved for the next install.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers ``LocationPlugin`` and swaps `CLLocationManager`'s location methods for the
    /// simulator's, so spoofing kept from the last launch is in effect at once.
    ///
    /// Call it at startup, before the app starts location updates: a manager that started
    /// before it isn't tracked. Release builds do nothing.
    func installLocation() {
        #if DEBUG
            // Adding the plugin installs it, which swaps the methods.
            registerGlobal(LocationPlugin())
        #endif
    }
}

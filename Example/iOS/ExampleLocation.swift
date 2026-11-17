import CoreLocation
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// A location manager of the app's own, created as the app creates one, and the last location its
/// delegate was given. With spoofing on, the Location plugin's coordinate or route reaches it.
/// It asks for no permission and starts no updates, so it shows only what the plugin delivers.
@MainActor
final class ExampleLocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var latest: CLLocation?
    @Published private(set) var count = 0
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        // The plugin delivers on the main thread, as Core Location does to a manager made there.
        MainActor.assumeIsolated {
            latest = last
            count += locations.count
        }
    }
}

/// The app's readout of the last location its manager was given: coordinate, course, speed and
/// time.
struct ExampleLocationReadout: View {
    @StateObject private var model = ExampleLocationModel()

    var body: some View {
        // Three lines whether or not a location has come, so a List row keeps its height as one
        // arrives: UIKit's list measured the row once and clipped the readout that replaced the
        // placeholder.
        VStack(alignment: .leading, spacing: 4) {
            Text(model.latest.map { String(format: "%.5f, %.5f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "No location yet")
                .font(.body.monospacedDigit())
            Text(model.latest.map(Self.motion(of:)) ?? "Turn on Spoof Location in the drawer, or play a route.")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(model.latest.map { "Update \(model.count) at \($0.timestamp.formatted(date: .omitted, time: .standard))" } ?? "No updates")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private static func motion(of location: CLLocation) -> String {
        let course = location.course < 0 ? "no course" : "course \(Int(location.course.rounded()))°"
        let speed = location.speed < 0 ? "no speed" : String(format: "%.1f m/s", location.speed)
        return "\(course), \(speed)"
    }
}

import CoreGraphics
import Foundation

/// Which plugins are pinned to the floating HUD and where it sits, saved across launches.
public struct HUDLayout: Codable, Equatable, Sendable {
    /// The `UserDefaults` key the layout is saved under.
    static let defaultsKey = "com.debugdrawer.hud"

    /// Pinned plugins' IDs, in the order they were pinned: the HUD lists them in this order.
    public internal(set) var pinned: [String] = []

    /// The HUD's top-leading corner in the window, or `nil` for the default corner.
    public internal(set) var origin: CGPoint?

    init() {}

    /// The layout saved in `defaults`, or an empty one when none is saved or it can't be read.
    init(from defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode(Self.self, from: data)
        else { return }
        self = saved
    }

    func save(to defaults: UserDefaults) {
        // Encoding plain strings and an optional point can't fail.
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    /// Pins `id` at the end of the HUD, or unpins it if it is pinned.
    mutating func togglePin(_ id: String) {
        if let index = pinned.firstIndex(of: id) {
            pinned.remove(at: index)
        } else {
            pinned.append(id)
        }
    }
}

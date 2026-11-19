#if DEBUG
    import Foundation

    // `powerSource` stays the system's own words: the Mac's IOKit reports "AC Power" or "Battery
    // Power" (and may add states), iOS has no such string and gets "AC Power" or "Battery", and the
    // drawer shows each as the platform says it.

    /// What the battery reader read: the charge, whether it is charging and what powers the device.
    struct BatteryReading: Codable, Equatable, Sendable {
        /// The charge in percent, or -1 where there is no battery (a desktop Mac) or no reading.
        var level: Int
        /// Whether the battery is charging or full on external power.
        var isCharging: Bool
        /// What powers the device, in the platform's words.
        var powerSource: String
    }

    /// One battery sample in the Energy snapshot's history.
    struct BatterySample: Codable, Equatable, Sendable {
        /// When it was taken.
        var timestamp: Date
        /// The charge in percent.
        var level: Int
        /// Whether the battery was charging.
        var isCharging: Bool
    }
#endif

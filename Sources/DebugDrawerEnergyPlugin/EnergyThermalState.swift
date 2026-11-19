#if DEBUG
    import Foundation

    // `ProcessInfo.ThermalState` isn't `Codable`, and a reader in another process may run an SDK
    // with cases this one lacks, so the snapshot carries the plugin's own enum, with a case for a
    // state this build doesn't know.

    /// The system's thermal state, as the Energy snapshot carries it.
    enum EnergyThermalState: String, Codable, Equatable, Sendable, CaseIterable {
        case nominal
        case fair
        case serious
        case critical
        /// A state the system reported that this build doesn't know.
        case unknown

        /// - Parameter state: The state `ProcessInfo` reported.
        init(_ state: ProcessInfo.ThermalState) {
            switch state {
            case .nominal: self = .nominal
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            @unknown default: self = .unknown
            }
        }
    }
#endif

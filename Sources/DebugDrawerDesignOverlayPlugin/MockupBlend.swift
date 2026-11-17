#if DEBUG
    import SwiftUI

    /// How the mockup is drawn over the app.
    enum MockupBlend: String, Codable, CaseIterable, Sendable {
        /// Over the app, at the overlay's opacity.
        case normal
        /// The difference of each of the mockup's pixels and the app's: black where they match,
        /// bright where they drift.
        case difference

        /// The blend SwiftUI draws it with.
        var blendMode: BlendMode {
            switch self {
            case .normal: .normal
            case .difference: .difference
            }
        }

        /// The name the blend picker shows.
        var title: String {
            switch self {
            case .normal: "Normal"
            case .difference: "Difference"
            }
        }
    }
#endif

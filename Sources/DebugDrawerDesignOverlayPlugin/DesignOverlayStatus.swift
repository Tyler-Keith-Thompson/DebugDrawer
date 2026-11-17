#if DEBUG
    /// What the overlay is doing, as the header and the HUD say it.
    enum DesignOverlayStatus: Equatable {
        /// No mockup picked.
        case noMockup
        /// The mockup shows, at an opacity ("50%"), in a blend.
        case showing(opacity: String, blend: MockupBlend)
        /// The mockup is picked but hidden.
        case hidden
        /// Move is on: a drag moves the mockup.
        case moving

        init(hasMockup: Bool, settings: DesignOverlaySettings, isMoving: Bool) {
            self = if !hasMockup {
                .noMockup
            } else if isMoving {
                .moving
            } else if settings.isVisible {
                .showing(opacity: settings.opacityText, blend: settings.blend)
            } else {
                .hidden
            }
        }

        /// The header's readout ("50% · Difference"), or `nil` before a mockup is picked.
        var summary: String? {
            switch self {
            case .noMockup: nil
            case let .showing(opacity, .normal): opacity
            case let .showing(opacity, blend): "\(opacity) · \(blend.title)"
            case .hidden: "Hidden"
            case .moving: "Moving"
            }
        }
    }
#endif

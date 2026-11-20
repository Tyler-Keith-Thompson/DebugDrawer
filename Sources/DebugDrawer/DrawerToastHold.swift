#if DEBUG
    /// Something that keeps the toast on screen past ``DebugDrawer/toastLifetime`` for as long as
    /// it lasts, so the toast doesn't leave while someone is reading or reaching for it.
    enum DrawerToastHold: Hashable {
        /// The pointer is over the toast (the Mac's, or a trackpad's on iPadOS and visionOS).
        case pointer
        /// VoiceOver or another assistive technology has focus on one of the toast's buttons.
        case accessibilityFocus
    }
#endif

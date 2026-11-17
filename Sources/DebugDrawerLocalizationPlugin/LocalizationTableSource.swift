#if DEBUG
    /// Where the plugin reads the app's localized strings from: the seam tests replace with
    /// bundles of their own.
    protocol LocalizationTableSource: Sendable {
        /// Every localized bundle of the app, the main bundle first.
        func bundles() -> [LocalizedBundle]
    }
#endif

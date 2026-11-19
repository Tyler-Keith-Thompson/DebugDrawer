#if DEBUG
    /// The app's signing, read the first time App Info is shown or reported, then kept: it can't
    /// change while the process runs, and App Info's model reads its facts every two seconds while
    /// shown. ``AppInfoModel`` keeps one.
    @MainActor
    final class AppSigningStore {
        private let source: any SigningInformation
        private var read: AppSigning?

        init(source: any SigningInformation) {
            self.source = source
        }

        var signing: AppSigning {
            if let read { return read }
            let signing = AppSigning(reading: source)
            read = signing
            return signing
        }
    }
#endif

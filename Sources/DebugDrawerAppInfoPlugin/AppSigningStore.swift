#if DEBUG
    /// The app's signing, read the first time App Info is shown or reported, then kept: it can't
    /// change while the process runs, and the drawer redraws App Info every two seconds.
    @MainActor
    final class AppSigningStore {
        static let shared = AppSigningStore(source: _SigningInformation())

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

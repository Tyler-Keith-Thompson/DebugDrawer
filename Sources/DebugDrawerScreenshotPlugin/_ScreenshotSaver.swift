#if DEBUG
    import Foundation

    /// Writes captures to the user's Desktop.
    struct _ScreenshotSaver: ScreenshotSaver {
        func save(_ png: Data, as filename: String) throws(ScreenshotFailure) -> ScreenshotFile {
            guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                throw .noDesktop
            }
            do {
                return try ScreenshotFile.save(png, as: filename, in: desktop)
            } catch {
                throw .writeFailed(error.localizedDescription)
            }
        }
    }
#endif

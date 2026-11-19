#if os(macOS)
    import Foundation

    /// Points this process's home folder at a new, empty temporary directory, and returns it.
    ///
    /// Plugins keep their files in Application Support under the home folder, which Foundation
    /// reads from `CFFIXED_USER_HOME`. The test runners point it at one temporary folder that the
    /// test process and every exit test's child share. Call this first in an exit test's child when
    /// what it installs touches files other tests own: a plugin installed with `sessions: .off`
    /// keeps no sessions, so it deletes every earlier session file it finds, including those of
    /// the children running beside it.
    ///
    /// Traps when Application Support doesn't move with it, so a child can't go on in the shared
    /// folder unnoticed.
    @discardableResult
    public func useHomeFolderOfItsOwn() -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID().uuidString)", directoryHint: .isDirectory)
        let path = home.path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("No home folder made at \(path): \(error)")
        }
        setenv("CFFIXED_USER_HOME", path, 1)
        precondition(
            URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(path),
            "Application Support is still \(URL.applicationSupportDirectory.path(percentEncoded: false)), not under \(path)"
        )
        return home
    }
#endif

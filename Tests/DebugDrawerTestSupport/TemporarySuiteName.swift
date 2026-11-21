import Foundation

/// A new UserDefaults suite name, `<folder>/<label>.<UUID>`, whose file lives in a temporary folder
/// rather than in the user's preferences.
///
/// A plain suite name keeps its file in `~/Library/Preferences/<name>.plist` whatever
/// `CFFIXED_USER_HOME` says, and nothing a test does takes it back: `removePersistentDomain(forName:)`
/// empties the file without removing it, and the preferences daemon writes a suite's later changes
/// some seconds after they're made, so a file a test deletes comes back once the test is over.
/// `UserDefaults(suiteName:)` also takes an absolute path for a name, and keeps that suite in
/// `<name>.plist` at that path. The folder is `UserDefaultsSuites` in the home folder the test
/// runners make for each run (`CFFIXED_USER_HOME`, removed after the run), or in the temporary
/// directory when none is set (the simulators). It's never a `Library/Preferences` folder: the
/// daemon reads a path ending in one as a plain name in the user's own.
///
/// The path is absolute, so an exit test's child handed the name reaches the same suite, even after
/// `useHomeFolderOfItsOwn()`. Every call returns a new name.
///
/// - Parameter label: What the name starts with, such as the suite and test: `"NoticeMutingTests.\(#function)"`.
/// - Returns: The suite's name, for `UserDefaults(suiteName:)` and `removePersistentDomain(forName:)`.
/// - Precondition: `label` holds no slash.
public func temporarySuiteName(_ label: String) -> String {
    precondition(!label.contains("/"), "A suite's label names a file, so it can't hold a slash: \(label)")
    let folder = temporarySuiteFolder()
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
        preconditionFailure("No folder for UserDefaults suites at \(folder.path(percentEncoded: false)): \(error)")
    }
    let name = folder.appending(path: "\(label).\(UUID().uuidString)").path(percentEncoded: false)
    // Read once while the file doesn't exist yet. A process whose first read of a suite named by a
    // path finds a file another process wrote (an exit test's parent after its child) keeps showing
    // that file's values after it removes one of them, though the file loses it. Read first, it
    // shows each removal and still sees the other process's writes.
    _ = UserDefaults(suiteName: name)?.object(forKey: name)
    return name
}

private func temporarySuiteFolder() -> URL {
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    return (home ?? FileManager.default.temporaryDirectory).appending(path: "UserDefaultsSuites", directoryHint: .isDirectory)
}

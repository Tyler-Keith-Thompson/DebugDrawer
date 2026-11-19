// The interception contract's checks (DebugDrawerInterceptionContract). Exit tests start a child
// process, which only the Mac's test runs can do; installing swizzles Foundation for the whole
// process, so each check runs in a child of its own.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    import DebugDrawerInterceptionContract
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import ObjectiveC
    import Testing

    /// The Disk I/O plugin's side of the contract, in a folder of its own: each captured call
    /// creates a file named by its marker.
    @MainActor
    private struct DiskIOContract: UnchangedResultContract, DrawerActivityContract {
        /// What the app's file calls got back.
        struct AppResult: Equatable {
            var wrote: Bool
            var read: Data?
            var listed: [String]
            var missingRead: Data?
            var removeMissingError: Int?
        }

        let directory: String

        static func made() throws -> Self {
            let directory = FileManager.default.temporaryDirectory.appending(path: "DiskIOContract-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return Self(directory: directory.path(percentEncoded: false))
        }

        func install(in drawer: DebugDrawer) {
            drawer.installDiskIO()
        }

        func uninstall(from drawer: DebugDrawer) {
            drawer.unregisterGlobal(id: DiskIOPlugin().id)
        }

        /// The implementations of methods of each kind the plugin replaces: swapped `FileManager`
        /// and `NSData` methods (and one they are swapped with), the replaced `NSData`
        /// initializers and a swapped `FileHandle` method.
        func processState() throws -> [IMP] {
            let handleClass: AnyClass = try #require(object_getClass(FileHandle(fileDescriptor: STDERR_FILENO, closeOnDealloc: false)))
            let methods = try [
                #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.contents(atPath:)))),
                #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.dd_contents(atPath:)))),
                #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.createFile(atPath:contents:attributes:)))),
                #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.removeItem(at:)))),
                #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.contentsOfDirectory(atPath:)))),
                #require(class_getInstanceMethod(NSData.self, #selector(NSData.write(toFile:atomically:)))),
                #require(class_getInstanceMethod(NSData.self, NSSelectorFromString("initWithContentsOfFile:"))),
                #require(class_getInstanceMethod(NSData.self, NSSelectorFromString("initWithContentsOfURL:options:error:"))),
                #require(class_getInstanceMethod(handleClass, NSSelectorFromString("writeData:")))
            ]
            return methods.map(method_getImplementation)
        }

        func makeAppCall() async throws -> AppResult {
            let folder = (directory as NSString).appendingPathComponent("app-\(UUID().uuidString)")
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
            let file = (folder as NSString).appendingPathComponent("file")
            let wrote = (Data("contents".utf8) as NSData).write(toFile: file, atomically: true)
            let read = FileManager.default.contents(atPath: file)
            let listed = try FileManager.default.contentsOfDirectory(atPath: folder)
            let missing = (folder as NSString).appendingPathComponent("missing")
            let missingRead = FileManager.default.contents(atPath: missing)
            var removeMissingError: Int?
            do {
                try FileManager.default.removeItem(at: URL(filePath: missing))
            } catch {
                removeMissingError = (error as NSError).code
            }
            return AppResult(wrote: wrote, read: read, listed: listed, missingRead: missingRead, removeMissingError: removeMissingError)
        }

        func limitCapture(to count: Int) {
            DiskIOStore.shared.capacity = count
        }

        func makeCapturedCall(_ marker: String) async throws {
            _ = FileManager.default.createFile(atPath: path(marker), contents: Data(marker.utf8))
        }

        func capturedMarkers(through marker: String) async throws -> [String] {
            let markerPath = path(marker)
            for await events in DiskIOStore.shared.$events.values where events.contains(where: { $0.path == markerPath }) {
                break
            }
            return DiskIOStore.shared.events
                .filter { ($0.path as NSString).deletingLastPathComponent == directory }
                .map { ($0.path as NSString).lastPathComponent }
                .filter { !$0.hasPrefix("app-") }
        }

        func capturedCount() -> Int {
            DiskIOStore.shared.events.count
        }

        /// The drawer's own file work, run as its plugins run it: under `isDrawerWork`.
        func makeDrawerCall(_ marker: String) async throws {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                _ = FileManager.default.createFile(atPath: path(marker), contents: Data(marker.utf8))
            }
        }

        private func path(_ marker: String) -> String {
            (directory as NSString).appendingPathComponent(marker)
        }
    }

    @Suite("The Disk I/O plugin keeps the interception contract, in a child process", .timeLimit(.minutes(1)))
    struct DiskIOContractExitTests {
        @Test("Installing the Disk I/O plugin twice, or in a second drawer, changes the process as installing it once does")
        func idempotentInstall() async {
            await #expect(processExitsWith: .success) {
                try await DiskIOContract.made().checkIdempotentInstall()
            }
        }

        @Test("A file call is recorded once with the Disk I/O plugin installed twice")
        func capturesOnceInstalledTwice() async {
            await #expect(processExitsWith: .success) {
                try await DiskIOContract.made().checkCapturesOnceInstalledTwice()
            }
        }

        @Test("Removing the Disk I/O plugin from the last drawer holding it puts back what installing changed")
        func reversibleUninstall() async {
            await #expect(processExitsWith: .success) {
                try await DiskIOContract.made().checkReversibleUninstall()
            }
        }

        @Test("The Disk I/O plugin removed forgets its calls and records nothing until installed again")
        func capturesNothingUninstalled() async {
            await #expect(processExitsWith: .success) {
                try await DiskIOContract.made().checkCapturesNothingUninstalled()
            }
        }

        @Test("The app's file calls write, read, list and fail the same with the Disk I/O plugin installed as without")
        func unchangedResult() async {
            await #expect(processExitsWith: .success) {
                try await DiskIOContract.made().checkUnchangedResult()
            }
        }

        @Test("The Disk I/O list keeps at most its capacity, the newest calls")
        func boundedCapture() async {
            await #expect(processExitsWith: .success) {
                try await DiskIOContract.made().checkBoundedCapture()
            }
        }

        @Test("The drawer's own file work is never recorded")
        func leavesOutDrawerActivity() async {
            await #expect(processExitsWith: .success) {
                try await DiskIOContract.made().checkLeavesOutDrawerActivity()
            }
        }
    }
#endif

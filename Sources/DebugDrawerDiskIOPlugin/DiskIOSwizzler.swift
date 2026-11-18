#if DEBUG
    import Foundation
    import ObjectiveC

    /// Swaps the file methods the plugin records for ones that time the call, call the original
    /// and record it (``DiskIOCall``). Installed once, by `installDiskIO()`.
    ///
    /// What it reaches: `FileManager`'s path and URL methods that read, create, list, stat, copy,
    /// move and delete; `NSData`'s `write(to:)`/`write(toFile:)` methods and its
    /// `contentsOf` initializers; and `FileHandle`'s Objective-C reads and writes on regular files.
    /// Swift's `Data(contentsOf:)`, `Data.write(to:)` and `FileHandle.write(contentsOf:)` don't call
    /// any of these on current OSes, and POSIX calls go to the kernel directly, so neither is seen.
    ///
    /// The methods' parameters and results are Foundation's reference types (`NSData`, `NSArray`)
    /// rather than Swift's, so a swizzled call doesn't copy what it passes through.
    enum DiskIOSwizzler {
        static func install() {
            _ = installation
        }

        private static let installation: Void = {
            let fileManager: [(Selector, Selector)] = [
                (#selector(FileManager.contents(atPath:)), #selector(FileManager.dd_contents(atPath:))),
                (
                    #selector(FileManager.createFile(atPath:contents:attributes:)),
                    #selector(FileManager.dd_createFile(atPath:contents:attributes:))
                ),
                (
                    #selector(FileManager.createDirectory(atPath:withIntermediateDirectories:attributes:)),
                    #selector(FileManager.dd_createDirectory(atPath:withIntermediateDirectories:attributes:))
                ),
                (
                    #selector(FileManager.createDirectory(at:withIntermediateDirectories:attributes:)),
                    #selector(FileManager.dd_createDirectory(at:withIntermediateDirectories:attributes:))
                ),
                (#selector(FileManager.removeItem(atPath:)), #selector(FileManager.dd_removeItem(atPath:))),
                (#selector(FileManager.removeItem(at:)), #selector(FileManager.dd_removeItem(at:))),
                (#selector(FileManager.contentsOfDirectory(atPath:)), #selector(FileManager.dd_contentsOfDirectory(atPath:))),
                (
                    #selector(FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)),
                    #selector(FileManager.dd_contentsOfDirectory(at:includingPropertiesForKeys:options:))
                ),
                (#selector(FileManager.attributesOfItem(atPath:)), #selector(FileManager.dd_attributesOfItem(atPath:))),
                (#selector(FileManager.copyItem(atPath:toPath:)), #selector(FileManager.dd_copyItem(atPath:toPath:))),
                (#selector(FileManager.copyItem(at:to:)), #selector(FileManager.dd_copyItem(at:to:))),
                (#selector(FileManager.moveItem(atPath:toPath:)), #selector(FileManager.dd_moveItem(atPath:toPath:))),
                (#selector(FileManager.moveItem(at:to:)), #selector(FileManager.dd_moveItem(at:to:)))
            ]
            for (original, replacement) in fileManager {
                exchange(original, with: replacement, in: FileManager.self)
            }

            let data: [(Selector, Selector)] = [
                (#selector(NSData.write(toFile:atomically:)), #selector(NSData.dd_write(toFile:atomically:))),
                (#selector(NSData.write(to:atomically:)), #selector(NSData.dd_write(to:atomically:))),
                (#selector(NSData.write(toFile:options:)), #selector(NSData.dd_write(toFile:options:))),
                (#selector(NSData.write(to:options:)), #selector(NSData.dd_write(to:options:)))
            ]
            for (original, replacement) in data {
                exchange(original, with: replacement, in: NSData.self)
            }
            replaceInitializer(NSSelectorFromString("initWithContentsOfFile:"), argumentIsURL: false)
            replaceInitializer(NSSelectorFromString("initWithContentsOfURL:"), argumentIsURL: true)
            replaceThrowingInitializer(NSSelectorFromString("initWithContentsOfFile:options:error:"), argumentIsURL: false)
            replaceThrowingInitializer(NSSelectorFromString("initWithContentsOfURL:options:error:"), argumentIsURL: true)

            // `FileHandle` is a class cluster: the handles Foundation makes are a subclass that
            // implements the reads and writes itself, so they are swapped on that subclass, found
            // from a handle rather than by name.
            let handle = FileHandle(fileDescriptor: STDERR_FILENO, closeOnDealloc: false)
            let handleClass: AnyClass = object_getClass(handle) ?? FileHandle.self
            let fileHandle: [(String, Selector)] = [
                ("writeData:", #selector(FileHandle.dd_writeData(_:))),
                ("writeData:error:", #selector(FileHandle.dd_writeData(_:error:))),
                ("readDataOfLength:", #selector(FileHandle.dd_readData(ofLength:))),
                ("readDataToEndOfFile", #selector(FileHandle.dd_readDataToEndOfFile)),
                ("availableData", #selector(FileHandle.dd_availableData)),
                ("readDataToEndOfFileAndReturnError:", #selector(FileHandle.dd_readToEndOfFile(error:))),
                ("readDataUpToLength:error:", #selector(FileHandle.dd_readData(upToLength:error:)))
            ]
            for (original, replacement) in fileHandle {
                exchange(NSSelectorFromString(original), with: replacement, in: handleClass)
            }
        }()

        private static func exchange(_ original: Selector, with replacement: Selector, in cls: AnyClass) {
            guard let originalMethod = class_getInstanceMethod(cls, original),
                  let replacementMethod = class_getInstanceMethod(cls, replacement)
            else { return }
            method_exchangeImplementations(originalMethod, replacementMethod)
        }

        // The initializers are replaced with blocks over raw pointers rather than swapped with
        // Swift methods: an `init` method consumes its receiver and returns a retained object,
        // which a method outside the `init` family can't do, so the block passes both through
        // untouched.

        /// Replaces `initWithContentsOfFile:` or `initWithContentsOfURL:`.
        private static func replaceInitializer(_ selector: Selector, argumentIsURL: Bool) {
            guard let method = class_getInstanceMethod(NSData.self, selector) else { return }
            typealias Initializer = @convention(c) (UnsafeRawPointer, Selector, UnsafeRawPointer?) -> UnsafeRawPointer?
            let original = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
            let replacement: @convention(block) (UnsafeRawPointer, UnsafeRawPointer?) -> UnsafeRawPointer? = { receiver, location in
                guard let call = DiskIOCall.begin() else { return original(receiver, selector, location) }
                let result = original(receiver, selector, location)
                let path = filePath(location, isURL: argumentIsURL)
                call.end(
                    path == nil ? nil : .read, path: path ?? "", size: result.map(length) ?? 0,
                    error: result == nil ? DiskIOCall.lastError(else: .fileReadUnknown) : nil
                )
                return result
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }

        /// Replaces `initWithContentsOfFile:options:error:` or `initWithContentsOfURL:options:error:`.
        private static func replaceThrowingInitializer(_ selector: Selector, argumentIsURL: Bool) {
            guard let method = class_getInstanceMethod(NSData.self, selector) else { return }
            typealias Initializer = @convention(c) (
                UnsafeRawPointer, Selector, UnsafeRawPointer?, UInt, UnsafeMutableRawPointer?
            ) -> UnsafeRawPointer?
            let original = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
            let replacement: @convention(block) (
                UnsafeRawPointer, UnsafeRawPointer?, UInt, UnsafeMutableRawPointer?
            ) -> UnsafeRawPointer? = { receiver, location, options, error in
                guard let call = DiskIOCall.begin() else { return original(receiver, selector, location, options, error) }
                let result = original(receiver, selector, location, options, error)
                let path = filePath(location, isURL: argumentIsURL)
                // The callee stores an autoreleased error, so reading it unretained is safe here.
                let reported = result == nil
                    ? error?.load(as: UnsafeRawPointer?.self).map { Unmanaged<NSError>.fromOpaque($0).takeUnretainedValue() }
                    ?? DiskIOCall.lastError(else: .fileReadUnknown)
                    : nil
                call.end(path == nil ? nil : .read, path: path ?? "", size: result.map(length) ?? 0, error: reported)
                return result
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }

        /// The path an initializer's argument names, or `nil` for a URL that isn't a file's.
        private static func filePath(_ location: UnsafeRawPointer?, isURL: Bool) -> String? {
            guard let location else { return nil }
            if isURL {
                let url = Unmanaged<NSURL>.fromOpaque(location).takeUnretainedValue()
                return url.isFileURL ? url.path : nil
            }
            return Unmanaged<NSString>.fromOpaque(location).takeUnretainedValue() as String
        }

        private static func length(_ data: UnsafeRawPointer) -> Int64 {
            Int64(Unmanaged<NSData>.fromOpaque(data).takeUnretainedValue().length)
        }
    }
#endif

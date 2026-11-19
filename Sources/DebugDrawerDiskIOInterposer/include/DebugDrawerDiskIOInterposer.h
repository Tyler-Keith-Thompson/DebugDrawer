// The Disk I/O plugin's opt-in interposer: dyld interposing tuples for read, write, pread and
// pwrite, which see the file calls Swift's Foundation makes without reaching a method the plugin
// can swizzle (`Data.write(to:)`, `Data(contentsOf:)`, `FileHandle.write(contentsOf:)`).
//
// The app links this library only to opt in. The plugin never imports it: it finds
// `DebugDrawerDiskIOInterposerStart` with `dlsym` when `unsafeInstallDiskIOInterposing()` runs, so
// an app that doesn't link the library builds and behaves exactly as before. Debug builds only:
// in release the library holds nothing.

#ifndef DEBUGDRAWER_DISK_IO_INTERPOSER_H
#define DEBUGDRAWER_DISK_IO_INTERPOSER_H

#if DEBUG
    #include <stdbool.h>
    #include <stdint.h>

    /// Receives one call to a regular file that moved bytes or failed, on the thread that made it.
    ///
    /// - Parameters:
    ///   - isWrite: Whether the call wrote (`write`, `pwrite`) rather than read (`read`, `pread`).
    ///   - path: The file's path, valid only for the length of the call.
    ///   - bytes: The bytes the call moved; 0 when it failed.
    ///   - nanoseconds: How long the call took.
    ///   - isMainThread: Whether the main thread made the call.
    ///   - error: The call's `errno` when it failed; 0 when it succeeded.
    typedef void (*DebugDrawerDiskIOInterposerHandler)(
        bool isWrite, const char *path, int64_t bytes, uint64_t nanoseconds, bool isMainThread, int error
    );

    /// Hands every later call to a regular file to `handler`, except calls `handler` itself makes.
    ///
    /// Until it is called, the interposed functions call the system's straight through. A second
    /// call replaces the handler.
    ///
    /// - Returns: Whether dyld applied the interposing tuples, so the calls reach `handler`. It
    ///   doesn't when the library was loaded after launch (`dlopen`) or the process is restricted.
    bool DebugDrawerDiskIOInterposerStart(DebugDrawerDiskIOInterposerHandler handler);

    /// Hands no more calls to the handler: the interposed functions call the system's straight
    /// through again, as before `DebugDrawerDiskIOInterposerStart`. dyld's interposing, applied at
    /// launch, stays. A later `DebugDrawerDiskIOInterposerStart` hands calls to its handler again.
    void DebugDrawerDiskIOInterposerStop(void);
#endif

#endif

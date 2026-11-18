// dyld interposing: each `__DATA,__interpose` tuple below makes dyld bind every other image's
// calls to the system function (Foundation's in the shared cache included) to the replacement
// beside it. Undocumented dyld behaviour, which Apple may change, and applied only to images
// loaded at launch, which is why this is a dynamic library of its own that the app links.
//
// Only read, write, pread and pwrite are interposed: they are the calls that move a file's bytes,
// and Swift's Foundation reads and writes files through read and write. open and close carry
// nothing the plugin records, and each interposed function is one more the process depends on
// this behaviour for. Calls within this file reach the system's functions, as dyld doesn't
// interpose an image's own calls.

#include "DebugDrawerDiskIOInterposer.h"

#if DEBUG
    #include <dlfcn.h>
    #include <errno.h>
    #include <fcntl.h>
    #include <pthread.h>
    #include <stdatomic.h>
    #include <sys/param.h>
    #include <sys/stat.h>
    #include <time.h>
    #include <unistd.h>

    #if defined(__LLVM_INSTR_PROFILE_GENERATE)
        // Built for code coverage, clang makes this image reference the profile runtime through
        // __llvm_profile_runtime unless the image defines that symbol itself, and Xcode links a
        // package's dynamic library without the runtime. On the iOS simulator -dead_strip drops the
        // reference; for Mac Catalyst and macOS nothing does, so the link fails. Defining it opts
        // this image out of writing a profile, which suits it: the hooks run on every read and
        // write in the process, the profile runtime's own included.
        int __llvm_profile_runtime = 0;
    #endif

    // NULL until DebugDrawerDiskIOInterposerStart: every hook then calls straight through.
    static _Atomic(DebugDrawerDiskIOInterposerHandler) handler = NULL;

    // Marks a thread inside a recorded call, so whatever the handler does that reads or writes a
    // file (the system logging, say) calls straight through rather than being recorded in turn. A
    // pthread key rather than `_Thread_local`: reading one never allocates, and a key works on a
    // thread that is exiting, when thread-local storage may already be gone.
    static pthread_key_t inRecordedCall;
    static pthread_once_t inRecordedCallOnce = PTHREAD_ONCE_INIT;

    static void makeInRecordedCall(void) {
        pthread_key_create(&inRecordedCall, NULL);
    }

    /// The handler, when the call should be recorded: started, and not inside a recorded call.
    static DebugDrawerDiskIOInterposerHandler beginCall(void) {
        DebugDrawerDiskIOInterposerHandler current = atomic_load_explicit(&handler, memory_order_acquire);
        if (current == NULL || pthread_getspecific(inRecordedCall) != NULL) return NULL;
        // Any non-NULL value marks the thread; nothing reads it back.
        pthread_setspecific(inRecordedCall, (const void *)1);
        return current;
    }

    /// Hands a finished call to `current` if it moved bytes of a regular file or failed on one, then
    /// restores the caller's `errno`. A pipe, a socket or a terminal isn't the disk.
    static void endCall(
        DebugDrawerDiskIOInterposerHandler current, bool isWrite, int descriptor, ssize_t result, int error, uint64_t start
    ) {
        uint64_t nanoseconds = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start;
        // 0 moved nothing: the end of a file, or a write of no bytes.
        if (result != 0) {
            struct stat status;
            char path[MAXPATHLEN];
            if (fstat(descriptor, &status) == 0 && S_ISREG(status.st_mode) && fcntl(descriptor, F_GETPATH, path) != -1) {
                current(isWrite, path, result > 0 ? result : 0, nanoseconds, pthread_main_np() == 1, result < 0 ? error : 0);
            }
        }
        pthread_setspecific(inRecordedCall, NULL);
        errno = error;
    }

    static ssize_t interposedRead(int descriptor, void *buffer, size_t count) {
        DebugDrawerDiskIOInterposerHandler current = beginCall();
        if (current == NULL) return read(descriptor, buffer, count);
        uint64_t start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        ssize_t result = read(descriptor, buffer, count);
        endCall(current, false, descriptor, result, errno, start);
        return result;
    }

    static ssize_t interposedWrite(int descriptor, const void *buffer, size_t count) {
        DebugDrawerDiskIOInterposerHandler current = beginCall();
        if (current == NULL) return write(descriptor, buffer, count);
        uint64_t start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        ssize_t result = write(descriptor, buffer, count);
        endCall(current, true, descriptor, result, errno, start);
        return result;
    }

    static ssize_t interposedPread(int descriptor, void *buffer, size_t count, off_t offset) {
        DebugDrawerDiskIOInterposerHandler current = beginCall();
        if (current == NULL) return pread(descriptor, buffer, count, offset);
        uint64_t start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        ssize_t result = pread(descriptor, buffer, count, offset);
        endCall(current, false, descriptor, result, errno, start);
        return result;
    }

    static ssize_t interposedPwrite(int descriptor, const void *buffer, size_t count, off_t offset) {
        DebugDrawerDiskIOInterposerHandler current = beginCall();
        if (current == NULL) return pwrite(descriptor, buffer, count, offset);
        uint64_t start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        ssize_t result = pwrite(descriptor, buffer, count, offset);
        endCall(current, true, descriptor, result, errno, start);
        return result;
    }

    bool DebugDrawerDiskIOInterposerStart(DebugDrawerDiskIOInterposerHandler newHandler) {
        pthread_once(&inRecordedCallOnce, makeInRecordedCall);
        // Released after the key exists, so a hook that sees the handler sees the key too.
        atomic_store_explicit(&handler, newHandler, memory_order_release);
        // dlsym answers with the replacement exactly when dyld applied the tuples.
        return dlsym(RTLD_DEFAULT, "write") == (void *)interposedWrite;
    }

    // dyld's tuple: the replacement, then the function it replaces.
    #define DEBUGDRAWER_INTERPOSE(replacement, replaced) \
        __attribute__((used)) static struct { const void *replacement; const void *replaced; } \
        interpose_##replaced __attribute__((section("__DATA,__interpose"))) = { \
            (const void *)&replacement, (const void *)&replaced \
        };

    DEBUGDRAWER_INTERPOSE(interposedRead, read)
    DEBUGDRAWER_INTERPOSE(interposedWrite, write)
    DEBUGDRAWER_INTERPOSE(interposedPread, pread)
    DEBUGDRAWER_INTERPOSE(interposedPwrite, pwrite)
#endif

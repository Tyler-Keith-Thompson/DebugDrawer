#if DEBUG
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct StackSamplerTests {
        @Test("Sampling a thread blocked on a semaphore gives its frames, from the kernel's wait out to the thread's start")
        func blockedThread() throws {
            let ready = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var sampler: MachThreadStackSampler?
            let thread = Thread {
                sampler = .currentThread()
                ready.signal()
                _ = release.wait(timeout: .now() + 30)
                done.signal()
            }
            thread.start()
            ready.wait()
            let frames = UnsafeMutableBufferPointer<UInt>.allocate(capacity: 128)
            defer { frames.deallocate() }

            let count = try #require(sampler).sample(into: frames)
            release.signal()
            done.wait()
            let actual = Symbolicator.lines(for: Array(frames.prefix(count)))

            #expect(count > 3)
            #expect(actual.first?.contains("semaphore") == true || actual.first?.contains("ulock") == true)
            #expect(actual.contains { $0.contains("dispatch_semaphore_wait") || $0.contains("DispatchSemaphore") })
            #expect(actual.contains { $0.contains("_pthread_start") || $0.contains("thread_start") })
        }

        @Test("A buffer of one frame holds the thread's instruction alone")
        func oneFrame() throws {
            let ready = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var sampler: MachThreadStackSampler?
            let thread = Thread {
                sampler = .currentThread()
                ready.signal()
                _ = release.wait(timeout: .now() + 30)
                done.signal()
            }
            thread.start()
            ready.wait()
            let frames = UnsafeMutableBufferPointer<UInt>.allocate(capacity: 1)
            defer { frames.deallocate() }

            let actual = try #require(sampler).sample(into: frames)
            release.signal()
            done.wait()

            #expect(actual == 1)
            #expect(frames[0] != 0)
        }

        @Test("An empty buffer samples nothing")
        func emptyBuffer() {
            let sut = MachThreadStackSampler.currentThread()
            let frames = UnsafeMutableBufferPointer<UInt>(start: nil, count: 0)

            let actual = sut.sample(into: frames)

            #expect(actual == 0)
        }
    }
#endif

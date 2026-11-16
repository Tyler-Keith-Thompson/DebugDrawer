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
            let sut = try #require(sampler)
            // `ready` fires before the helper reaches its wait, so it may still be on its way into
            // it. Ask the kernel until it reports the helper parked: an event, not a delay.
            func isParked() -> Bool {
                var info = thread_basic_info()
                var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
                let result = withUnsafeMutablePointer(to: &info) { pointer in
                    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        thread_info(sut.thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                    }
                }
                return result == KERN_SUCCESS && info.run_state == TH_STATE_WAITING
            }
            while !isParked() {
                sched_yield()
            }
            let frames = UnsafeMutableBufferPointer<UInt>.allocate(capacity: 128)
            defer { frames.deallocate() }

            let count = sut.sample(into: frames)
            release.signal()
            done.wait()
            let actual = Symbolicator.lines(for: Array(frames.prefix(count)))

            #expect(count > 3)
            #expect(actual.prefix(3).contains { $0.contains("semaphore") || $0.contains("ulock") })
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

#if DEBUG
    import Darwin
    @testable import DebugDrawerPerformancePlugin
    import Foundation
    import Testing

    // Each test runs its sampling on a thread of its own, which reports back through a
    // continuation: the test waits for that event rather than for time to pass.
    @Suite("Performance thread sampling", .timeLimit(.minutes(1)))
    struct MachThreadSamplerTests {
        @Test("A busy thread named dd54-busy reaches the top of the list, by its name, with its CPU above zero")
        func busyThreadRanksFirst() async throws {
            let name = "dd54-busy"
            let sampler = MachThreadSampler(mainThreadID: 0)

            // The thread is busy sampling: it samples until it finds itself first, which it does
            // once the CPU it has used outweighs every other thread's. Waiting for that, rather
            // than asserting on one sample, keeps the test from failing when another test's
            // thread (SwiftPM runs every suite in one process) is briefly busier. A list that is
            // unsorted, sorted the wrong way or missing names never puts it first, and the time
            // limit fails the test. The cap ends the thread if it never does.
            let actual: [ThreadCPU] = await withCheckedContinuation { continuation in
                let thread = Thread {
                    var latest: [ThreadCPU] = []
                    for _ in 0 ..< 2_000_000 {
                        latest = sampler.sample()
                        if let first = latest.first, first.name == name, first.cpuUsage > 0 { break }
                    }
                    continuation.resume(returning: latest)
                }
                thread.name = name
                thread.start()
            }

            let busiest = try #require(actual.first)
            #expect(busiest.name == name)
            #expect(busiest.cpuUsage > 0)
            #expect(actual == ThreadCPU.ranked(actual))
        }

        @Test("An unnamed thread is listed by its ID, the one pthread_threadid_np reports")
        func unnamedThreadIsListedByID() async throws {
            let sampler = MachThreadSampler(mainThreadID: 0)

            let observed: (id: UInt64, sample: [ThreadCPU]) = await withCheckedContinuation { continuation in
                Thread {
                    let id = MachThreadSampler.currentThreadID()
                    continuation.resume(returning: (id, sampler.sample()))
                }.start()
            }
            let expected = "Thread 0x\(String(observed.id, radix: 16))"

            let actual = try #require(observed.sample.first { $0.threadID == observed.id })

            #expect(actual.name == expected)
        }

        @Test("The thread the sampler knows as the main thread is Main Thread when it has no name")
        func mainThreadIsNamed() async throws {
            let observed: (id: UInt64, sample: [ThreadCPU]) = await withCheckedContinuation { continuation in
                Thread {
                    let id = MachThreadSampler.currentThreadID()
                    continuation.resume(returning: (id, MachThreadSampler(mainThreadID: id).sample()))
                }.start()
            }

            let actual = try #require(observed.sample.first { $0.threadID == observed.id })

            #expect(actual.name == "Main Thread")
        }

        @Test("Every thread is listed once, by its own ID")
        func threadsAreUnique() {
            let sut = MachThreadSampler(mainThreadID: MachThreadSampler.currentThreadID())

            let actual = sut.sample()

            #expect(!actual.isEmpty)
            #expect(Set(actual.map(\.threadID)).count == actual.count)
        }
    }
#endif

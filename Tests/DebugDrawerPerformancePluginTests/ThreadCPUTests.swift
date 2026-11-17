#if DEBUG
    @testable import DebugDrawerPerformancePlugin
    import Testing

    @Suite("Thread CPU names and ranking")
    struct ThreadCPUTests {
        @Test("A thread with a pthread name is shown by that name, even the main thread")
        func pthreadName() {
            let expected = "com.example.worker"

            let actual = ThreadCPU.name(pthreadName: expected, threadID: 0x1A2B, isMainThread: true)

            #expect(actual == expected)
        }

        @Test("An unnamed main thread is Main Thread")
        func unnamedMainThread() {
            let expected = "Main Thread"

            let actual = ThreadCPU.name(pthreadName: "", threadID: 0x1A2B, isMainThread: true)

            #expect(actual == expected)
        }

        @Test("An unnamed thread, or one with no pthread, is named by its ID in hexadecimal")
        func unnamedThread() {
            let expected = "Thread 0x1a2b"

            let empty = ThreadCPU.name(pthreadName: "", threadID: 0x1A2B, isMainThread: false)
            let noPthread = ThreadCPU.name(pthreadName: nil, threadID: 0x1A2B, isMainThread: false)

            #expect(empty == expected)
            #expect(noPthread == expected)
        }

        @Test("Ranking puts the busiest first, then breaks ties by name and then by ID")
        func ranking() {
            let threads = [
                ThreadCPU(name: "b", threadID: 4, cpuUsage: 0),
                ThreadCPU(name: "a", threadID: 3, cpuUsage: 0.25),
                ThreadCPU(name: "worker", threadID: 2, cpuUsage: 0.9),
                ThreadCPU(name: "a", threadID: 1, cpuUsage: 0.25),
                ThreadCPU(name: "a", threadID: 5, cpuUsage: 0)
            ]
            let expected: [UInt64] = [2, 1, 3, 5, 4]

            let actual = ThreadCPU.ranked(threads).map(\.threadID)

            #expect(actual == expected)
        }

        @Test("Ranking no threads gives none, and one thread gives it alone")
        func rankingEdges() {
            let one = ThreadCPU(name: "only", threadID: 1, cpuUsage: 1)

            let none = ThreadCPU.ranked([])
            let single = ThreadCPU.ranked([one])

            #expect(none.isEmpty)
            #expect(single == [one])
        }
    }
#endif

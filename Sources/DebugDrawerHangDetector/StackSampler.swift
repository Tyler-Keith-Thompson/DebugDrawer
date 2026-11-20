import Darwin

/// Captures the return addresses on one thread's stack while it runs: the seam over the
/// system calls that stop a thread and read its registers, so tests can stand in for it.
package protocol StackSampler: Sendable {
    /// Writes the thread's current instruction, then the return address of each frame,
    /// innermost first, into `frames`; returns how many it wrote.
    ///
    /// Called on the watcher thread, holding the monitor's lock, so it must not allocate or
    /// take a lock of its own: the sampled thread may be stopped holding one.
    func sample(into frames: UnsafeMutableBufferPointer<UInt>) -> Int
}

/// Samples a thread by stopping it: `thread_suspend`, its registers through
/// `thread_get_state`, a walk of its frame records, then `thread_resume`.
///
/// Stopping another thread is safe only while the sampler touches nothing that thread could
/// hold a lock on: between suspend and resume it reads registers and stack memory into a
/// buffer allocated in advance, and calls nothing that allocates, logs or takes a lock (the
/// allocator's, dyld's, the Objective-C or Swift runtime's). The addresses are named later,
/// with `dladdr`, once the thread runs again.
package struct MachThreadStackSampler: StackSampler {
    /// The thread's Mach port, as `pthread_mach_thread_np` names it. The port stays valid
    /// while the thread lives; the app's main thread lives as long as the app.
    package let thread: thread_act_t
    /// The highest address of the thread's stack, where its first frame is.
    package let stackTop: UInt
    /// The lowest address the stack may grow to.
    package let stackBottom: UInt

    /// A sampler of the calling thread, to be called from another.
    package static func currentThread() -> MachThreadStackSampler {
        let thread = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        return MachThreadStackSampler(
            thread: pthread_mach_thread_np(thread),
            stackTop: top,
            stackBottom: top &- UInt(pthread_get_stacksize_np(thread))
        )
    }

    package func sample(into frames: UnsafeMutableBufferPointer<UInt>) -> Int {
        guard !frames.isEmpty, thread_suspend(thread) == KERN_SUCCESS else { return 0 }
        defer { thread_resume(thread) }
        guard let registers = readRegisters() else { return 0 }
        return walk(from: registers, into: frames)
    }

    /// The thread's instruction, link register (arm64 only) and frame pointer, or `nil` when
    /// the kernel won't say.
    private func readRegisters() -> Registers? {
        #if arch(arm64)
            var state = arm_thread_state64_t()
            var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &state) { pointer in
                pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                    thread_get_state(thread, ARM_THREAD_STATE64, $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return nil }
            return Registers(instruction: UInt(state.__pc), link: UInt(state.__lr), framePointer: UInt(state.__fp))
        #elseif arch(x86_64)
            var state = x86_thread_state64_t()
            var count = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &state) { pointer in
                pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                    thread_get_state(thread, x86_THREAD_STATE64, $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return nil }
            return Registers(instruction: UInt(state.__rip), link: nil, framePointer: UInt(state.__rbp))
        #else
            return nil
        #endif
    }

    /// The instruction, the link register unless the first frame record repeats it, then the
    /// return address of each frame record; how many it wrote.
    ///
    /// Written after the crash plugin's walk of a crashed thread (DebugDrawerCrashReportsPlugin's
    /// CrashCapture), copied rather than shared, as plugins don't depend on each other. It
    /// stops at a frame pointer outside the thread's stack, one that doesn't move outward, or
    /// a zero return address, so a stack caught mid-change ends the walk instead of faulting.
    private func walk(from registers: Registers, into frames: UnsafeMutableBufferPointer<UInt>) -> Int {
        // Return addresses saved by arm64e code (the system's libraries) carry a pointer
        // authentication code in their high bits; user addresses fit in the low 47.
        let addressMask: UInt = 0x0000_7FFF_FFFF_FFFF
        let recordSize = UInt(2 * MemoryLayout<UInt>.size)
        frames[0] = registers.instruction & addressMask
        var count = 1
        var framePointer = registers.framePointer
        var isFirstRecord = true
        while count < frames.count,
              framePointer >= stackBottom, framePointer <= stackTop &- recordSize,
              framePointer % UInt(MemoryLayout<UInt>.alignment) == 0,
              let record = UnsafePointer<UInt>(bitPattern: framePointer) {
            let returnAddress = record[1] & addressMask
            guard returnAddress != 0 else { break }
            // A leaf function that saved no frame record (a system call's trap) leaves its
            // caller only in the link register, ahead of the first record's return address.
            if isFirstRecord, let link = registers.link.map({ $0 & addressMask }), link != 0, link != returnAddress,
               count < frames.count - 1 {
                frames[count] = link
                count += 1
            }
            isFirstRecord = false
            frames[count] = returnAddress
            count += 1
            let next = record[0]
            guard next > framePointer else { break }
            framePointer = next
        }
        return count
    }
}

/// The registers a walk starts from.
private struct Registers {
    let instruction: UInt
    let link: UInt?
    let framePointer: UInt
}

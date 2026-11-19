#if DEBUG
    import Foundation

    /// This process, from `kinfo_proc`, `task_info` and `ProcessInfo`.
    struct _ProcessMetricsSource: ProcessMetricsSource {
        /// Where the footprint comes from: the kernel's `task_vm_info` by default.
        let memory: any TaskVMInfoSource

        init(memory: any TaskVMInfoSource = _TaskVMInfoSource()) {
            self.memory = memory
        }

        func start() -> ProcessStart? {
            ProcessStart.current()
        }

        func footprintMB() -> Double {
            MemoryFootprint.currentMB(from: memory)
        }

        var processIdentifier: Int32 {
            ProcessInfo.processInfo.processIdentifier
        }

        var argumentCount: Int {
            ProcessInfo.processInfo.arguments.count
        }
    }
#endif

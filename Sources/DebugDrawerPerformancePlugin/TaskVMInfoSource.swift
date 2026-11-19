#if DEBUG
    import Darwin

    /// Where the process's `task_vm_info` comes from: the kernel's `task_info(TASK_VM_INFO)`.
    /// Tests pass a fixed reading instead.
    protocol TaskVMInfoSource {
        /// The process's virtual memory information now, or `nil` when the kernel won't report it.
        func taskVMInfo() -> task_vm_info_data_t?
    }
#endif

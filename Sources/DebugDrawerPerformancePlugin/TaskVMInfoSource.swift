#if DEBUG
    import Darwin

    /// Where the process's `task_vm_info` comes from: the kernel's `task_info(TASK_VM_INFO)`.
    protocol TaskVMInfoSource {
        /// The process's virtual memory information now, or `nil` when the kernel won't report it.
        func taskVMInfo() -> task_vm_info_data_t?
    }

    // The same few lines live in each plugin that shows memory: plugins share no helper target.
    /// The real reading: `task_info(mach_task_self_, TASK_VM_INFO)`.
    struct _TaskVMInfoSource: TaskVMInfoSource {
        func taskVMInfo() -> task_vm_info_data_t? {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? info : nil
        }
    }
#endif

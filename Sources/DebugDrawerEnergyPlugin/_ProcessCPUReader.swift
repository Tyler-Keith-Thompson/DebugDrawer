#if DEBUG
    import Foundation

    /// This process's CPU use from the kernel's thread list, against the cores `ProcessInfo`
    /// reports active.
    @MainActor
    final class _ProcessCPUReader: ProcessCPUReader {
        var processorCount: Int {
            ProcessInfo.processInfo.activeProcessorCount
        }

        func cpuUsage() -> Double {
            EnergyMonitor.processCPUUsage()
        }
    }
#endif

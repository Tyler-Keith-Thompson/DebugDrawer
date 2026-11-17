// ViewInspector is linked on Apple platforms only; the memory warning's view tests run on iOS.
#if os(macOS) || os(iOS)
    @testable import DebugDrawerPerformancePlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif

// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerScreenshotPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif

// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerDesignOverlayPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif

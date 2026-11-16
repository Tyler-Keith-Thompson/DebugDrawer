// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif

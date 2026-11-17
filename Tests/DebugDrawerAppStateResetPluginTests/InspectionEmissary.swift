// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerAppStateResetPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif

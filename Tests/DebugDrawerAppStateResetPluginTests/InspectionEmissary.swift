// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif

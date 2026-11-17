// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerUserDefaultsPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif

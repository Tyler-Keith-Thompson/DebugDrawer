// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerLocalizationPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif

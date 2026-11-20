#if DEBUG
    /// Names a mangled Swift symbol as Xcode shows it ("Example.crash() -> ()" for
    /// "$s7Example5crashyyF").
    ///
    /// The Crash Reports plugin has a copy of its own: the plugins are vertical, and a few lines
    /// cost less than a shared module.
    package protocol SymbolDemangler: Sendable {
        /// The readable name of `symbol`, or `nil` when it isn't a mangled Swift symbol or there
        /// is no demangler to ask.
        func demangle(_ symbol: String) -> String?
    }
#endif

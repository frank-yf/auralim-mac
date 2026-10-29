/// This is a compiler flag, not a preference or a runtime environment variable.
enum BuildFeatures {
    #if AURALIM_DEBUG_TOOLS
    static let debugToolsEnabled = true
    #else
    static let debugToolsEnabled = false
    #endif
}

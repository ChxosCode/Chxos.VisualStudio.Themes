// Default fixture builds stay clean. Define THEME_AUDIT_DIAGNOSTICS in a disposable
// runtime fixture copy to display predictable compiler warnings and inline errors.
#if THEME_AUDIT_DIAGNOSTICS
#warning Theme audit: inspect inline warning text and its actual underlay.
internal static class DiagnosticScenarios
{
    internal static int SyntaxError() => ;
}
#endif

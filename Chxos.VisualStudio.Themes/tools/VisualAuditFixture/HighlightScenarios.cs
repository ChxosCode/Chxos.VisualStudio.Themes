namespace VisualAuditFixture;

// Place the caret in either "family" occurrence below: definition/reference.
// Then select a word, move focus away, Find "family", and use Peek Definition.
public static class HighlightScenarios
{
    public static IReadOnlyDictionary<string, string> Index(IEnumerable<string> families)
    {
        return families.ToDictionary(family => family, StringComparer.Ordinal);
    }
}

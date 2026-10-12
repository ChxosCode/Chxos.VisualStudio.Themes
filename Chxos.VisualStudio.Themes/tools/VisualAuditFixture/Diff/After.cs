// Open Before.cs and After.cs with Visual Studio's /Diff command.
// Check line fills, word borders, syntax, and the large empty alignment region.
namespace ThemeDiff;

public static class Gallery
{
    public static string Describe(string family, int count)
    {
        var title = "Current family";
        return $"{title}: {family} ({count + 1})";
    }

    // Added lines retain their syntax colors on a subdued green fill.
    public static IReadOnlyDictionary<string, int> Count(IEnumerable<string> families)
    {
        return families
            .GroupBy(family => family)
            .ToDictionary(group => group.Key, group => group.Count());
    }
}

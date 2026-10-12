// Open Before.cs and After.cs with Visual Studio's /Diff command.
// Check line fills, word borders, syntax, and the large empty alignment region.
namespace ThemeDiff;

public static class Gallery
{
    public static string Describe(string family, int count)
    {
        var title = "Old family";
        return $"{title}: {family} ({count})";
    }
}

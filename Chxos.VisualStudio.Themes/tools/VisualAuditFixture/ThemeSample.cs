namespace VisualAuditFixture;

public enum AuditState
{
    Ready,
    Selected,
    Inactive
}

public readonly record struct AuditMeasurement(int Count, double ContrastRatio);

/// <summary>Deterministic syntax and diagnostic fixture for theme screenshots.</summary>
public sealed class ClassificationSample(string name)
{
    private const int MaximumCount = 7;
    private const double MinimumContrast = 4.5;

    public string Name { get; } = name;

    public bool TryDescribe(int count, out string description)
    {
        description = count switch
        {
            < 0 => "invalid",
            0 => "empty",
            <= MaximumCount => $"{Name}: {count}",
            _ => "overflow"
        };

        return count >= 0;
    }

    public AuditMeasurement Measure(AuditState state)
    {
        // Keep numbers, types, methods, strings, and comments visible together.
        var adjustedCount = state == AuditState.Inactive ? MaximumCount - 1 : MaximumCount;
        return new AuditMeasurement(adjustedCount, MinimumContrast);
    }
}

/// <summary>Exercises field, parameter, local, property, and method classifications.</summary>
public sealed class AssignmentSample
{
    private readonly string configuration;
    private readonly string module;
    private string committed;

    public AssignmentSample(string configuration, string module)
    {
        this.configuration = configuration;
        this.module = module;
        committed = configuration.Trim();
        Current = committed;
    }

    public string Current { get; private set; }

    public string Reassign(string input)
    {
        var normalized = input.Trim();
        committed = normalized;
        Current = committed;
        return configuration + module + committed;
    }
}

/// <summary>Dense semantic lanes for normal, selected, and highlighted captures.</summary>
public sealed class SemanticSyntaxSample<TValue>
    where TValue : notnull
{
    private const int RetryLimit = 3;
    private readonly Dictionary<string, TValue> values = new(StringComparer.Ordinal);
    private readonly TValue initialValue;

    public SemanticSyntaxSample(TValue initialValue)
    {
        this.initialValue = initialValue;
        Current = initialValue;
    }

    public TValue Current { get; private set; }

    public bool TryCommit(string key, TValue candidate, out TValue committed)
    {
        // Types, methods, fields, properties, locals, parameters, numbers,
        // strings, punctuation, and operators intentionally share each line.
        var normalizedKey = key.Trim();
        var attempts = RetryLimit + values.Count;
        committed = attempts > 0 ? candidate : initialValue;
        values[normalizedKey] = committed;
        Current = committed;
        return values.TryGetValue(normalizedKey, out committed!);
    }
}

/// <summary>
/// Supplies enough deliberately long type names to make Class View expose both
/// scrollbar axes in deterministic visual-audit captures.
/// </summary>
public static class DenseClassViewFixture
{
    public sealed class BackgroundHighlightContrastMeasurementCoordinator { }
    public sealed class CurrentLineDiscoverabilityMeasurementCoordinator { }
    public sealed class FindHighlightSyntaxPreservationMeasurementCoordinator { }
    public sealed class ReferenceHighlightSyntaxPreservationMeasurementCoordinator { }
    public sealed class ActiveSelectionDiscoverabilityMeasurementCoordinator { }
    public sealed class InactiveSelectionReadabilityMeasurementCoordinator { }
    public sealed class ScrollbarRestingThumbVisibilityMeasurementCoordinator { }
    public sealed class ScrollbarHoveredThumbVisibilityMeasurementCoordinator { }
    public sealed class ScrollbarPressedThumbVisibilityMeasurementCoordinator { }
    public sealed class ScrollbarArrowGlyphVisibilityMeasurementCoordinator { }
    public sealed class SolutionTitleRestingSurfaceMeasurementCoordinator { }
    public sealed class SolutionTitleHoveredSurfaceMeasurementCoordinator { }
    public sealed class SolutionTitleFocusedSurfaceMeasurementCoordinator { }
    public sealed class SolutionTitleInactiveSurfaceMeasurementCoordinator { }
    public sealed class RazorHighlightClassificationMeasurementCoordinator { }
    public sealed class CssHighlightClassificationMeasurementCoordinator { }
    public sealed class HtmlHighlightClassificationMeasurementCoordinator { }
    public sealed class EditorScalingAndAccessibilityMeasurementCoordinator { }
}

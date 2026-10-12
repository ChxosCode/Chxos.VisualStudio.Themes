using Microsoft.AspNetCore.Components;
using Microsoft.JSInterop;

namespace VisualAuditFixture.Semantics;

public interface IReview { Task RefreshAsync(); }
public enum ReviewState { Pending, Complete }
public readonly record struct ReviewPoint(int X, int Y);
public record ReviewItem(string Name);
public delegate Task ReviewCallback(ElementReference element);

/// <summary>Review declaration and use sites, including inherited record colors.</summary>
public sealed class EditorSemantics<TItem> where TItem : class
{
    private ElementReference shell = default;
    private IJSObjectReference? module;
    private Task? initialization;
    public TItem? Current { get; set; }
    public event EventHandler? Changed;

    public async Task RefreshAsync(IJSRuntime runtime, bool enabled)
    {
        if (!enabled) return;
        module = await runtime.InvokeAsync<IJSObjectReference>("import", "./review.js");
        initialization = module.InvokeVoidAsync("refresh", shell).AsTask();
        await initialization;
        var point = new ReviewPoint(2, 3);
        var item = new ReviewItem("sample");
        ReviewState state = ReviewState.Pending;
        IReview? review = null;
        ReviewCallback callback = async element =>
        {
            if (element.Id is null) return;
            await Task.Yield();
        };
        foreach (var value in new[] { point.X, point.Y })
        {
            if (value < 0) continue;
            else if (value == 0) break;
            state = ReviewState.Complete;
        }
        switch (state)
        {
            case ReviewState.Complete: Changed?.Invoke(this, EventArgs.Empty); break;
            default: await callback(shell); break;
        }
        try { if (review is not null) await review.RefreshAsync(); }
        catch (InvalidOperationException) { throw; }
        finally { GC.KeepAlive(item); }
    }
}

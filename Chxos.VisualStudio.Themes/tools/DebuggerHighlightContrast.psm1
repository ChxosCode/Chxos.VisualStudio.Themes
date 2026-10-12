Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'PriorityThemeRefinements.psm1')
Import-Module (Join-Path $PSScriptRoot 'ContextualContrast.psm1')

function Get-DebuggerHighlightRoles {
    foreach ($kind in @('Enabled','Error','Warning')) {
        foreach ($prefix in @('Breakpoint','Breakpoint - Advanced','Breakpoint - Mapped','Breakpoint - Temporary','Breakpoint - Dependent')) {
            "$prefix ($kind)"
        }
    }
    'Current Statement'; 'Current Statement (new context)'; 'Current Statement (historical mode)'
}

function Test-DebuggerHighlightContrast {
    param([xml]$Theme,[Collections.IDictionary]$Policy)
    # Source regression screening, not confirmation of a particular marker painter.
    # Check both explicit marker foreground and preserved syntax; never depend on
    # source alpha surviving Fonts and Colors' RGB conversion.
    $parts=@{}
    foreach ($category in $Theme.Themes.Theme.Category) {
        foreach ($color in $category.Color) {
            foreach ($part in $color.ChildNodes | Where-Object NodeType -eq Element) {
                $parts[(@($category.Name,$color.Name,$part.LocalName) -join [char]31)]=$part
            }
        }
    }
    function Part([string]$Category,[string]$Role,[string]$Component) { $parts[(@($Category,$Role,$Component) -join [char]31)] }
    function Opaque($Part) {
        if ($null -eq $Part -or $Part.Type -cne 'CT_RAW' -or $Part.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Requires opaque CT_RAW; automatic, inherited, and translucent values are not interchangeable.' }
        [string]$Part.Source
    }
    # Preserve this consumer's original 69-role screening matrix. Normal-selection
    # additions do not establish new debugger rendering/enforcement semantics.
    $debuggerPolicy=@{};foreach ($key in $Policy.Keys) { $debuggerPolicy[$key]=$Policy[$key] }
    $debuggerPolicy.Remove('EditorSelectionModel')
    $roles=@(Get-PrioritySelectionRoles $debuggerPolicy)+@(
        [pscustomobject]@{Category='Text Editor MEF Items';Role='HTML Operator';Resolution='opaque-raw'},
        [pscustomobject]@{Category='Text Editor MEF Items';Role='HTML Tag Delimiter';Resolution='opaque-raw'}
    )
    $syntaxByBackground=@{}
    foreach ($role in Get-DebuggerHighlightRoles) {
        $row=[ordered]@{Theme=[string]$Theme.Themes.Theme.Name;Category='Text Editor MEF Items';Role=$role;Status='unresolved';Background=$null;Foreground=$null;ForegroundContrast=$null;SurfaceContrast=$null;MinimumSyntaxContrast=$null;SyntaxMeasurements=@();Detail='';EvidenceAssessment='unresolved';RuntimeAcceptance='pending'}
        try {
            $base=Opaque (Part 'Text Editor Text Manager Items' 'Plain Text' 'Background')
            $row.Background=Opaque (Part 'Text Editor MEF Items' $role 'Background')
            $row.Foreground=Opaque (Part 'Text Editor MEF Items' $role 'Foreground')
            $row.SurfaceContrast=Get-ContextualContrast $row.Background @($base)
            $row.ForegroundContrast=Get-ContextualContrast $row.Foreground @($row.Background)
            # Variants share fills. Resolve and measure each syntax/background
            # pair once, while retaining the full result for every debugger state.
            if (-not $syntaxByBackground.ContainsKey($row.Background)) {
            $syntaxByBackground[$row.Background]=@(foreach ($syntax in $roles) {
                $measure=[ordered]@{Category=$syntax.Category;Role=$syntax.Role;Type=$null;Source=$null;Resolution=$syntax.Resolution;ResolvedForeground=$null;Ratio=$null;Status='unresolved';Detail=''}
                try {
                    $part=Part $syntax.Category $syntax.Role 'Foreground'
                    if ($null -eq $part) { throw 'Missing syntax foreground.' }
                    $measure.Type=[string]$part.Type; $measure.Source=[string]$part.Source
                    switch ($syntax.Resolution) {
                        'inherited-plain-text' {
                            if ($part.Type -cne 'CT_INVALID') { throw 'Member foreground must retain inheritance.' }
                            $part=Part 'Text Editor Text Manager Items' 'Plain Text' 'Foreground'
                        }
                        {$_ -in @('inherited-class','inherited-struct')} {
                            if ($part.Type -cne 'CT_INVALID') { throw 'Record foreground must retain inheritance.' }
                            $parent=if ($syntax.Resolution -eq 'inherited-class') {'class name'} else {'struct name'}
                            $part=Part 'Text Editor MEF Items' $parent 'Foreground'
                        }
                    }
                    $measure.ResolvedForeground=Opaque $part
                    $measure.Ratio=Get-ContextualContrast $measure.ResolvedForeground @($row.Background)
                    $measure.Status=if ($measure.Ratio+0.000001 -ge 4.5) {'passed'} else {'failed'}
                } catch { $measure.Detail=$_.Exception.Message }
                [pscustomobject]$measure
            })
            }
            $row.SyntaxMeasurements=$syntaxByBackground[$row.Background]
            $row.MinimumSyntaxContrast=($row.SyntaxMeasurements | Where-Object { $null -ne $_.Ratio } | Measure-Object Ratio -Minimum).Minimum
            $row.Status=if ($row.ForegroundContrast+0.000001 -ge 4.5 -and $row.SurfaceContrast -ge 1.1 -and $row.SurfaceContrast -le 2.5 -and @($row.SyntaxMeasurements | Where-Object Status -ne 'passed').Count -eq 0) {'passed'} else {'failed'}
            $row.Detail='Project guards: text >=4.5:1; fill/editor 1.1..2.5. Explicit foreground and preserved-syntax alternatives are screened separately. Painter precedence and overlapping states require IDE review.'
        } catch { $row.Detail=$_.Exception.Message }
        [pscustomobject]$row
    }
}
Export-ModuleMember -Function Get-DebuggerHighlightRoles,Test-DebuggerHighlightContrast

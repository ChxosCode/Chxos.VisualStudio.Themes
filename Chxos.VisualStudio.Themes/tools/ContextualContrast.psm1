Set-StrictMode -Version Latest

function Get-ContextualRgb {
    param([string] $Source)
    if ($Source -cnotmatch '^[0-9A-Fa-f]{8}$') { throw "Malformed ARGB '$Source'." }
    return @([Convert]::ToInt32($Source.Substring(2,2),16), [Convert]::ToInt32($Source.Substring(4,2),16), [Convert]::ToInt32($Source.Substring(6,2),16))
}

function Merge-ContextualColor {
    param([string] $Source, [double[]] $Underlay)
    $rgb = Get-ContextualRgb $Source
    $alpha = [Convert]::ToInt32($Source.Substring(0,2),16) / 255.0
    return @(0..2 | ForEach-Object { $rgb[$_] * $alpha + $Underlay[$_] * (1.0 - $alpha) })
}

function Get-ContextualLuminance {
    param([double[]] $Rgb)
    $linear = @($Rgb | ForEach-Object {
        $channel = $_ / 255.0
        if ($channel -le 0.04045) { $channel / 12.92 } else { [Math]::Pow(($channel + 0.055) / 1.055, 2.4) }
    })
    return 0.2126 * $linear[0] + 0.7152 * $linear[1] + 0.0722 * $linear[2]
}

function Get-ContextualContrast {
    # Layers are ordered from the nearest background to the outer opaque base.
    # No channel rounding is allowed between composition and threshold comparison.
    param([string] $Foreground, [string[]] $Layers)
    if ($Layers.Count -eq 0 -or $Layers[-1] -notmatch '^FF[0-9A-Fa-f]{6}$') {
        throw 'Contextual contrast requires a complete chain ending in an opaque base.'
    }
    $background = Get-ContextualRgb $Layers[-1]
    for ($i = $Layers.Count - 2; $i -ge 0; $i--) { $background = Merge-ContextualColor $Layers[$i] $background }
    $content = Merge-ContextualColor $Foreground $background
    $a = Get-ContextualLuminance $content
    $b = Get-ContextualLuminance $background
    return ([Math]::Max($a,$b) + 0.05) / ([Math]::Min($a,$b) + 0.05)
}

function Test-ContextualRelationships {
    param([xml] $Theme, [object[]] $Relationships)
    $index = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($category in $Theme.Themes.Theme.Category) {
        foreach ($color in $category.Color) {
            foreach ($component in $color.ChildNodes | Where-Object NodeType -eq Element) {
                $key = @($category.Name, $color.Name, $component.LocalName) -join [char]31
                if ($index.ContainsKey($key)) { throw "Duplicate component '$key'." }
                $index.Add($key, $component)
            }
        }
    }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Relationships) {
        if (-not $ids.Add($entry.id)) { throw "Duplicate relationship '$($entry.id)'." }
        $result = [ordered]@{ Theme = [string]$Theme.Themes.Theme.Name; Id = $entry.id; Group = $entry.group; Status = 'unresolved'; Ratio = $null; Minimum = $entry.minimum; Detail = $entry.confidence; Runtime = 'pending' }
        try {
            if ($entry.id -cnotmatch '^F0[1-7]-[0-9]{3}$') { throw 'Malformed relationship identity.' }
            if ($entry.disposition -notin @('confirmed-contract','unresolved','exempt')) { throw 'Unknown relationship disposition.' }
            if ($entry.contentType -notin @('text','glyph','unresolved')) { throw 'Unknown content type.' }
            if ($entry.disposition -eq 'confirmed-contract' -and $entry.contentType -eq 'unresolved') { throw 'Confirmed contracts require a content classification.' }
            if ($entry.disposition -eq 'exempt') {
                if (-not $entry.consumerEvidence -or -not $entry.confidence) { throw 'Exempt relationships require consumer evidence and rationale.' }
                $result.Status = 'exempt'
                $result.Detail = $entry.consumerEvidence
                [pscustomobject]$result
                continue
            }
            if ($entry.disposition -eq 'confirmed-contract' -and $entry.minimum -ne $(if ($entry.contentType -eq 'glyph') {3.0} else {4.5})) { throw 'Invalid enabled-content threshold.' }
            $sources = @()
            $unresolvedType = $false
            $references = @(@{ key = $entry.foreground }, @{ key = $entry.background })
            foreach ($base in $entry.bases) { $references += @{ key = $base } }
            foreach ($reference in $references) {
                if (@($reference.key).Count -ne 3) { throw 'Component references require category, color and component.' }
                $key = $reference.key -join [char]31
                if (-not $index.ContainsKey($key)) { throw "Missing component '$($reference.key -join '/')'." }
                $component = $index[$key]
                if ($component.Type -cne 'CT_RAW') {
                    if ($entry.disposition -eq 'unresolved') { $unresolvedType = $true; continue }
                    throw "Unresolved component type '$($component.Type)' at '$($reference.key -join '/')'."
                }
                $sources += [string]$component.Source
            }
            if ($unresolvedType) {
                $result.Detail = 'Runtime resolution required for a non-raw component; no raw contrast inferred.'
                [pscustomobject]$result
                continue
            }
            $ratio = Get-ContextualContrast -Foreground $sources[0] -Layers $sources[1..($sources.Count-1)]
            $result.Ratio = $ratio
            if ($entry.disposition -eq 'confirmed-contract') {
                $result.Status = if ($ratio -ge $entry.minimum) { 'validated' } else { 'failed' }
                $result.Detail = "$($entry.foreground -join '/') on $($entry.background -join '/'): $ratio; minimum $($entry.minimum). Source contract only; runtime pending."
            }
        }
        catch {
            $result.Status = 'invalid'
            $result.Detail = $_.Exception.Message
        }
        [pscustomobject]$result
    }
}

Export-ModuleMember -Function Get-ContextualContrast, Test-ContextualRelationships

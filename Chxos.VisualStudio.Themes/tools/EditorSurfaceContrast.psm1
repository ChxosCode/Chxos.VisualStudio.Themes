Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ContextualContrast.psm1')
Import-Module (Join-Path $PSScriptRoot 'EditorSelectionContrast.psm1')

function Test-EditorSurfaceContrast {
    param([xml] $Theme, [object] $Policy, [object[]] $SyntaxFamilies)
    # FontsAndColorsHelper converts editor overrides through Win32 RGB. Alpha
    # in a vstheme is not a reliable opacity control on this path. Opaque RGB
    # authoring is separate from the normal selection painter's element opacity.
    # Other surfaces retain their existing RGB/texture calculations.
    $index = @{}
    foreach ($category in $Theme.Themes.Theme.Category) {
        foreach ($color in $category.Color) {
            foreach ($part in $color.ChildNodes | Where-Object NodeType -eq Element) {
                $index[(@($category.Name,$color.Name,$part.LocalName) -join [char]31)] = $part
            }
        }
    }
    $editor = $index[(@('Text Editor Text Manager Items','Plain Text','Background') -join [char]31)]
    if ($null -eq $editor -or $editor.Type -cne 'CT_RAW' -or $editor.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Opaque editor base required.' }
    if ($Policy.SchemaVersion -ne 1 -or $Policy.MinimumSyntaxContrast -ne 4.5 -or $Policy.MinimumBorderContrast -ne 3 -or $Policy.MaximumFillContrast -ne 2.5 -or $Policy.MaximumHatchContrast -ne 2) { throw 'Invalid editor surface thresholds.' }
    foreach ($entry in $Policy.Surfaces) {
        $result = [ordered]@{ Theme=[string]$Theme.Themes.Theme.Name; Category=$entry.Category; Role=$entry.Role; Component=$entry.Component; Status='validated'; SurfaceContrast=$null; MinimumSyntaxContrast=$null; ContentContrast=$null; Detail=''; AuthoredBackground=$null; RenderedBackground=$null; RawSurfaceContrast=$null; Model=$null; RuntimeAcceptance='pending' }
        try {
            $surface = $editor
            if ($entry.PSObject.Properties.Name -contains 'SurfaceCategory') {
                $surface = $index[(@($entry.SurfaceCategory,'Plain Text','Background') -join [char]31)]
                if ($null -eq $surface -or $surface.Type -cne 'CT_RAW' -or $surface.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Registered pane requires its own opaque Plain Text background.' }
            }
            $key = @($entry.Category,$entry.Role,$entry.Component) -join [char]31
            $part = $index[$key]
            if ($null -eq $part -or $part.Type -cne 'CT_RAW' -or $part.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Editor RGB surface must use opaque CT_RAW; source alpha is not supported here.' }
            $value = [string]$part.Source
            $result.AuthoredBackground=$value
            $result.RawSurfaceContrast=Get-ContextualContrast -Foreground $value -Layers @([string]$surface.Source)
            if ($entry.Category -ceq 'Text Editor Text Manager Items' -and $entry.Role -ceq 'Inactive Selected Text' -and $entry.Component -ceq 'Background') {
                $value=Get-NormalSelectionBackground -Source $value -Underlay $surface.Source -Type $part.Type -UnderlayType $surface.Type
                $result.Model='normal-selection-18.10'
            }
            $result.RenderedBackground=$value
            $ratio = Get-ContextualContrast -Foreground $value -Layers @([string]$surface.Source)
            $result.SurfaceContrast = $ratio
            switch ($entry.Kind) {
                'fill' {
                    if ($ratio -gt $Policy.MaximumFillContrast) { throw "Harsh editor fill: $ratio exceeds the 2.5 surface/editor comfort limit." }
                }
                'hatch' {
                    if ($ratio -gt $Policy.MaximumHatchContrast -or $ratio -lt 1.1) { throw "Diff hatching must stay within 1.1 to 2.0 against the editor; found $ratio." }
                }
                'border' {
                    $fill = $index[(@($entry.Category,$entry.Role,'Background') -join [char]31)]
                    if ($null -eq $fill -or $fill.Type -cne 'CT_RAW' -or $fill.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Word border requires a registered opaque fill.' }
                    $innerRatio = Get-ContextualContrast -Foreground $value -Layers @([string]$fill.Source)
                    if ($ratio -lt $Policy.MinimumBorderContrast -or $innerRatio -lt $Policy.MinimumBorderContrast) { throw 'Diff word border must reach 3:1 against its fill and the editor.' }
                }
                default { throw 'Unknown editor surface kind.' }
            }
            if ($entry.Syntax) {
                $minimum = [double]::PositiveInfinity
                foreach ($syntax in $SyntaxFamilies) {
                    $foreground = $index[(@($syntax.Category,$syntax.Role,'Foreground') -join [char]31)]
                    if ($null -eq $foreground -or $foreground.Type -cne 'CT_RAW' -or $foreground.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw "Missing opaque syntax foreground: $($syntax.Role)." }
                    $contrast = Get-ContextualContrast -Foreground ([string]$foreground.Source) -Layers @($value)
                    $minimum = [Math]::Min($minimum,$contrast)
                    if ($contrast -lt $Policy.MinimumSyntaxContrast) { throw "Syntax '$($syntax.Role)' on editor RGB fill is $contrast; minimum 4.5." }
                }
                $result.MinimumSyntaxContrast = $minimum
            }
            if ($entry.PSObject.Properties.Name -contains 'ContentRole') {
                $content = $index[(@($entry.ContentCategory,$entry.ContentRole,'Foreground') -join [char]31)]
                if ($null -eq $content -or $content.Type -cne 'CT_RAW' -or $content.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Registered pane content requires an explicit opaque foreground.' }
                $contrast = Get-ContextualContrast -Foreground ([string]$content.Source) -Layers @($value)
                $result.ContentContrast = $contrast
                if ($contrast -lt 4.5) { throw "Pane content '$($entry.ContentRole)' is $contrast; minimum 4.5." }
            }
        }
        catch { $result.Status='failed'; $result.Detail=$_.Exception.Message }
        [pscustomobject]$result
    }
}
Export-ModuleMember -Function Test-EditorSurfaceContrast

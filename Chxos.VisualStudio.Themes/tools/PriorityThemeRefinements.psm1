Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ContextualContrast.psm1')
Import-Module (Join-Path $PSScriptRoot 'EditorSelectionContrast.psm1')

function Get-PriorityRefinementRoles {
    @{
        ControlSolidFillDefault = @(,@('Shell','ControlSolidFillDefault','Background'))
        EditorActiveSelectionFill = @(,@('Text Editor Text Manager Items','Selected Text','Background'))
        EditorInactiveSelectionFill = @(,@('Text Editor Text Manager Items','Inactive Selected Text','Background'))
        LegacyDisabledBorder = @(@('CommonControls','ButtonBorderDisabled','Background'),@('CommonControls','CheckBoxBorderDisabled','Background'))
        LineNumber = @(,@('Text Editor MEF Items','Line Number','Foreground'))
        SelectedLineNumber = @(,@('Text Editor MEF Items','Selected Line Number','Foreground'))
        InactivePaneBorder = @(@('ShellInternal','EnvironmentBorderInactive','Background'),@('Environment','ToolWindowBorder','Background'))
        ToolbarLayeredBorder = @(,@('ShellInternal','EnvironmentLayeredBorder','Background'))
    }
}

function Get-PrioritySelectionRoles {
    param([Collections.IDictionary]$Policy)
    $extra=@()
    if ($Policy.Contains('EditorSelectionModel')) {
        $extra=@('HTML Operator','HTML Tag Delimiter','CppMemberOperatorSemanticTokenFormat','CppControlKeywordSyntacticTokenFormat','C/C++ User Keywords','Preprocessor Keyword','RazorTagHelperAttribute','RazorTagHelperElement','RazorDirectiveAttribute','RazorComponentAttribute')
        $extra+=@('attribute name','attribute quotes','attribute value','cdata section','delimiter','entity reference','name','processing instruction' | ForEach-Object { 'xml doc comment - '+$_ })
        $extra=@($extra | ForEach-Object { @{Category='Text Editor MEF Items';Role=$_} })
    }
    $roles = $extra + @($Policy.EditorSyntaxFamilies) + @($Policy.CoreSyntaxFamilyRoles.Values | ForEach-Object { $_ }) + @($Policy.CoreSyntaxTypeCoupledMarkupRoles)
    @($roles | ForEach-Object {
        [pscustomobject]@{ Category=$_.Category; Role=$_.Role; Resolution='opaque-raw' }
    } | Sort-Object Category,Role -Unique) + @(foreach ($name in @('field name','property name','event name')) {
        [pscustomobject]@{ Category='Text Editor MEF Items'; Role=$name; Resolution='inherited-plain-text' }
    }) + @(
        [pscustomobject]@{ Category='Text Editor MEF Items'; Role='record class name'; Resolution='inherited-class' }
        [pscustomobject]@{ Category='Text Editor MEF Items'; Role='record struct name'; Resolution='inherited-struct' }
    )
}

function Get-PriorityColorDistance {
    param([string]$First,[string]$Second)
    $labs = @(foreach ($source in @($First,$Second)) {
        if ($source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Selection distance requires opaque RGB.' }
        $rgb = @(2,4,6 | ForEach-Object {
            $v=[Convert]::ToInt32($source.Substring($_,2),16)/255.0
            if ($v -le 0.04045) { $v/12.92 } else { [Math]::Pow(($v+0.055)/1.055,2.4) }
        })
        $l=[Math]::Pow(0.4122214708*$rgb[0]+0.5363325363*$rgb[1]+0.0514459929*$rgb[2],1.0/3)
        $m=[Math]::Pow(0.2119034982*$rgb[0]+0.6806995451*$rgb[1]+0.1073969566*$rgb[2],1.0/3)
        $s=[Math]::Pow(0.0883024619*$rgb[0]+0.2817188376*$rgb[1]+0.6299787005*$rgb[2],1.0/3)
        ,@((0.2104542553*$l+0.7936177850*$m-0.0040720468*$s),(1.9779984951*$l-2.4285922050*$m+0.4505937099*$s),(0.0259040371*$l+0.7827717662*$m-0.8086757660*$s))
    })
    [Math]::Sqrt([Math]::Pow($labs[0][0]-$labs[1][0],2)+[Math]::Pow($labs[0][1]-$labs[1][1],2)+[Math]::Pow($labs[0][2]-$labs[1][2],2))
}

function Get-PriorityIconRenderingDecision {
    # Numerical model observed in Imaging 18.10.1155.63130. Not runtime acceptance.
    param([string]$Background)
    if ($Background -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Image background requires opaque CT_RAW RGB.' }
    $rgb=@(2,4,6 | ForEach-Object { [Convert]::ToInt32($Background.Substring($_,2),16)/255.0 })
    $max=($rgb | Measure-Object -Maximum).Maximum; $min=($rgb | Measure-Object -Minimum).Minimum
    $lightness=($max+$min)/2.0
    $saturation=if ($max -eq $min) { 0.0 } else { ($max-$min)/(1.0-[Math]::Abs(2.0*$lightness-1.0)) }
    $lower=0.30-0.15*$saturation; $upper=0.70+0.15*$saturation
    [pscustomobject]@{ Background=$Background; Lightness=$lightness; Saturation=$saturation; Lower=$lower; Upper=$upper; Monochrome=($lightness -ge $lower -and $lightness -le $upper); LowerMargin=$lower-$lightness; Version='18.10.1155.63130' }
}

function Get-ThemeRefinementEnforcement {
    param([Collections.IDictionary]$Policy,[string]$ThemeName)
    if ($Policy.Contains('RefinementEnforcement') -and $Policy.RefinementEnforcement -is [Collections.IDictionary] -and
        $Policy.RefinementEnforcement.Contains($ThemeName) -and $Policy.RefinementEnforcement[$ThemeName] -cin @('enforced','pending')) {
        return $Policy.RefinementEnforcement[$ThemeName]
    }
    # Historical policy compatibility, also preserving established diagnostics
    # while the metadata validator reports an invalid current scope map.
    if ($Policy.Contains('PriorityRefinementAnchors') -and $Policy.PriorityRefinementAnchors -is [Collections.IDictionary] -and $Policy.PriorityRefinementAnchors.Contains($ThemeName)) { return 'enforced' }
    return 'pending'
}

function Test-RefinementEnforcementPolicy {
    param([Collections.IDictionary]$Policy,[string[]]$ThemeNames,[bool]$RequireExplicit=$true)
    if (-not $Policy.Contains('RefinementEnforcement')) {
        if ($RequireExplicit) { 'Missing RefinementEnforcement map.' }
        return
    }
    $scope=$Policy.RefinementEnforcement
    if ($scope -isnot [Collections.IDictionary]) { 'RefinementEnforcement must be a theme map.'; return }
    foreach ($name in $scope.Keys) {
        if ($name -cnotin $ThemeNames) { "Unknown refinement scope theme: $name." }
        if ($scope[$name] -cnotin @('enforced','pending')) { "Invalid refinement enforcement state for $name." }
    }
    foreach ($name in $ThemeNames) {
        if (-not $scope.Contains($name)) { "Missing refinement scope theme: $name."; continue }
        if ($scope[$name] -ceq 'enforced') {
            if (-not $Policy.Contains('PriorityRefinementAnchors') -or $Policy.PriorityRefinementAnchors -isnot [Collections.IDictionary] -or
                -not $Policy.PriorityRefinementAnchors.Contains($name) -or $Policy.PriorityRefinementAnchors[$name] -isnot [Collections.IDictionary]) {
                "Missing enforced refinement anchors for $name."; continue
            }
            $anchors=$Policy.PriorityRefinementAnchors[$name]
            foreach ($required in @('ControlSolidFillDefault','EditorActiveSelectionFill')) {
                if (-not $anchors.Contains($required)) { "Missing enforced refinement anchor $required for $name." }
            }
            $roles=Get-PriorityRefinementRoles
            foreach ($anchor in $anchors.Keys) {
                if (-not $roles.ContainsKey($anchor) -or $anchors[$anchor] -cnotmatch '^[0-9A-F]{8}$') { "Invalid refinement anchor $anchor for $name." }
            }
        }
    }
}

function Test-PriorityThemeRefinements {
    param([xml]$Theme,[Collections.IDictionary]$Policy)
    $name=[string]$Theme.Themes.Theme.Name
    $enforced=(Get-ThemeRefinementEnforcement $Policy $name) -ceq 'enforced'
    $anchorSet=@{}
    if ($Policy.Contains('PriorityRefinementAnchors') -and $Policy.PriorityRefinementAnchors -is [Collections.IDictionary] -and $Policy.PriorityRefinementAnchors.Contains($name) -and $Policy.PriorityRefinementAnchors[$name] -is [Collections.IDictionary]) { $anchorSet=$Policy.PriorityRefinementAnchors[$name] }
    $parts=@{}
    foreach ($category in $Theme.Themes.Theme.Category) {
        foreach ($color in $category.Color) {
            foreach ($part in $color.ChildNodes | Where-Object NodeType -eq Element) {
                $parts[(@($category.Name,$color.Name,$part.LocalName) -join [char]31)]=$part
            }
        }
    }
    function Part([string[]]$Key) { $parts[($Key -join [char]31)] }
    function Row([string]$Check,[string]$Component,[string]$State) {
        [ordered]@{ Theme=$name; Check=$Check; Component=$Component; State=$State; Status='unresolved'; Enforced=$enforced; Foreground=$null; Background=$null; ForegroundType=$null; Resolution=$null; Ratio=$null; Distance=$null; Minimum=$null; Detail=''; ContractIds=@('RC-PRIORITY-REFINEMENTS'); RuntimeAcceptance='pending'; AuthoredBackground=$null; RenderedBackground=$null; RawRatio=$null; RawDistance=$null; RawMinimum=$null; RawStatus=$null; Underlay=$null; Model=$null; EvidenceIds=@('SEL-PAINTER-1810','SEL-CALCULATION'); OriginalSource=$null; InheritanceTarget=$null }
    }
    $scopeProblem=$null
    if ($Policy.Contains('RefinementEnforcement') -and ($Policy.RefinementEnforcement -isnot [Collections.IDictionary] -or
        -not $Policy.RefinementEnforcement.Contains($name) -or $Policy.RefinementEnforcement[$name] -cnotin @('enforced','pending'))) {
        $scopeProblem='The explicit refinement scope is missing or invalid for this theme.'
    }
    if ($enforced -and (-not $anchorSet.Contains('ControlSolidFillDefault') -or -not $anchorSet.Contains('EditorActiveSelectionFill'))) {
        $scopeProblem='Enforced refinement checks require solid-control and active-selection anchors.'
    }
    if ($scopeProblem) {
        $row=Row 'refinement-scope' 'ThemeRolePolicy/RefinementEnforcement' 'metadata'
        $row.Enforced=$true; $row.Status='failed'; $row.Detail=$scopeProblem
        [pscustomobject]$row
    }
    if ($enforced) {
        $roleMap=Get-PriorityRefinementRoles
        foreach ($anchor in $anchorSet.Keys | Sort-Object) {
            if (-not $roleMap.ContainsKey($anchor)) { continue } # Metadata error; retain other color diagnostics.
            foreach ($key in $roleMap[$anchor]) {
                $row=Row 'anchor' ($key -join '/') $anchor
                $part=Part $key; $expected=$anchorSet[$anchor]
                $row.Status=if ($null -ne $part -and $part.Type -ceq 'CT_RAW' -and $part.Source -ceq $expected) {'passed'} else {'failed'}
                $row.Detail="Priority refinement $anchor requires CT_RAW/$expected."
                [pscustomobject]$row
            }
        }
        $icon=Part @('Shell','ControlSolidFillDefault','Background')
        $row=Row 'image-context' 'Shell/ControlSolidFillDefault/Background' 'normal enabled themeable image'
        $row.ContractIds=@('RC-TOOLBAR-IMAGE-CONTEXT')
        try {
            if ($null -eq $icon -or $icon.Type -cne 'CT_RAW') { throw 'Image context must be CT_RAW.' }
            $decision=Get-PriorityIconRenderingDecision $icon.Source
            $row.Status=if ($decision.Monochrome) {'failed'} else {'passed'}
            $row.Background=$icon.Source
            $row.Detail='Pinned Imaging 18.10.1155.63130 branch model; actual icon visibility requires runtime review.'
        } catch { $row.Detail=$_.Exception.Message }
        [pscustomobject]$row
    }
    $selectionPolicy=$null
    if ($Policy.Contains('EditorSelectionModel')) {
        try {
            $selectionPolicy=Read-EditorSelectionPolicy
            if ($Policy.EditorSelectionModel -cne $selectionPolicy.Id) { throw 'Selection model identifier disagrees with policy.' }
        } catch {
            $selectionPolicy=$null
            $row=Row 'selection-model' 'EditorSelectionPolicy' 'metadata'
            $row.Enforced=$true; $row.Status='failed'; $row.Detail=$_.Exception.Message
            [pscustomobject]$row
        }
    }
    $editor=Part @('Text Editor Text Manager Items','Plain Text','Background')
    $plain=Part @('Text Editor Text Manager Items','Plain Text','Foreground')
    foreach ($state in @('Selected Text','Inactive Selected Text')) {
        $background=Part @('Text Editor Text Manager Items',$state,'Background')
        foreach ($role in Get-PrioritySelectionRoles $Policy) {
            $row=Row 'selection-text' ($role.Category+'/'+$role.Role+'/Foreground') $state
            $row.ContractIds=@('RC-ACTIVE-SELECTION','RC-PRIORITY-REFINEMENTS')
            $row.Minimum=$Policy.PrioritySelectionMinimum
            try {
                if ($null -eq $background -or $background.Type -cne 'CT_RAW' -or $background.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Selection background is not a resolved opaque raw RGB value.' }
                $foreground=Part @($role.Category,$role.Role,'Foreground')
                if ($null -eq $foreground) { throw 'Registered selection foreground is missing.' }
                $row.ForegroundType=[string]$foreground.Type; $row.OriginalSource=[string]$foreground.Source; $row.Resolution=$role.Resolution
                if ($role.Resolution -eq 'inherited-plain-text') {
                    if ($foreground.Type -cne 'CT_INVALID') { throw 'Member foreground must retain CT_INVALID inheritance.' }
                    $foreground=$plain; $row.InheritanceTarget='Text Editor Text Manager Items/Plain Text/Foreground'
                }
                elseif ($role.Resolution -in @('inherited-class','inherited-struct')) {
                    if ($foreground.Type -cne 'CT_INVALID') { throw 'Record foreground must retain CT_INVALID base-classification inheritance.' }
                    $baseRole=if ($role.Resolution -eq 'inherited-class') { 'class name' } else { 'struct name' }
                    $foreground=Part @('Text Editor MEF Items',$baseRole,'Foreground'); $row.InheritanceTarget='Text Editor MEF Items/'+$baseRole+'/Foreground'
                }
                if ($null -eq $foreground -or $foreground.Type -cne 'CT_RAW' -or $foreground.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Foreground resolution is unresolved; typed values are not interchangeable.' }
                $row.Foreground=[string]$foreground.Source; $row.Background=[string]$background.Source
                $row.AuthoredBackground=$row.Background
                $row.RawRatio=Get-ContextualContrast -Foreground $row.Foreground -Layers @($row.Background)
                $row.RawStatus=if ($row.RawRatio+0.000001 -ge $row.Minimum) {'passed'} else {'failed'}
                if ($Policy.Contains('EditorSelectionModel')) {
                    if ($null -eq $selectionPolicy) { throw 'Invalid selection model; no fallback rendering assumption.' }
                    $row.Underlay=[string]$editor.Source; $row.Model=$selectionPolicy.Id
                    $row.Background=Get-NormalSelectionBackground -Source $background.Source -Type $background.Type -Underlay $editor.Source -UnderlayType $editor.Type -Policy $selectionPolicy
                }
                $row.RenderedBackground=$row.Background
                $row.Ratio=Get-ContextualContrast -Foreground $row.Foreground -Layers @($row.Background)
                $row.Status=if ($row.Ratio+0.000001 -ge $row.Minimum) {'passed'} else {'failed'}
                $row.Detail="Registered syntax on $state; source calculation, overlap/runtime acceptance pending."
            } catch { $row.Detail=$_.Exception.Message }
            [pscustomobject]$row
        }
    }
    if ($enforced) {
        $row=Row 'selection-state-distance' 'Text Editor Text Manager Items/Selected Text/Background' 'active versus inactive'
        $row.Minimum=$Policy.PrioritySelectionDistanceMinimum
        try {
            $active=Part @('Text Editor Text Manager Items','Selected Text','Background')
            $inactive=Part @('Text Editor Text Manager Items','Inactive Selected Text','Background')
            $row.RawDistance=Get-PriorityColorDistance $active.Source $inactive.Source
            $row.RawMinimum=$Policy.PrioritySelectionDistanceMinimum
            $row.RawStatus=if ($row.RawDistance+0.000001 -ge $row.RawMinimum) {'passed'} else {'failed'}
            $row.Distance=$row.RawDistance
            if ($Policy.Contains('EditorSelectionModel')) {
                if ($null -eq $selectionPolicy) { throw 'Invalid selection model; no fallback rendering assumption.' }
                $activeRendered=Get-NormalSelectionBackground $active.Source $editor.Source -Type $active.Type -UnderlayType $editor.Type -Policy $selectionPolicy
                $inactiveRendered=Get-NormalSelectionBackground $inactive.Source $editor.Source -Type $inactive.Type -UnderlayType $editor.Type -Policy $selectionPolicy
                $row.Distance=Get-PriorityColorDistance $activeRendered $inactiveRendered
                $row.Minimum=$selectionPolicy.Guards.$name.MinimumStateDistance
                $row.Model=$selectionPolicy.Id
            }
            $row.Status=if ($row.Distance+0.000001 -ge $row.Minimum) {'passed'} else {'failed'}
            $row.Detail='Project OKLab regression guard; not a WCAG or perceptual acceptance claim.'
        } catch { $row.Detail=$_.Exception.Message }
        [pscustomobject]$row
    }
    if ($Policy.Contains('EditorSelectionModel') -and $null -ne $selectionPolicy) {
        $guard=$selectionPolicy.Guards.$name
        foreach ($state in @('Selected Text','Inactive Selected Text')) {
            $row=Row 'selection-visibility' 'Text Editor Text Manager Items' $state
            $row.Minimum=if ($state -eq 'Selected Text') {$guard.MinimumActiveVisibility} else {$guard.MinimumInactiveVisibility}
            try {
                $part=Part @('Text Editor Text Manager Items',$state,'Background')
                $row.AuthoredBackground=$part.Source; $row.Underlay=$editor.Source; $row.Model=$selectionPolicy.Id
                $row.RenderedBackground=Get-NormalSelectionBackground $part.Source $editor.Source -Type $part.Type -UnderlayType $editor.Type -Policy $selectionPolicy
                $row.Ratio=Get-ContextualContrast -Foreground $row.RenderedBackground -Layers @($editor.Source)
                $maximum=if ($state -eq 'Selected Text') {$guard.MaximumActiveVisibility} else {$guard.MaximumActiveVisibility}
                $row.Status=if ($row.Ratio+0.000001 -ge $row.Minimum -and $row.Ratio-0.000001 -le $maximum) {'passed'} else {'failed'}
                $row.Detail="Project rendered visibility bounds $($row.Minimum)..$maximum; runtime pending."
            } catch {$row.Detail=$_.Exception.Message}
            [pscustomobject]$row
        }
        $row=Row 'selection-order' 'Text Editor Text Manager Items' 'active versus inactive'
        try {
            $a=Part @('Text Editor Text Manager Items','Selected Text','Background'); $i=Part @('Text Editor Text Manager Items','Inactive Selected Text','Background')
            $ar=Get-NormalSelectionBackground $a.Source $editor.Source -Type $a.Type -UnderlayType $editor.Type -Policy $selectionPolicy
            $ir=Get-NormalSelectionBackground $i.Source $editor.Source -Type $i.Type -UnderlayType $editor.Type -Policy $selectionPolicy
            $av=Get-ContextualContrast -Foreground $ar -Layers @($editor.Source);$iv=Get-ContextualContrast -Foreground $ir -Layers @($editor.Source)
            $row.Status=if ($av -gt $iv) {'passed'} else {'failed'}
            $row.Detail='Active selection must remain more visible than inactive; overlapping-state rendering pending.'
        } catch {$row.Detail=$_.Exception.Message}
        [pscustomobject]$row
        foreach ($state in @('Selected Text','Inactive Selected Text')) {
            $row=Row 'selection-legacy-foreground' 'Text Editor Text Manager Items' $state
            $row.Enforced=$false; $row.Minimum=$Policy.PrioritySelectionMinimum
            try {
                $b=Part @('Text Editor Text Manager Items',$state,'Background');$f=Part @('Text Editor Text Manager Items',$state,'Foreground')
                $row.AuthoredBackground=[string]$b.Source;$row.Foreground=[string]$f.Source;$row.ForegroundType=[string]$f.Type
                if ($f.Type -cne 'CT_RAW' -or $b.Type -cne 'CT_RAW') { throw 'Historical pair contains inherited or unresolved values.' }
                $row.RawRatio=Get-ContextualContrast -Foreground $f.Source -Layers @($b.Source)
                $row.Status=if ($row.RawRatio+0.000001 -ge $row.Minimum) {'passed'} else {'failed'}
                $row.Detail='Historical source pair; this foreground override is not painted by the normal selection consumer.'
            } catch {$row.Detail=$_.Exception.Message}
            [pscustomobject]$row
        }
        $row=Row 'selection-current-line-hierarchy' 'Text Editor MEF Items/CurrentLineActiveFormat/Background' 'inactive selection versus current line'
        $row.Enforced=$false
        try {
            $line=Part @('Text Editor MEF Items','CurrentLineActiveFormat','Background')
            if ($line.Type -cne 'CT_RAW' -or $line.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Current-line comparison requires its registered opaque source.' }
            $currentDistance=Get-PriorityColorDistance $editor.Source $line.Source
            $row.Distance=Get-PriorityColorDistance $editor.Source $ir
            $row.Minimum=$currentDistance
            $row.RawDistance=Get-PriorityColorDistance $editor.Source $i.Source
            $row.RawStatus=if ($row.RawDistance+0.000001 -ge $currentDistance) {'passed'} else {'failed'}
            $row.Status=if ($name -ceq 'Amberroot') {'unresolved'} elseif ($row.Distance+0.000001 -ge $currentDistance) {'passed'} else {'failed'}
            $row.Detail='Current-line source comparison uses no selection opacity. Amberroot conflict and actual overlapping-state hierarchy require runtime review; other themes retain the main-validator guard.'
        } catch {$row.Detail=$_.Exception.Message}
        [pscustomobject]$row
        if ($name -ceq 'Nullsector') {
            foreach ($kind in @('active-prominence','active-inactive-prominence')) {
                $row=Row 'selection-legacy-prominence' 'Text Editor Text Manager Items' $kind
                $row.Enforced=$false
                $row.Minimum=if ($kind -eq 'active-prominence') {0.12} else {0.04}
                try {
                    $row.RawDistance=Get-PriorityColorDistance $editor.Source $a.Source
                    if ($kind -eq 'active-inactive-prominence') { $row.RawDistance-=(Get-PriorityColorDistance $editor.Source $i.Source) }
                    $row.Status=if ($row.RawDistance+0.000001 -ge $row.Minimum) {'passed'} else {'failed'}
                    $row.Detail='Superseded raw-fill project prominence diagnostic; rendered per-theme bounds own enforcement.'
                } catch {$row.Detail=$_.Exception.Message}
                [pscustomobject]$row
            }
        }
        foreach ($item in $selectionPolicy.Unresolved | Where-Object Theme -CEQ $name) {
            $row=Row 'selection-unresolved-classification' ($item.Key -join '/') 'unresolved consumer'
            $row.Enforced=$false;$row.ForegroundType=$item.Type;$row.OriginalSource=$item.Source;$row.Detail=$item.Next
            [pscustomobject]$row
        }
    }

}

Export-ModuleMember -Function Get-PriorityRefinementRoles,Get-PrioritySelectionRoles,Get-PriorityColorDistance,Get-PriorityIconRenderingDecision,Get-ThemeRefinementEnforcement,Test-RefinementEnforcementPolicy,Test-PriorityThemeRefinements

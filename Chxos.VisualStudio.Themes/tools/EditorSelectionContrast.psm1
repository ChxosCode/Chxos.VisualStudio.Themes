Set-StrictMode -Version Latest

function Read-EditorSelectionPolicy {
    param([string]$Path=(Join-Path $PSScriptRoot 'EditorSelectionPolicy.json'))
    $p=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($p.SchemaVersion -ne 1 -or $p.Id -cne 'normal-selection-18.10' -or $p.Version -cne '18.10.106.50897' -or
        $p.BrushOpacity -ne 1 -or $p.ElementOpacity -ne 0.4 -or $p.LayerOpacity -ne 1 -or
        ($p.Underlay -join '/') -cne 'Text Editor Text Manager Items/Plain Text/Background' -or
        $p.Rounding -cne 'floor(channel + 0.5)' -or $p.MinimumTextContrast -ne 4.5) { throw 'Invalid normal-selection rendering model metadata.' }
    $themes=@((Get-Content (Join-Path $PSScriptRoot '../authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json).Name)
    if ((@($p.Guards.PSObject.Properties.Name | Sort-Object) -join '|') -cne (($themes | Sort-Object) -join '|')) { throw 'Selection guards must cover exactly the theme catalog.' }
    foreach ($theme in $themes) {
        $g=$p.Guards.$theme
        foreach ($key in @('MinimumActiveVisibility','MinimumInactiveVisibility','MinimumStateDistance','MaximumActiveVisibility')) {
            if ($g.$key -isnot [ValueType] -or [double]::IsNaN($g.$key) -or [double]::IsInfinity($g.$key)) { throw 'Selection bounds require finite numbers.' }
        }
        if ($g.MinimumInactiveVisibility -le 1 -or $g.MinimumActiveVisibility -le $g.MinimumInactiveVisibility -or
            $g.MaximumActiveVisibility -le $g.MinimumActiveVisibility -or $g.MinimumStateDistance -le 0) { throw 'Invalid selection visibility/separation bounds.' }
    }
    if (($p.HierarchyPending -join '|') -cne 'Amberroot') { throw 'Only the reviewed Amberroot hierarchy exception is registered.' }
    if (@($p.ExtraRoles).Count -ne 18 -or @($p.ExtraRoles | Group-Object Category,Role | Where-Object Count -ne 1).Count) { throw 'Selection additions must contain 18 distinct roles.' }
    foreach ($role in $p.ExtraRoles) {
        if ($role.Category -cne 'Text Editor MEF Items' -or -not $role.Role -or $role.Resolution -cne 'opaque-raw') { throw 'Invalid additional selection role.' }
    }
    $expected=@('HTML Operator','HTML Tag Delimiter','CppMemberOperatorSemanticTokenFormat','CppControlKeywordSyntacticTokenFormat','C/C++ User Keywords','Preprocessor Keyword','RazorTagHelperAttribute','RazorTagHelperElement','RazorDirectiveAttribute','RazorComponentAttribute')
    $expected+=@('attribute name','attribute quotes','attribute value','cdata section','delimiter','entity reference','name','processing instruction' | ForEach-Object {'xml doc comment - '+$_})
    if ((($p.ExtraRoles.Role | Sort-Object) -join '|') -cne (($expected | Sort-Object) -join '|')) {throw 'Selection additions disagree with the reviewed matrix.'}
    $unresolvedKeys=@($p.Unresolved | ForEach-Object { $_.Theme+'/'+($_.Key -join '/') })
    if ($unresolvedKeys.Count -ne 182 -or @($unresolvedKeys | Select-Object -Unique).Count -ne 182) { throw 'Unresolved selection inventory must retain 182 distinct records.' }
    foreach ($theme in $themes) { if (@($p.Unresolved | Where-Object Theme -CEQ $theme).Count -ne 14) { throw 'Each theme requires its fourteen unresolved classification records.' } }
    foreach ($item in $p.Unresolved) { if ($item.Theme -cnotin $themes -or -not $item.Next -or @($item.Key).Count -ne 3) { throw 'Unresolved classification requires a component, theme and investigation.' } }
    return $p
}

function Get-NormalSelectionBackground {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Underlay,
        [string]$Type='CT_RAW',[string]$UnderlayType='CT_RAW',[object]$Policy=(Read-EditorSelectionPolicy))
    if ($Type -cne 'CT_RAW' -or $UnderlayType -cne 'CT_RAW' -or $Source -cnotmatch '^FF[0-9A-F]{6}$' -or $Underlay -cnotmatch '^FF[0-9A-F]{6}$') {
        throw 'Normal selection requires opaque CT_RAW RGB and an opaque editor underlay; typed values cannot be substituted.'
    }
    if ($Policy.Id -cne 'normal-selection-18.10' -or $Policy.Version -cne '18.10.106.50897' -or
        $Policy.ElementOpacity -ne 0.4 -or $Policy.LayerOpacity -ne 1 -or $Policy.BrushOpacity -ne 1 -or
        $Policy.Rounding -cne 'floor(channel + 0.5)' -or ($Policy.Underlay -join '/') -cne 'Text Editor Text Manager Items/Plain Text/Background') { throw 'Unsupported selection opacity model.' }
    # Version-pinned element opacity, not authored alpha. Encoded sRGB channels;
    # round once. This rounding is a project policy, not lossless runtime evidence.
    $channels=foreach ($offset in @(2,4,6)) {
        $foreground=[Convert]::ToInt32($Source.Substring($offset,2),16)
        $background=[Convert]::ToInt32($Underlay.Substring($offset,2),16)
        ([int][Math]::Floor($foreground*0.4+$background*0.6+0.5)).ToString('X2')
    }
    'FF'+($channels -join '')
}

function Restore-EditorSelectionBaseline {
    param([xml]$Theme,[string]$File)
    # Regression fixtures unwind only verified, explicit edits before comparing
    # immutable historical fingerprints. This never modifies a source file.
    $changes=Get-Content (Join-Path $PSScriptRoot 'evidence/editor-selection/changes.json') -Raw | ConvertFrom-Json
    foreach ($change in $changes | Where-Object File -CEQ $File) {
        $node=$Theme.SelectSingleNode('//Category[@Name="'+$change.Key[0]+'"]/Color[@Name="'+$change.Key[1]+'"]/'+$change.Key[2])
        if ($null -eq $node -or $node.Type -cne $change.Type -or $node.Source -cne $change.After) { throw "Unexpected selection migration component: $File/$($change.Key -join '/')." }
        $node.SetAttribute('Source',$change.Before)
    }
}
Export-ModuleMember -Function Read-EditorSelectionPolicy,Get-NormalSelectionBackground,Restore-EditorSelectionBaseline

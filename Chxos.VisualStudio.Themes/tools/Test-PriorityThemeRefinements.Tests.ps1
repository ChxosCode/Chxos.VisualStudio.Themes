[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PriorityThemeRefinements.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EditorSelectionContrast.psm1')
$project=Split-Path -Parent $PSScriptRoot
$policy=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
$count=0
$selectionRoles=@(Get-PrioritySelectionRoles $policy)
function Assert-Case([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:count++; Write-Host "PASS: $Name"
}
$catalog=Get-Content (Join-Path $project 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json
foreach ($entry in $catalog) {
    [xml]$xml=Get-Content (Join-Path $project $entry.File) -Raw
    $rows=@(Test-PriorityThemeRefinements $xml $policy)
    $priority=(Get-ThemeRefinementEnforcement $policy $entry.Name) -ceq 'enforced'
    Assert-Case (@($rows | Where-Object { $_.Enforced -and $_.Status -ne 'passed' }).Count -eq 0) "$($entry.Name) enforced checks pass"
    Assert-Case (@($rows | Where-Object Check -eq 'selection-text').Count -eq ($selectionRoles.Count*2)) "$($entry.Name) has the complete policy-derived matrix in both states"
    if (-not $priority) { Assert-Case (@($rows | Where-Object Enforced).Count -eq 0) "$($entry.Name) expanded checks remain non-enforcing" }
}
[xml]$foundation=Get-Content (Join-Path $project 'Foundation.vstheme') -Raw
function Mutate-Case([string]$Name,[string]$XPath,[string]$Attribute,[string]$Value,[string]$Check) {
    [xml]$copy=$foundation.OuterXml
    $node=$copy.SelectSingleNode($XPath)
    if ($null -eq $node) { throw "Missing mutation target: $XPath" }
    $node.SetAttribute($Attribute,$Value)
    $bad=@(Test-PriorityThemeRefinements $copy $policy | Where-Object { $_.Enforced -and $_.Check -eq $Check -and $_.Status -ne 'passed' })
    Assert-Case ($bad.Count -gt 0) $Name
}
$selected='//Category[@Name="Text Editor Text Manager Items"]/Color[@Name="Selected Text"]/Background'
$inactive='//Category[@Name="Text Editor Text Manager Items"]/Color[@Name="Inactive Selected Text"]/Background'
Mutate-Case 'bright active fill fails full syntax matrix' $selected Source 'FFFFFFFF' 'selection-text'
Mutate-Case 'Foundation state collapse fails' $inactive Source $policy.ActiveSelectionAnchors.Foundation 'selection-state-distance'
Mutate-Case 'transparent selection remains unresolved' $selected Source '40223249' 'selection-text'
Mutate-Case 'automatic selection is not raw' $selected Type 'CT_AUTOMATIC' 'selection-text'
Mutate-Case 'documentation comments are checked' '//Color[@Name="xml doc comment - text"]/Foreground' Source 'FF223249' 'selection-text'
Mutate-Case 'inherited member foreground remains invalid' '//Color[@Name="field name"]/Foreground' Type 'CT_RAW' 'selection-text'
Mutate-Case 'inherited members resolve current plain text' '//Category[@Name="Text Editor Text Manager Items"]/Color[@Name="Plain Text"]/Foreground' Source 'FF223249' 'selection-text'
Mutate-Case 'solid-control regression is rejected' '//Category[@Name="Shell"]/Color[@Name="ControlSolidFillDefault"]/Background' Source 'FF777777' 'image-context'
[xml]$missing=$foundation.OuterXml
$node=$missing.SelectSingleNode('//Color[@Name="xml doc comment - text"]/Foreground');[void]$node.ParentNode.RemoveChild($node)
Assert-Case (@(Test-PriorityThemeRefinements $missing $policy | Where-Object { $_.Enforced -and $_.Status -eq 'unresolved' }).Count -gt 0) 'missing registered role does not silently pass'
foreach ($source in @('FF757575','FFB2B2B2','FF777777')) { Assert-Case (Get-PriorityIconRenderingDecision $source).Monochrome "inside pinned monochrome band: $source" }
foreach ($source in @('FF4C4C4C','FFB3B3B3','FF424248')) { Assert-Case (-not (Get-PriorityIconRenderingDecision $source).Monochrome) "outside pinned monochrome band: $source" }
Assert-Case ((Get-PriorityColorDistance 'FF223249' 'FF1C293B') -gt 0.03) 'Foundation paired adjustment retains separation'
# Minimal published regression baselines; private implementation reports are
# intentionally not dependencies of a clean checkout.
$evidence=Join-Path $PSScriptRoot 'evidence/editor-semantics'
$preservation=Get-Content (Join-Path $evidence 'preservation.json') -Raw | ConvertFrom-Json
$debuggerMigration=Get-Content (Join-Path $PSScriptRoot 'evidence/debugger-highlights/changes.json') -Raw | ConvertFrom-Json
$migration=Get-Content (Join-Path $PSScriptRoot 'evidence/deferred-refinements/changes.json') -Raw | ConvertFrom-Json
$changes=(Get-Content (Join-Path $evidence 'change-register.json') -Raw | ConvertFrom-Json).Changes
foreach ($entry in $catalog) {
    [xml]$xml=Get-Content (Join-Path $project $entry.File) -Raw
    Restore-EditorSelectionBaseline $xml $entry.File
    # Check each migrated role, then restore only that role in this local XML
    # copy before comparing the immutable historical component fingerprint.
    foreach ($change in @($debuggerMigration | Where-Object File -ceq $entry.File)+@($migration | Where-Object File -ceq $entry.File)) {
        $node=$xml.SelectSingleNode('//Category[@Name="'+$change.Key[0]+'"]/Color[@Name="'+$change.Key[1]+'"]/'+$change.Key[2])
        Assert-Case ($null -ne $node -and $node.Type -ceq 'CT_RAW' -and $node.Source -ceq $change.After) "$($entry.Name) exact migrated role: $($change.Key -join '/')"
        $node.SetAttribute('Source',$change.Before)
    }
    $excluded=@($changes | Where-Object File -ceq $entry.File | ForEach-Object { $_.Key -join [char]31 })
    [string[]]$lines=@(foreach ($cat in $xml.Themes.Theme.Category) { foreach ($color in $cat.Color) { foreach ($part in $color.ChildNodes | Where-Object NodeType -eq Element) {
        $key=@($cat.Name,$color.Name,$part.LocalName) -join [char]31
        if ($key -cnotin $excluded) { @($key,$part.Type,$part.Source) -join [char]31 }
    } } })
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")+"`n"))).Replace('-','') } finally { $sha.Dispose() }
    $baseline=$preservation | Where-Object File -ceq $entry.File
    Assert-Case ($hash -ceq $baseline.UntouchedComponentsSha256) "$($entry.Name) unrelated typed components unchanged"
    if ((Get-ThemeRefinementEnforcement $policy $entry.Name) -ceq 'pending') { Assert-Case ((Get-FileHash (Join-Path $project $entry.File)).Hash -ceq $baseline.SourceSha256) "$($entry.Name) matches approved semantic refinement source" }
}
Assert-Case (@(Test-RefinementEnforcementPolicy $policy @($catalog.Name)).Count -eq 0) 'explicit scope covers the catalog'
foreach ($case in @('missing-map','missing-theme','unknown-theme','invalid-state','missing-anchors')) {
    $copy=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
    switch ($case) {
        'missing-map' { $copy.Remove('RefinementEnforcement') }
        'missing-theme' { $copy.RefinementEnforcement.Remove('Amberroot') }
        'unknown-theme' { $copy.RefinementEnforcement['Not a theme']='pending' }
        'invalid-state' { $copy.RefinementEnforcement.Foundation='ENFORCED' }
        'missing-anchors' { $copy.PriorityRefinementAnchors.Remove('Foundation') }
    }
    Assert-Case (@(Test-RefinementEnforcementPolicy $copy @($catalog.Name)).Count -gt 0) "invalid scope rejected: $case"
    # Invalid metadata must not interrupt collection of existing color diagnostics.
    Assert-Case (@(Test-PriorityThemeRefinements $foundation $copy | Where-Object Check -eq 'selection-text').Count -eq ($selectionRoles.Count*2)) "matrix remains available with $case"
}
$historical=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1');$historical.Remove('RefinementEnforcement'); foreach ($name in @('Amberroot','Aquatoxic','Biolume','Hardline','Nightglass','Nullsector','Silverphase')) { $historical.PriorityRefinementAnchors.Remove($name) }
Assert-Case ((Get-ThemeRefinementEnforcement $historical 'Foundation') -ceq 'enforced' -and (Get-ThemeRefinementEnforcement $historical 'Hardline') -ceq 'pending') 'historical policy retains its original scope'
$transition=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
[xml]$hardline=Get-Content (Join-Path $project 'Hardline.vstheme') -Raw
$transition.RefinementEnforcement.Hardline='pending'
$transition.PriorityRefinementAnchors.Hardline=@{ControlSolidFillDefault='FF34393C';EditorActiveSelectionFill=$policy.ActiveSelectionAnchors.Hardline}
Assert-Case (@(Test-PriorityThemeRefinements $hardline $transition | Where-Object Enforced).Count -eq 0) 'anchor ownership alone does not enable enforcement'
$transition.RefinementEnforcement.Hardline='enforced'
Assert-Case (@(Test-PriorityThemeRefinements $hardline $transition | Where-Object { $_.Enforced -and $_.Status -ne 'passed' }).Count -eq 0) 'pending theme can migrate without palette changes'
$hardline.SelectSingleNode('//Color[@Name="xml doc comment - text"]/Foreground').SetAttribute('Source','FF20384A')
Assert-Case (@(Test-PriorityThemeRefinements $hardline $transition | Where-Object { $_.Enforced -and $_.Status -eq 'failed' }).Count -gt 0) 'migrated theme enforces the full syntax matrix'
$transition.RefinementEnforcement.Hardline='pending'
Assert-Case (@(Test-PriorityThemeRefinements $hardline $transition | Where-Object { -not $_.Enforced -and $_.Status -eq 'failed' }).Count -gt 0) 'pending failures remain measured'
$packageCatalog=Get-Content (Join-Path $project 'authoring/PackageCatalog.json') -Raw | ConvertFrom-Json
Assert-Case ('Hardline.vstheme' -cin $packageCatalog.DeferredPublicThemes) 'scope migration does not promote package ownership'
# All inherited syntax roles must stay explicit about unresolved automatic values.
foreach ($role in @('field name','property name','event name','record class name','record struct name')) {
    Mutate-Case "automatic inherited role rejected: $role" ('//Color[@Name="'+$role+'"]/Foreground') Type 'CT_AUTOMATIC' 'selection-text'
}
if ($policy.RefinementEnforcement.Nullsector -ceq 'enforced') {
    [xml]$nullsector=Get-Content (Join-Path $project 'Nullsector.vstheme') -Raw
    $comments=@($migration | Where-Object { $_.Theme -ceq 'Nullsector' -and $_.After -ceq 'FF8190A2' })
    Assert-Case ($comments.Count -eq 11) 'Nullsector has exactly eleven reviewed comment changes'
    foreach ($change in $comments) {
        [xml]$copy=$nullsector.OuterXml
        $copy.SelectSingleNode('//Category[@Name="'+$change.Key[0]+'"]/Color[@Name="'+$change.Key[1]+'"]/'+$change.Key[2]).SetAttribute('Source','FF748395')
        Assert-Case (@(Test-PriorityThemeRefinements $copy $policy | Where-Object { $_.Enforced -and $_.Check -eq 'selection-text' -and $_.Status -eq 'failed' }).Count -gt 0) "Nullsector comment regression: $($change.Key[1])"
    }
    foreach ($role in @('HTML Operator','HTML Tag Delimiter')) {
        Assert-Case ($nullsector.SelectSingleNode('//Category[@Name="Text Editor MEF Items"]/Color[@Name="'+$role+'"]/Foreground').Source -ceq 'FF8693A2') "Nullsector punctuation explicitly refined: $role"
    }
}
# Probe every explicit matrix role, not just a representative comment.
foreach ($role in $selectionRoles | Where-Object Resolution -ceq 'opaque-raw') {
    Mutate-Case ("matrix rejects unreadable "+$role.Category+'/'+$role.Role) ('//Category[@Name="'+$role.Category+'"]/Color[@Name="'+$role.Role+'"]/Foreground') Source 'FF223249' 'selection-text'
}
Assert-Case (Get-PriorityIconRenderingDecision 'FF4D4D4D').Monochrome 'first grayscale byte inside the pinned lower boundary'
$imaging=@(Get-Content (Join-Path $PSScriptRoot 'evidence/priority-refinements/supplemental-evidence.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.Record.id -ceq 'PRIORITY-IMAGING' })
Assert-Case ($imaging.Count -eq 1 -and $imaging[0].Record.assembly.FileVersion -ceq '18.10.1155.63130') 'image evidence retains the pinned renderer'
$evidenceText=$imaging[0] | ConvertTo-Json -Depth 30
Assert-Case ($evidenceText -match 'Disabled grayscale is a separate operation' -and $evidenceText -match 'GrayscaleDIBits') 'disabled transformation remains separately evidenced, not inferred from enabled image context'
# Full unrelated-component fingerprints above include every disabled resource.
$publicFiles=@($packageCatalog.Packages | Where-Object Distribution -ceq 'public' | ForEach-Object Themes)
foreach ($file in $packageCatalog.DeferredPublicThemes) {
    $theme=@($catalog | Where-Object File -ceq $file)[0]
    Assert-Case ($policy.RefinementEnforcement[$theme.Name] -ceq 'enforced' -and $file -cnotin $publicFiles) ("enforced theme stays outside public packages: "+$theme.Name)
}
Write-Host "Priority refinement regression suite: $count cases passed."

& (Join-Path $PSScriptRoot 'Test-EditorSelection.Tests.ps1')

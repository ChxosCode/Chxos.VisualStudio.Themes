[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DebuggerHighlightContrast.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PriorityThemeRefinements.psm1')
Import-Module (Join-Path $PSScriptRoot 'EditorSelectionContrast.psm1')
$project=Split-Path -Parent $PSScriptRoot
$policy=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
$catalog=Get-Content (Join-Path $project 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json
$changes=Get-Content (Join-Path $PSScriptRoot 'evidence/debugger-highlights/changes.json') -Raw | ConvertFrom-Json
$preservation=Get-Content (Join-Path $PSScriptRoot 'evidence/debugger-highlights/preservation.json') -Raw | ConvertFrom-Json
$count=0
function Assert-Case([bool]$Value,[string]$Name) {
    if (-not $Value) { throw "FAILED: $Name" }
    $script:count++
}
$allowed=@(Get-DebuggerHighlightRoles)
Assert-Case ($allowed.Count -eq 18) 'Complete breakpoint and execution-state set'
$ids=@($changes | ForEach-Object { $_.File+'/'+($_.Key -join '/') })
Assert-Case (($ids | Sort-Object -Unique).Count -eq $changes.Count) 'Unique change entries'
foreach ($theme in $catalog) {
    [xml]$xml=Get-Content (Join-Path $project $theme.File) -Raw
    $rows=@(Test-DebuggerHighlightContrast $xml $policy)
    Assert-Case ($rows.Count -eq $allowed.Count -and @($rows | Where-Object Status -ne 'passed').Count -eq 0) "$($theme.Name) all debugger states pass"
    foreach ($row in $rows) {
        $keys=@($row.SyntaxMeasurements | ForEach-Object { $_.Category+'/'+$_.Role })
        Assert-Case ($row.SyntaxMeasurements.Count -eq 69 -and ($keys | Sort-Object -Unique).Count -eq $keys.Count) "$($theme.Name) complete deduplicated matrix for $($row.Role)"
        Assert-Case ($row.EvidenceAssessment -eq 'unresolved' -and $row.RuntimeAcceptance -eq 'pending') 'Source pass does not imply runtime acceptance'
    }
    Restore-EditorSelectionBaseline $xml $theme.File
    foreach ($change in @($changes | Where-Object File -ceq $theme.File)) {
        Assert-Case ($change.Key[0] -ceq 'Text Editor MEF Items' -and $change.Key[1] -cin $allowed -and ($change.Key[2] -ceq 'Background' -or ($theme.File -ceq 'Aquatoxic.vstheme' -and $change.Key[1] -like 'Breakpoint*' -and $change.Key[2] -ceq 'Foreground'))) 'Bounded change allowlist'
        $node=$xml.SelectSingleNode('//Category[@Name="'+$change.Key[0]+'"]/Color[@Name="'+$change.Key[1]+'"]/'+$change.Key[2])
        Assert-Case ($null -ne $node -and $node.Type -ceq $change.Type -and $node.Source -ceq $change.After) 'Exact reviewed assignment'
        $node.SetAttribute('Source',$change.Before)
    }
    # Restore the approved changes in memory, then compare every typed component.
    # This preserves disabled markers, glyph resources, syntax, and all other fills.
    $lines=@(foreach ($category in $xml.Themes.Theme.Category) { foreach ($color in $category.Color) { foreach ($part in $color.ChildNodes | Where-Object NodeType -eq Element) {
        @($category.Name,$color.Name,$part.LocalName,$part.Type,$part.Source) -join '|'
    } } })
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")+"`n"))).Replace('-','') } finally { $sha.Dispose() }
    $baseline=$preservation | Where-Object File -ceq $theme.File
    Assert-Case ($hash -ceq $baseline.TypedComponentsSha256) "$($theme.Name) unrelated components preserved"
}
[xml]$foundation=Get-Content (Join-Path $project 'Foundation.vstheme') -Raw
function Reject-Mutation([string]$Name,[string]$XPath,[string]$Attribute,[string]$Value) {
    [xml]$copy=$foundation.OuterXml
    $copy.SelectSingleNode($XPath).SetAttribute($Attribute,$Value)
    Assert-Case (@(Test-DebuggerHighlightContrast $copy $policy | Where-Object Status -ne 'passed').Count -gt 0) $Name
}
foreach ($role in $allowed) {
    Reject-Mutation "$role alpha cannot mask bright RGB" ('//Color[@Name="'+$role+'"]/Background') Source '66F87171'
}
Reject-Mutation 'Bright opaque fill rejected' '//Color[@Name="Current Statement"]/Background' Source 'FFF0E010'
Reject-Mutation 'Invisible fill rejected' '//Color[@Name="Current Statement"]/Background' Source 'FF0D0D0F'
Reject-Mutation 'Automatic fill unresolved' '//Color[@Name="Current Statement"]/Background' Type 'CT_AUTOMATIC'
Reject-Mutation 'Explicit text unreadable' '//Color[@Name="Current Statement"]/Foreground' Source 'FF213147'
Reject-Mutation 'Inherited explicit marker text unresolved' '//Color[@Name="Current Statement"]/Foreground' Type 'CT_INVALID'
Reject-Mutation 'Documentation comments covered' '//Color[@Name="xml doc comment - text"]/Foreground' Source 'FF213147'
Reject-Mutation 'Automatic syntax unresolved' '//Color[@Name="keyword - control"]/Foreground' Type 'CT_AUTOMATIC'
Reject-Mutation 'Inherited member base is resolved' '//Category[@Name="Text Editor Text Manager Items"]/Color[@Name="Plain Text"]/Foreground' Source 'FF213147'
Reject-Mutation 'Record class base is resolved' '//Color[@Name="class name"]/Foreground' Source 'FF213147'
Reject-Mutation 'Record struct base is resolved' '//Color[@Name="struct name"]/Foreground' Source 'FF213147'
Reject-Mutation 'Member inheritance retained' '//Color[@Name="field name"]/Foreground' Type 'CT_RAW'
Reject-Mutation 'Punctuation outside selection matrix covered' '//Color[@Name="HTML Operator"]/Foreground' Source 'FF213147'
[xml]$missing=$foundation.OuterXml
$node=$missing.SelectSingleNode('//Color[@Name="Current Statement"]/Background')
[void]$node.ParentNode.RemoveChild($node)
Assert-Case (@(Test-DebuggerHighlightContrast $missing $policy | Where-Object Status -eq 'unresolved').Count -gt 0) 'Missing component cannot pass'
Write-Host "$count debugger highlight regression cases passed. Runtime acceptance remains pending."

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ContextualContrast.psm1') -Force
$count = 0
function Assert-Case([bool] $Condition, [string] $Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:count++
}
Assert-Case ((Get-ContextualContrast 'FFFFFFFF' @('FF000000')) -eq 21) 'black/white'
Assert-Case ((Get-ContextualContrast 'FF123456' @('FF123456')) -eq 1) 'opaque collision'
Assert-Case ((Get-ContextualContrast '00000000' @('FF123456')) -eq 1) 'transparent content'
$layered = Get-ContextualContrast '66B6FF2E' @('66B6FF2E','FF0D121A')
Assert-Case ([Math]::Abs($layered - 2.033608) -lt 0.000001) 'fractional layered alpha'
$threw = $false
try { Get-ContextualContrast 'FFFFFFFF' @('66123456') | Out-Null } catch { $threw = $true }
Assert-Case $threw 'incomplete underlay rejected'
# These two values straddle 4.5. Never round a failing result up to the threshold.
Assert-Case ((Get-ContextualContrast 'FF767676' @('FFFFFFFF')) -ge 4.5) 'threshold passing side'
Assert-Case ((Get-ContextualContrast 'FF777777' @('FFFFFFFF')) -lt 4.5) 'threshold failing side'
$registry = Get-Content (Join-Path $PSScriptRoot 'ContextualRelationships.json') -Raw | ConvertFrom-Json
$themePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Amberroot.vstheme'
foreach ($probe in @(
    @{ Category='InfoBar'; Role='Hyperlink'; Component='Foreground'; Source='FF36382D' },
    @{ Category='TreeView'; Role='SelectedItemActiveGlyph'; Component='Background'; Source='00000000' },
    @{ Category='Output Window'; Role='urlformat'; Component='Foreground'; Source='FF000000' },
    @{ Category='ThemedDialog'; Role='ActionButtonTextActive'; Component='Background'; Source='FFB88935' },
    @{ Category='InfoBar'; Role='CloseButtonHoverGlyph'; Component='Background'; Source='00000000' }
)) {
    [xml]$theme = [IO.File]::ReadAllText($themePath)
    $node = $theme.SelectSingleNode("/Themes/Theme/Category[@Name='$($probe.Category)']/Color[@Name='$($probe.Role)']/$($probe.Component)")
    $node.Source = $probe.Source
    $entry = @($registry | Where-Object { $_.foreground[0] -ceq $probe.Category -and $_.foreground[1] -ceq $probe.Role })
    $results = @(Test-ContextualRelationships $theme $entry)
    Assert-Case ($results.Count -eq 1 -and $results[0].Status -ceq 'failed') "mutation: $($probe.Category)/$($probe.Role)"
}
[xml]$theme = [IO.File]::ReadAllText($themePath)
$entry = $registry[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$entry.foreground[1] = 'missing-role'
Assert-Case ((Test-ContextualRelationships $theme @($entry)).Status -ceq 'invalid') 'missing role'
$entry = $registry[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$entry.minimum = 1
Assert-Case ((Test-ContextualRelationships $theme @($entry)).Status -ceq 'invalid') 'weakened threshold rejected'
$entry = $registry[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$entry.bases = @(@('Shell','DoesNotExist','Background'))
Assert-Case ((Test-ContextualRelationships $theme @($entry)).Status -ceq 'invalid') 'wrong underlay reference'
$entry = $registry[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$entry.disposition = 'unresolved'
Assert-Case ((Test-ContextualRelationships $theme @($entry)).Status -ceq 'unresolved') 'unresolved is not a pass'
$theme.SelectSingleNode("/Themes/Theme/Category[@Name='ThemedDialog']/Color[@Name='ActionButtonTextActive']/Background").Type='CT_AUTOMATIC'
Assert-Case ((Test-ContextualRelationships $theme @($entry)).Status -ceq 'unresolved') 'unresolved automatic component is not treated as raw'
[xml]$aquatoxic = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Aquatoxic.vstheme'))
foreach ($id in @('F06-059','F06-060')) {
    $entry = $registry | Where-Object id -ceq $id
    $node = $aquatoxic.SelectSingleNode("/Themes/Theme/Category[@Name='Text Editor MEF Items']/Color[@Name='$($entry.foreground[1])']")
    $node.Foreground.Source='FF001D20'
    Assert-Case ((Test-ContextualRelationships $aquatoxic @($entry)).Status -ceq 'failed') "$id text on editor collision"
    $node.Foreground.Source='FFE6FFFF'
    $before = (Test-ContextualRelationships $aquatoxic @($entry)).Ratio
    $node.Background.Source='FFFFFFFF'
    $after = (Test-ContextualRelationships $aquatoxic @($entry)).Ratio
    Assert-Case ($before -eq $after) "$id border is not the text underlay"
}
Write-Host "All $count contextual contrast cases pass."

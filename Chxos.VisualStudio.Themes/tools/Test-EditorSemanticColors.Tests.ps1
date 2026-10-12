[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PriorityThemeRefinements.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EditorSurfaceContrast.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ContextualContrast.psm1')
$project=Split-Path -Parent $PSScriptRoot
$policy=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
$surfaces=Get-Content (Join-Path $PSScriptRoot 'EditorSurfacePolicy.json') -Raw | ConvertFrom-Json
$catalog=Get-Content (Join-Path $project 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json
$count=0
function Assert-Case([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:count++; Write-Host "PASS: $Name"
}
$newFamilies=@('Struct','Interface','Control','Directive')
$roles=@($newFamilies | ForEach-Object { $policy.CoreSyntaxFamilyRoles[$_] })
foreach ($theme in $catalog) {
    [xml]$xml=Get-Content (Join-Path $project $theme.File) -Raw
    $parts=@{}
    foreach ($cat in $xml.Themes.Theme.Category) { foreach ($color in $cat.Color) { $parts[$cat.Name+'/'+$color.Name]=$color } }
    $anchors=$policy.CoreSyntaxThemeAnchors[$theme.Name]
    foreach ($family in $newFamilies) {
        foreach ($role in $policy.CoreSyntaxFamilyRoles[$family]) {
            $node=$parts[$role.Category+'/'+$role.Role]
            Assert-Case ($node.Foreground.Type -ceq 'CT_RAW' -and $node.Foreground.Source -ceq $anchors[$family]) "$($theme.Name): explicit $($role.Role) anchor"
        }
        foreach ($other in $anchors.Keys | Where-Object { $_ -cne $family }) {
            Assert-Case ((Get-PriorityColorDistance $anchors[$family] $anchors[$other])+0.000001 -ge $policy.CoreSyntaxDistanceMinimum) "$($theme.Name): $family distinct from $other"
        }
    }
    $selection=@(Test-PriorityThemeRefinements $xml $policy | Where-Object { $_.Check -eq 'selection-text' -and ($_.Component -match '/(struct name|enum name|interface name|type parameter name|keyword - control|RazorDirective|RazorTransition|record class name|record struct name)/') })
    $changedSelection=@($selection | Where-Object { $_.Component -notmatch '/record class name/' })
    Assert-Case ($selection.Count -eq 18 -and @($changedSelection | Where-Object Status -ne 'passed').Count -eq 0) "$($theme.Name): new classifications and inherited record structs retain both selection contrasts"
    Assert-Case (@($selection | Where-Object { $_.Component -match '/record class name/' -and $_.Foreground -ceq $anchors.Type -and $_.Resolution -ceq 'inherited-class' }).Count -eq 2) "$($theme.Name): record class retains existing class color and its reported contrast status"
    $surfaceResults=@(Test-EditorSurfaceContrast $xml $surfaces $roles)
    Assert-Case (@($surfaceResults | Where-Object Status -ne 'validated').Count -eq 0) "$($theme.Name): semantic colors retain diff, Peek and other registered surface contrast"
    $razorBackground=$parts['Text Editor MEF Items/RazorCode'].Background
    $razorRatios=@($newFamilies | ForEach-Object { Get-ContextualContrast -Foreground $anchors[$_] -Layers @([string]$razorBackground.Source) })
    Assert-Case ($razorBackground.Type -ceq 'CT_RAW' -and $razorBackground.Source -cmatch '^FF[0-9A-F]{6}$' -and @($razorRatios | Where-Object { $_ -lt 4.5 }).Count -eq 0) "$($theme.Name): optional Razor code background retains new syntax contrast"
    foreach ($role in @('record class name','record struct name','field name','property name','event name','namespace name','enum member name')) {
        Assert-Case ($parts['Text Editor MEF Items/'+$role].Foreground.Type -ceq 'CT_INVALID') "$($theme.Name): $role retains inheritance"
    }
}
[xml]$foundation=Get-Content (Join-Path $project 'Foundation.vstheme') -Raw
foreach ($role in @('struct name','interface name','keyword - control','RazorDirective','RazorTransition')) {
    [xml]$copy=$foundation.OuterXml
    $copy.SelectSingleNode('//Color[@Name="'+$role+'"]/Foreground').Source='FF223249'
    Assert-Case (@(Test-PriorityThemeRefinements $copy $policy | Where-Object { $_.Check -eq 'selection-text' -and $_.Enforced -and $_.Status -eq 'failed' }).Count -gt 0) "unreadable $role is rejected"
}
foreach ($role in @('record class name','record struct name')) {
    [xml]$copy=$foundation.OuterXml
    $copy.SelectSingleNode('//Color[@Name="'+$role+'"]/Foreground').Type='CT_AUTOMATIC'
    Assert-Case (@(Test-PriorityThemeRefinements $copy $policy | Where-Object { $_.Check -eq 'selection-text' -and $_.Status -eq 'unresolved' }).Count -eq 2) "$role automatic value cannot masquerade as inheritance"
}
$fixture=Join-Path $PSScriptRoot 'VisualAuditFixture'
foreach ($file in @('EditorSemantics.cs','EditorSemantics.razor')) {
    $text=Get-Content (Join-Path $fixture $file) -Raw
    Assert-Case ($text.Contains('ElementReference') -and $text.Contains('IJSObjectReference') -and $text.Contains('Task') -and $text.Contains('await') -and $text.Contains('return')) "$file contains semantic review examples"
}
Write-Host "Editor semantic regression suite: $count cases passed."

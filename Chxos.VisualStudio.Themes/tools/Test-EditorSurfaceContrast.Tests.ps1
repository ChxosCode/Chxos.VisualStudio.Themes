[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'EditorSurfaceContrast.psm1') -Force
$policy = Get-Content (Join-Path $PSScriptRoot 'EditorSurfacePolicy.json') -Raw | ConvertFrom-Json
$roles = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
$project = Split-Path -Parent $PSScriptRoot
$count = 0
foreach ($file in Get-ChildItem $project -Filter '*.vstheme') {
    $theme = [xml](Get-Content $file.FullName -Raw)
    $results = @(Test-EditorSurfaceContrast $theme $policy $roles.EditorSyntaxFamilies)
    if ($results.Count -ne 52 -or @($results | Where-Object Status -eq 'failed').Count) { throw "Editor surface baseline failed: $($file.Name)." }
    $count++
}
foreach ($case in @(
    @{ Role='deltadiff.add.line'; Component='Background'; Source='4734D399'; Expected='opaque CT_RAW' },
    @{ Role='deltadiff.add.line'; Component='Background'; Source='FF34D399'; Expected='Harsh editor fill' },
    @{ Role='deltadiff.remove.word'; Component='Background'; Source='FFFB7185'; Expected='Harsh editor fill' },
    @{ Role='MarkerFormatDefinition/HighlightedReference'; Component='Background'; Source='14F27CAF'; Expected='opaque CT_RAW' },
    @{ Role='MarkerFormatDefinition/HighlightedDefinition'; Component='Background'; Source='FF34D399'; Expected='Harsh editor fill' },
    @{ Role='deltadiff.overview.color'; Component='Foreground'; Source='FFC9C7DC'; Expected='Diff hatching' },
    @{ Role='deltadiff.overview.color'; Component='Foreground'; Source='FF090C17'; Expected='Diff hatching' },
    @{ Role='deltadiff.add.word'; Component='Foreground'; Source='FF123733'; Expected='word border' },
    @{ Role='mergeEditor.AcceptedSimilarLine'; Component='Background'; Source='FF34D399'; Expected='Harsh editor fill' },
    @{ Role='Peek Highlighted Text'; Component='Background'; Source='668068E8'; Expected='opaque CT_RAW' }
)) {
    $theme = [xml](Get-Content (Join-Path $project 'Cosmora.vstheme') -Raw)
    $category = $theme.Themes.Theme.Category | Where-Object Name -ceq 'Text Editor MEF Items'
    $node = $category.Color | Where-Object Name -ceq $case.Role
    $node.($case.Component).Source = $case.Source
    $failures = @(Test-EditorSurfaceContrast $theme $policy $roles.EditorSyntaxFamilies | Where-Object Status -eq 'failed')
    if (-not @($failures | Where-Object Detail -like "*$($case.Expected)*").Count) { throw "Mutation accepted: $($case.Role)/$($case.Source)." }
    $count++
}
$theme = [xml](Get-Content (Join-Path $project 'Cosmora.vstheme') -Raw)
$node = ($theme.Themes.Theme.Category | Where-Object Name -ceq 'Text Editor MEF Items').Color | Where-Object Name -ceq 'deltadiff.add.word'
$node.Foreground.Type = 'CT_INVALID'
if (-not @(Test-EditorSurfaceContrast $theme $policy $roles.EditorSyntaxFamilies | Where-Object Status -eq 'failed').Count) { throw 'Inherited border accepted as explicit RGB.' }
$count++
foreach ($categoryName in @('Output Window','Find Results')) {
    $theme = [xml](Get-Content (Join-Path $project 'Cosmora.vstheme') -Raw)
    $node = ($theme.Themes.Theme.Category | Where-Object Name -ceq $categoryName).Color | Where-Object Name -ceq 'Selected Text'
    $node.Background.Source = '66F472B6'
    if (-not @(Test-EditorSurfaceContrast $theme $policy $roles.EditorSyntaxFamilies | Where-Object Status -eq 'failed').Count) { throw "Pane source alpha accepted: $categoryName." }
    $count++
}
Write-Host "Editor surface regression suite: $count cases passed."

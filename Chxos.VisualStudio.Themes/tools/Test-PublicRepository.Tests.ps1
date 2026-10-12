[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$root=Split-Path -Parent $project
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
$catalog=Read-PackageCatalog
$count=0
function Assert-Ignored([string]$Path,[bool]$Expected) {
    & git -C $root check-ignore --no-index -q -- $Path
    $code=$LASTEXITCODE
    if ($code -notin @(0,1) -or (($code -eq 0) -ne $Expected)) { throw "Unexpected Git eligibility: $Path" }
    $script:count++
}
function Assert-PublicFile([string]$Repository,[string]$Path) {
    if ([IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe dependency path: $Path" }
    if (-not (Test-Path -LiteralPath (Join-Path $Repository $Path) -PathType Leaf)) { throw "Missing public dependency: $Path" }
    & git -C $Repository check-ignore --no-index -q -- $Path
    if ($LASTEXITCODE -eq 0) { throw "Ignored public dependency: $Path" }
    if ($LASTEXITCODE -ne 1) { throw 'Git dependency check failed.' }
}
function Assert-NoIgnoredTrackedFiles([string]$Repository) {
    $ignored=@(& git -C $Repository ls-files --cached --ignored --exclude-standard -z)
    if ($LASTEXITCODE -ne 0) { throw 'Git index check failed.' }
    if ($ignored.Count) { throw 'Ignored files are still tracked; remove private/generated entries from the index before publication.' }
}
function Assert-Rejected([scriptblock]$Action,[string]$Reason) {
    $rejected=$false
    try { & $Action } catch {
        if (-not $_.Exception.Message.Contains($Reason)) { throw }
        $rejected=$true
    }
    if (-not $rejected) { throw "Expected rejection: $Reason" }
    $script:count++
}
Assert-NoIgnoredTrackedFiles $root
$count++
foreach ($name in $catalog.DeferredPublicThemes) { Assert-Ignored "Chxos.VisualStudio.Themes/$name" $true }
$public=@($catalog.Packages | Where-Object Distribution -ceq 'public' | ForEach-Object Themes)
foreach ($name in $public) { Assert-Ignored "Chxos.VisualStudio.Themes/$name" $false }
foreach ($path in @('docs/audits/report.md','docs/audits/evidence/example.json','docs/images/capture.png','artifacts/test.log','Chxos.VisualStudio.Themes/assets/source/preview.svg',
    '.local/tools/probe.ps1','.local/notes.md','Chxos.VisualStudio.Themes/node_modules/sharp/package.json','Chxos.VisualStudio.Themes/.npm/cache','Chxos.VisualStudio.Themes/.npm-cache/cache')) { Assert-Ignored $path $true }
Assert-Ignored 'docs/screenshots/example.png' $false
foreach ($path in @('authoring/Components.json','authoring/Palettes.json','authoring/ThemeCatalog.json','authoring/PackageCatalog.json')) { Assert-Ignored "Chxos.VisualStudio.Themes/$path" $false }
# These consumers must work in a public checkout without historical audit files,
# local probes, generated caches, or implicit asset-renderer installations.
$required=@('Chxos.VisualStudio.Themes.slnx','global.json','LICENSE.txt')
$required+=@('Chxos.VisualStudio.Themes.csproj','packages.lock.json','ThemeCatalog.props','PackageCatalog.props',
    'package.json','package-lock.json','packaging/manifest.template.xml',
    'authoring/Components.json','authoring/Palettes.json','authoring/ThemeCatalog.json','authoring/PackageCatalog.json',
    'tools/Build-ThemePackages.ps1','tools/Generate-Themes.ps1','tools/Generate-ThemePackages.ps1','tools/Test-VsixPackage.ps1',
    'tools/PackageBuildTest.Common.ps1','tools/PublicArtifacts.psm1','tools/Stage-PublicArtifacts.ps1','tools/Test-PublicArtifacts.Tests.ps1',
    'tools/VisualAudit.Common.psm1','tools/PackageCatalog.psm1','tools/RuntimeAcceptance.psm1','tools/RuntimeScenarios.json',
    'tools/Invoke-ThemeVisualAudit.ps1','tools/Invoke-PackageLifecycle.ps1','tools/New-PackageUpgradeFixture.ps1','tools/Test-ReleaseReadiness.ps1',
    'tools/Test-ThemeContrast.ps1','tools/ThemeRolePolicy.psd1','tools/RenderingContracts.psm1','tools/RenderingContracts.json',
    'tools/ContextualContrast.psm1','tools/ContextualRelationships.json','tools/ComponentInventory.json',
    'tools/EditorSelectionContrast.psm1','tools/EditorSelectionPolicy.json','tools/Test-EditorSelection.Tests.ps1','tools/evidence/editor-selection/changes.json','tools/DebuggerHighlightContrast.psm1','tools/evidence/debugger-highlights/changes.json','tools/evidence/debugger-highlights/preservation.json',
    'tools/EditorSurfaceContrast.psm1','tools/EditorSurfacePolicy.json','tools/PriorityThemeRefinements.psm1','tools/Render-PackageAssets.cjs',
    'tools/VisualAuditFixture/VisualAuditFixture.slnx','tools/VisualAuditFixture/VisualAuditFixture.csproj',
    'tools/VisualAuditFixture/ThemeSample.cs','tools/VisualAuditFixture/ThemeSample.razor',
    'tools/VisualAuditFixture/EditorSemantics.cs','tools/VisualAuditFixture/EditorSemantics.razor',
    'tools/VisualAuditFixture/CppSyntaxSample.cpp','tools/VisualAuditFixture/Diff/Before.cs','tools/VisualAuditFixture/Diff/After.cs',
    'tools/evidence/deferred-refinements/changes.json','tools/evidence/editor-semantics/preservation.json','tools/evidence/editor-semantics/change-register.json') | ForEach-Object { 'Chxos.VisualStudio.Themes/'+$_ }
foreach ($package in $catalog.Packages) {
    foreach ($asset in @($package.Icon,$package.PreviewImage)) {
        $required+='Chxos.VisualStudio.Themes/'+$asset
        $required+='Chxos.VisualStudio.Themes/'+[IO.Path]::ChangeExtension($asset,'svg')
    }
    $required+='Chxos.VisualStudio.Themes/packaging/generated/'+$package.Key+'/source.extension.vsixmanifest'
}
foreach ($file in $public) { $required+='Chxos.VisualStudio.Themes/'+$file }
# Derive CI entry points as well, so newly added suites cannot silently be ignored.
foreach ($workflowFile in Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -Filter '*.yml' -File) {
    $required+='.github/workflows/'+$workflowFile.Name
    $workflow=Get-Content -LiteralPath $workflowFile.FullName -Raw
    foreach ($match in [regex]::Matches($workflow,'[A-Za-z0-9.-]+\.(?:ps1|psm1)')) { $required+='Chxos.VisualStudio.Themes/tools/'+$match.Value }
}
foreach ($path in @($required | Sort-Object -Unique)) { Assert-PublicFile $root $path; $count++ }
$node=Get-Content (Join-Path $project 'package.json') -Raw | ConvertFrom-Json
$lockText=Get-Content (Join-Path $project 'package-lock.json') -Raw
# npm's root package uses an empty key, unsupported by PS 5.1's PSCustomObject JSON conversion.
if ($PSVersionTable.PSVersion.Major -ge 6) { $lock=ConvertFrom-Json $lockText -AsHashtable }
else {
    Add-Type -AssemblyName System.Web.Extensions
    $lock=(New-Object System.Web.Script.Serialization.JavaScriptSerializer).DeserializeObject($lockText)
}
if ($node.private -ne $true -or $lock['packages']['node_modules/sharp']['version'] -cne $node.devDependencies.sharp -or
    $lock['packages']['']['devDependencies']['sharp'] -cne $node.devDependencies.sharp -or -not $lock['packages']['node_modules/sharp']['integrity']) {
    throw 'Asset renderer must remain private with a matching, integrity-locked sharp dependency.'
}
$count++
$registry=Get-Content (Join-Path $PSScriptRoot 'RenderingContracts.json') -Raw | ConvertFrom-Json
if ($registry.AuditSnapshot.Path -cne 'Chxos.VisualStudio.Themes/tools/evidence/rendering-audit') { throw 'Current registry depends on private audit files.' }
$evidence=@($registry.AuditSnapshot.Files | ForEach-Object { $registry.AuditSnapshot.Path+'/'+$_.Name })+@($registry.EvidenceSources | ForEach-Object Path)
foreach ($path in $evidence) {
    Assert-PublicFile $root $path
    $count++
    $text=Get-Content -LiteralPath (Join-Path $root $path) -Raw
    if ($text -match '(?i)[A-Z]:(?:\\+|/)+Users(?:\\+|/)' -or $text -match '"(?:localArtifact|retainedEvidence)"\s*:') { throw "Private machine or retained-artifact path in public evidence: $path" }
    $count++
}
Import-Module (Join-Path $PSScriptRoot 'RenderingContracts.psm1') -Force
$context=Read-RenderingContracts
$errors=@(Test-RenderingContracts $context)
if ($errors.Count) { throw ($errors -join "`n") }
$count++
# Exercise actual failures in a disposable Git repository, never this index.
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$fixture=Join-Path $tempRoot ('chxos-public-boundary-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try {
    & git -C $fixture init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git initialization failed.' }
    [IO.File]::WriteAllText((Join-Path $fixture '.gitignore'), ".local/`nnode_modules/`n")
    [IO.File]::WriteAllText((Join-Path $fixture 'required.psm1'), '# public dependency')
    Assert-PublicFile $fixture 'required.psm1'; $count++
    Assert-Rejected { Assert-PublicFile $fixture 'missing.psm1' } 'Missing public dependency'
    Assert-Rejected { Assert-PublicFile $fixture '../outside.psm1' } 'Unsafe dependency path'
    Assert-Rejected { Assert-PublicFile $fixture (Join-Path $tempRoot 'outside.psm1') } 'Unsafe dependency path'
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture '.local'))
    [IO.File]::WriteAllText((Join-Path $fixture '.local/probe.ps1'), '# private probe')
    Assert-Rejected { Assert-PublicFile $fixture '.local/probe.ps1' } 'Ignored public dependency'
    Assert-NoIgnoredTrackedFiles $fixture; $count++
    & git -C $fixture add --force -- .local/probe.ps1
    if ($LASTEXITCODE -ne 0) { throw 'Fixture private-file staging failed.' }
    Assert-Rejected { Assert-NoIgnoredTrackedFiles $fixture } 'Ignored files are still tracked'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notlike 'chxos-public-boundary-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "Public repository regression suite: $count cases passed."

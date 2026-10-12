[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
$count=0
function Case([string]$Name,[scriptblock]$Action) { & $Action; $script:count++; Write-Host "PASS: $Name" }
function Reject([scriptblock]$Action,[string]$Reason) {
    $failure=$null
    try { & $Action } catch { $failure=$_.Exception.Message }
    if (-not $failure -or $failure -notmatch $Reason) { throw "Expected '$Reason'; got '$failure'." }
}
function Assert-NoPublication([string]$Text) {
    if ($Text -notmatch '(?m)^permissions:\n  contents: read\n' -or $Text -match '(?m)^\s+\w[\w-]*: write\s*$|secrets:|secrets\.\w|gh release|gh api|git push|VsixPublisher|vsce publish|softprops/action-gh-release|actions/create-release') { throw 'Release preparation must not grant write access or publish.' }
    if ($Text -match '(?m)^  (push|pull_request|release|schedule|workflow_run):') { throw 'Release preparation must not run automatically.' }
}
function Assert-Wrapper([string]$Text,[string]$Key) {
    Assert-NoPublication $Text
    if ($Text -notmatch '(?m)^  workflow_dispatch:\n' -or $Text -notmatch '(?m)^      version:\n' -or $Text -notmatch '(?m)^        required: true\n' -or $Text -notmatch '(?m)^        type: string\n') { throw 'Manual product preparation requires an explicit version.' }
    if ($Text -notmatch '(?m)^    uses: \./\.github/workflows/release-product.yml\n' -or $Text -notmatch "(?m)^      package: $Key\n" -or $Text -notmatch '(?m)^      version: \x24\{\{ inputs.version \}\}\n') { throw 'Wrapper must select its own product and pass the expected version.' }
}
function Assert-Shared([string]$Text) {
    Assert-NoPublication $Text
    if ($Text -notmatch '(?m)^  workflow_call:\n' -or $Text -match '(?m)^  workflow_dispatch:') { throw 'Shared preparation must be callable only.' }
    foreach ($step in @('Get-ReleaseTarget.ps1 -Package $env:RELEASE_PACKAGE -Version $env:RELEASE_VERSION -Ref $env:GITHUB_REF',
        'Build-ThemePackages.ps1 -Package $env:RELEASE_PACKAGE',
        'Stage-PublicArtifacts.ps1 -Package $env:RELEASE_PACKAGE -Check',
        'Test-PublicRepository.Tests.ps1','Test-VsixEligibility.Tests.ps1')) {
        if (-not $Text.Contains($step)) { throw 'Missing selected-product verification gate.' }
    }
    if ($Text.Contains('-AllPublic') -or $Text.Contains('-Package foundation,pinknoise,cosmora')) { throw 'Preparation must build only the selected product.' }
    $uploads=@([regex]::Matches($Text,'(?ms)^      - name: Upload .*?(?=^      - name:|\z)') | ForEach-Object Value)
    if ($uploads.Count -ne 1 -or ([regex]::Matches($Text,'uses: actions/upload-artifact@')).Count -ne 1) { throw 'Preparation requires exactly one artifact upload.' }
    $block=$uploads[0]
    if ($block -notmatch "if: \x24\{\{ success\(\) && steps.verify_candidate.outcome == 'success' \}\}" -or $Text -notmatch '(?m)^        id: verify_candidate\n') { throw 'Upload must depend on successful stage verification.' }
    $paths=@([regex]::Matches($block,'(?m)^            (.+)$') | ForEach-Object { $_.Groups[1].Value })
    $expected=@('artifacts/release-preparation/candidate/${{ inputs.package }}/${{ inputs.package }}.vsix',
        'artifacts/release-preparation/candidate/${{ inputs.package }}/candidate.json',
        'artifacts/release-preparation/candidate/${{ inputs.package }}/SHA256SUMS.txt')
    if (($paths -join '|') -cne ($expected -join '|') -or $block -notmatch 'if-no-files-found: error') { throw 'Upload must use the exact three-file allowlist.' }
    foreach ($match in [regex]::Matches($Text,'(?m)^\s+uses: actions/[^\n]+')) {
        if ($match.Value -notmatch '@[0-9a-f]{40}(?: |$)') { throw 'External actions must be commit-pinned.' }
    }
}
foreach ($key in @('foundation','pinknoise','cosmora')) {
    $spec=Get-ThemePackage -Package $key
    Case "$key accepts its catalog version on a branch and matching product tag" {
        foreach ($ref in @('refs/heads/main',"refs/tags/$key/v$($spec.Version)")) {
            $target=& (Join-Path $PSScriptRoot 'Get-ReleaseTarget.ps1') -Package $key -Version $spec.Version -Ref $ref
            if ($target.Identity -cne $spec.Identity) { throw 'Target identity differs.' }
        }
    }
    Case "$key rejects wrong version and wrong-product or generic tags" {
        Reject { & (Join-Path $PSScriptRoot 'Get-ReleaseTarget.ps1') -Package $key -Version '0.0.0' -Ref 'refs/heads/main' } 'does not match'
        foreach ($ref in @('refs/tags/other/v1.0.0',"refs/tags/v$($spec.Version)","refs/tags/$key/v0.0.0",'refs/pull/1/merge','refs/heads/')) {
            Reject { & (Join-Path $PSScriptRoot 'Get-ReleaseTarget.ps1') -Package $key -Version $spec.Version -Ref $ref } 'tag must match|requires a branch'
        }
    }
    $wrapper=(Get-Content -LiteralPath (Join-Path $root ".github/workflows/release-$key.yml") -Raw).Replace("`r`n","`n")
    Case "$key workflow is manual, read-only and product-scoped" { Assert-Wrapper $wrapper $key }
    Case "$key wrapper rejects cross-product routing" { Reject { Assert-Wrapper ($wrapper.Replace("package: $key",'package: all-dev')) $key } 'select its own product' }
}
Case 'release target rejects internal, unknown and nonexact keys' {
    foreach ($key in @('all-dev','unknown','Foundation','foundation; Write-Output injected')) {
        Reject { & (Join-Path $PSScriptRoot 'Get-ReleaseTarget.ps1') -Package $key -Version '1.0.0' -Ref 'refs/heads/main' } 'exact public product key'
    }
}
$shared=(Get-Content -LiteralPath (Join-Path $root '.github/workflows/release-product.yml') -Raw).Replace("`r`n","`n")
Case 'shared preparation has product gates and exact success-only artifact upload' { Assert-Shared $shared }
Case 'publication permissions regression rejected' { Reject { Assert-Shared ($shared.Replace('contents: read','contents: write')) } 'must not grant write' }
Case 'automatic tag dispatch regression rejected' { Reject { Assert-Shared ($shared.Replace("on:`n","on:`n  push:`n    tags: ['**']`n")) } 'must not run automatically' }
Case 'failure-path upload regression rejected' { Reject { Assert-Shared ($shared.Replace("success() && steps.verify_candidate.outcome == 'success'",'always()')) } 'successful stage verification' }
Case 'raw-evidence upload regression rejected' { Reject { Assert-Shared ($shared.Replace('candidate/${{ inputs.package }}/${{ inputs.package }}.vsix','**/*')) } 'exact three-file allowlist' }
Case 'version validation removal rejected' { Reject { Assert-Shared ($shared.Replace('Get-ReleaseTarget.ps1','Write-Output')) } 'Missing selected-product verification' }
Case 'shared scripts parse under Windows PowerShell' {
    foreach ($file in @('Get-ReleaseTarget.ps1','Stage-PublicArtifacts.ps1','PublicArtifacts.psm1')) {
        $tokens=$null; $errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw ($errors | Out-String) }
    }
}
Write-Host "Release workflow regression suite: $count cases passed."

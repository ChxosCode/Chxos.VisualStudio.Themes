[CmdletBinding()]
param([string]$VsixDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PublicArtifacts.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'VisualAudit.Common.psm1') -Force
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $VsixDirectory) { $VsixDirectory=Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/Release' }
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$fixture=Join-Path $tempRoot ('chxos-public-artifacts-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$count=0
function Case([string]$Name,[scriptblock]$Body) { & $Body; $script:count++; Write-Host "PASS: $Name" }
function Reject([scriptblock]$Body,[string]$Message) {
    $failure=$null
    try { & $Body } catch { $failure=$_.Exception.Message }
    if (-not $failure -or $failure -notmatch $Message) { throw "Expected '$Message'; got '$failure'." }
}
function Write-Report($Report,[string]$Path) { $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Report-Case([string]$Name,[scriptblock]$Mutation,[string]$Message) {
    Case $Name {
        $copy=$script:baseline | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        & $Mutation $copy
        $path=Join-Path $fixture 'report.json'; Write-Report $copy $path
        $destination=Join-Path $fixture ('rejected-'+[Guid]::NewGuid().ToString('N'))
        Reject { New-PublicArtifactStage $path $destination } $Message
        if (Test-Path -LiteralPath $destination) { throw 'Failed staging exposed uploadable output.' }
    }
}
function Stage-Case([string]$Name,[scriptblock]$Mutation,[string]$Message) {
    Case $Name {
        $destination=Join-Path $fixture ('check-'+[Guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $script:validStage -Destination $destination -Recurse
        & $Mutation $destination
        Reject { Test-PublicArtifactStage $destination } $Message
    }
}
function Assert-Workflow([string]$Text) {
    $steps=@([regex]::Matches($Text,'(?ms)^      - name:.*?(?=^      - name:|\z)') | ForEach-Object Value)
    $uploads=@($steps | Where-Object { $_ -match 'uses: actions/upload-artifact@' })
    if ($uploads.Count -ne 3 -or ([regex]::Matches($Text,'uses: actions/upload-artifact@')).Count -ne 3) { throw 'Unexpected upload count.' }
    foreach ($key in @('foundation','pinknoise','cosmora')) {
        $matches=@($uploads | Where-Object { $_ -match "name: $key-unqualified-candidate\s" })
        if ($matches.Count -ne 1) { throw 'Missing candidate upload.' }
        $block=$matches[0]
        if ($block -notmatch "if: \x24\{\{ success\(\) && steps\.verify_public\.outcome == 'success' \}\}") { throw 'Upload is not success-gated.' }
        $paths=@([regex]::Matches($block,'(?m)^            (.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
        $expected=@("artifacts/public-candidates/$key/$key.vsix","artifacts/public-candidates/$key/candidate.json","artifacts/public-candidates/$key/SHA256SUMS.txt")
        if (($paths -join '|') -cne ($expected -join '|') -or $block -notmatch 'path: \|' -or $block -notmatch 'if-no-files-found: error') { throw 'Upload path is outside the exact file allowlist.' }
    }
    if ($Text -notmatch '(?m)^        id: verify_public\r?$' -or $Text -notmatch 'Stage-PublicArtifacts.ps1 -Check -OutputDirectory ./artifacts/public-candidates') { throw 'Missing stage verification gate.' }
    if ($Text -notmatch 'Build-ThemePackages.ps1 -Package foundation,pinknoise,cosmora,all-dev') { throw 'Four-package build was reduced.' }
    if ($Text -notmatch 'timeout-minutes: 360') { throw 'Complete verification time budget was reduced.' }
    foreach ($suite in @('Test-PackageCleanBuild.Tests.ps1','Test-PackageBuildIsolation.Tests.ps1')) {
        if (-not $Text.Contains($suite+' -Package foundation,pinknoise,cosmora,all-dev')) { throw 'Four-package test scope was reduced.' }
    }

}
try {
    $packages=@()
    foreach ($spec in (Read-PackageCatalog).Packages) {
        $source=Join-Path $VsixDirectory "$($spec.Key)/$($spec.Key)-$($spec.Version).vsix"
        $dir=Join-Path $fixture "Release/$($spec.Key)/$($spec.Version)"
        [void][IO.Directory]::CreateDirectory($dir)
        $file=Join-Path $dir ([IO.Path]::GetFileName($source))
        Copy-Item -LiteralPath $source -Destination $file
        $packages+=@([pscustomobject]@{Key=$spec.Key;Identity=$spec.Identity;Version=$spec.Version;Distribution=$spec.Distribution;
            Themes=@(Get-PackageThemes $spec | Select-Object File,Name,Guid,Pkgdef);VsixPath=$file;VsixSha256=(Get-FileHash $file).Hash;
            PkgdefHashes=(Get-VsixPkgdefHashes $file);InspectionPassed=$true})
    }
    $script:baseline=[pscustomobject]@{SchemaVersion=1;Succeeded=$true;Configuration='Release';Packages=$packages;
        Commands=@(@{ExitCode=0;Arguments=@('private-sentinel')});GitStatus='private-sentinel';Failure=$null}
    $reportPath=Join-Path $fixture 'report.json'
    Write-Report $baseline $reportPath
    $script:validStage=Join-Path $fixture 'public'
    Case 'four-package evidence exports only three products and nine sanitized files' {
        New-PublicArtifactStage $reportPath $validStage
        Test-PublicArtifactStage $validStage
        $files=@(Get-ChildItem $validStage -Recurse -File)
        if ($files.Count -ne 9 -or @($files | Where-Object Name -match 'all-dev').Count) { throw 'Incorrect public membership.' }
        foreach ($file in $files | Where-Object Extension -ne '.vsix') {
            if ([IO.File]::ReadAllText($file.FullName) -match 'private-sentinel|VsixPath|GitStatus|Commands') { throw 'Unsanitized public metadata.' }
        }
        foreach ($spec in Get-PublicArtifactPackages) {
            $row=@($baseline.Packages | Where-Object Key -CEQ $spec.Key)[0]
            if ((Get-FileHash (Join-Path $validStage "$($spec.Key)/$($spec.Key).vsix")).Hash -cne $row.VsixSha256) { throw 'Staging changed VSIX bytes.' }
        }
    }
    Case 'existing output cannot be replaced or credited by a failed retry' {
        $before=(Get-FileHash (Join-Path $validStage 'foundation/foundation.vsix')).Hash
        Reject { New-PublicArtifactStage $reportPath $validStage } 'must be new'
        if ((Get-FileHash (Join-Path $validStage 'foundation/foundation.vsix')).Hash -cne $before) { throw 'Stale output was modified.' }
    }
    Case 'public-only successful report is accepted' {
        $r=$baseline|ConvertTo-Json -Depth 12|ConvertFrom-Json
        $r.Packages=@($r.Packages|Where-Object Distribution -CEQ 'public')
        Write-Report $r $reportPath
        New-PublicArtifactStage $reportPath (Join-Path $fixture 'public-only')
    }
    foreach ($key in @('foundation','pinknoise','cosmora')) {
        Case "$key single-product evidence exports only its three files" {
            $r=$baseline | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            $r.Packages=@($r.Packages | Where-Object Key -CEQ $key)
            Write-Report $r $reportPath
            $selected=Join-Path $fixture ('single-'+$key)
            New-PublicArtifactStage -BuildReportPath $reportPath -OutputDirectory $selected -Package $key
            Test-PublicArtifactStage -OutputDirectory $selected -Package $key
            $files=@(Get-ChildItem -LiteralPath $selected -Recurse -File)
            if ($files.Count -ne 3 -or (Get-FileHash (Join-Path $selected "$key/$key.vsix")).Hash -cne $r.Packages[0].VsixSha256) { throw 'Selected stage changed archive bytes or exported another product.' }
            Reject { Test-PublicArtifactStage -OutputDirectory $selected } 'unexpected entries'
            $other=if ($key -ceq 'foundation') { 'pinknoise' } else { 'foundation' }
            Reject { Test-PublicArtifactStage -OutputDirectory $selected -Package $other } 'unexpected entries'
            Reject { New-PublicArtifactStage -BuildReportPath $reportPath -OutputDirectory (Join-Path $fixture ('wrong-'+$key)) -Package $other } 'exactly the requested products'
        }
    }
    Case 'explicit selection rejects a report containing other products' {
        Write-Report $baseline $reportPath
        Reject { New-PublicArtifactStage -BuildReportPath $reportPath -OutputDirectory (Join-Path $fixture 'mixed') -Package foundation } 'exactly the requested products'
    }
    Case 'single-product report cannot bypass default three-product staging' {
        $r=$baseline | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $r.Packages=@($r.Packages | Where-Object Key -CEQ 'foundation')
        Write-Report $r $reportPath
        Reject { New-PublicArtifactStage -BuildReportPath $reportPath -OutputDirectory (Join-Path $fixture 'default-single') } 'Invalid package records'
    }
    Case 'explicit two-product export remains restricted to its requested products' {
        $r=$baseline | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $r.Packages=@($r.Packages | Where-Object { $_.Key -cin @('foundation','pinknoise') })
        Write-Report $r $reportPath
        $selected=Join-Path $fixture 'two-products'
        New-PublicArtifactStage -BuildReportPath $reportPath -OutputDirectory $selected -Package foundation,pinknoise
        Test-PublicArtifactStage -OutputDirectory $selected -Package foundation,pinknoise
        if (@(Get-ChildItem -LiteralPath $selected -Recurse -File).Count -ne 6) { throw 'Incorrect two-product export membership.' }
    }
    Case 'internal, unknown, duplicate and nonexact public selectors are rejected' {
        foreach ($selection in @(@('all-dev'),@('unknown'),@('Foundation'),@('foundation','foundation'))) {
            Reject { Get-PublicArtifactPackages -Package $selection } 'distinct public package keys'
        }
        Reject { Get-PublicArtifactPackages -Package @() } 'distinct public package keys'
    }
    Case 'selected stage rejects extra product and raw evidence files' {
        $selected=Join-Path $fixture 'single-foundation'
        Copy-Item -LiteralPath (Join-Path $validStage 'pinknoise/pinknoise.vsix') -Destination (Join-Path $selected 'extra.vsix')
        Reject { Test-PublicArtifactStage -OutputDirectory $selected -Package foundation } 'unexpected entries'
        Remove-Item -LiteralPath (Join-Path $selected 'extra.vsix')
        Set-Content -LiteralPath (Join-Path $selected 'raw.log') -Value 'private'
        Reject { Test-PublicArtifactStage -OutputDirectory $selected -Package foundation } 'unexpected entries'
    }
    Case 'missing output parent is rejected without creating directories' {
        $parent=Join-Path $fixture 'absent-parent'
        Reject { New-PublicArtifactStage $reportPath (Join-Path $parent 'stage') } 'parent directory first'
        if (Test-Path $parent) { throw 'Unrequested parent created.' }
    }
    Case 'junction output parent is rejected' {
        $link=Join-Path $fixture 'junction'
        try {
            [void](New-Item -ItemType Junction -Path $link -Target $validStage)
            Reject { New-PublicArtifactStage $reportPath (Join-Path $link 'nested') } 'reparse points'
        } finally {
            # Remove the junction only; the target remains available for subsequent tests.
            if ([IO.Path]::GetFullPath($link) -cne (Join-Path $fixture 'junction')) { throw 'Unsafe junction path.' }
            if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        }
    }
    Report-Case 'failed run' {param($r) $r.Succeeded=$false} 'successful Release'
    Report-Case 'string success flag' {param($r) $r.Succeeded='true'} 'successful Release'
    Report-Case 'Debug build' {param($r) $r.Configuration='Debug'} 'successful Release'
    Report-Case 'missing public member' {param($r) $r.Packages=@($r.Packages | Where-Object Key -ne 'pinknoise')} 'Missing public package'
    Report-Case 'duplicate package' {param($r) $r.Packages[1]=$r.Packages[0]} 'Invalid package records'
    Report-Case 'unknown package' {param($r) $r.Packages[3].Key='private'} 'Invalid package records'
    Report-Case 'wrong identity' {param($r) $r.Packages[0].Identity='private'} 'metadata does not match'
    Report-Case 'test-only version' {param($r) $r.Packages[0].Version='1.0.1'} 'metadata does not match'
    Report-Case 'internal distribution in public slot' {param($r) $r.Packages[0].Distribution='internal'} 'metadata does not match'
    Report-Case 'uninspected artifact' {param($r) $r.Packages[0].InspectionPassed=$false} 'metadata does not match'
    Report-Case 'wrong theme membership' {param($r) $r.Packages[0].Themes[0].Guid='{00000000-0000-0000-0000-000000000000}'} 'membership does not match'
    Report-Case 'cross-run artifact path' {param($r) $r.Packages[0].VsixPath=$r.Packages[1].VsixPath} 'outside the selected build'
    Report-Case 'wrong archive hash' {param($r) $r.Packages[0].VsixSha256='0'*64} 'Archive hash'
    Report-Case 'wrong compiled hash' {param($r) $r.Packages[0].PkgdefHashes.'Foundation.pkgdef'='0'*64} 'Compiled payload hashes'
    Report-Case 'failed nested command' {param($r) $r.Commands[0].ExitCode=1} 'unsuccessful commands'
    Report-Case 'missing nested command result' {param($r) $r.Commands[0].ExitCode=$null} 'unsuccessful commands'
    Stage-Case 'extra internal archive' {param($d) Copy-Item (Join-Path $d 'foundation/foundation.vsix') (Join-Path $d 'all-dev.vsix')} 'unexpected entries'
    Stage-Case 'private hidden file' {param($d) Set-Content (Join-Path $d '.private') 'private'} 'unexpected entries'
    Stage-Case 'unexpected empty directory' {param($d) [void][IO.Directory]::CreateDirectory((Join-Path $d 'raw-captures'))} 'unexpected entries'
    Stage-Case 'missing sidecar' {param($d) Remove-Item -LiteralPath (Join-Path $d 'foundation/candidate.json')} 'unexpected entries'
    Stage-Case 'wrong checksum' {param($d) Set-Content (Join-Path $d 'foundation/SHA256SUMS.txt') 'wrong'} 'Incorrect public checksum'
    Stage-Case 'private summary property' {param($d) $p=Join-Path $d 'foundation/candidate.json'; $s=Get-Content $p -Raw|ConvertFrom-Json; $s|Add-Member NoteProperty LocalPath 'private'; $s|ConvertTo-Json|Set-Content $p} 'unsanitized candidate summary'
    Stage-Case 'qualified status claim' {param($d) $p=Join-Path $d 'foundation/candidate.json'; $s=Get-Content $p -Raw|ConvertFrom-Json; $s.Status='Qualified'; $s|ConvertTo-Json|Set-Content $p} 'unsanitized candidate summary'
    Stage-Case 'cross-product archive replacement' {param($d) Copy-Item (Join-Path $d 'pinknoise/pinknoise.vsix') (Join-Path $d 'foundation/foundation.vsix') -Force} 'inspection failed'
    Case 'tampered archive with updated hash fails inspection before promotion' {
        $source=$baseline.Packages[0].VsixPath
        $original=[IO.File]::ReadAllBytes($source)
        try {
            $zip=[IO.Compression.ZipFile]::Open($source,[IO.Compression.ZipArchiveMode]::Update)
            try { [void]$zip.CreateEntry('private.log') } finally { $zip.Dispose() }
            $r=$baseline|ConvertTo-Json -Depth 12|ConvertFrom-Json
            $r.Packages[0].VsixSha256=(Get-FileHash $source).Hash
            Write-Report $r $reportPath
            $dest=Join-Path $fixture 'tampered-output'
            Reject {New-PublicArtifactStage $reportPath $dest} 'inspection failed'
            if (Test-Path $dest) { throw 'Partial stage promoted after failed inspection.' }
        } finally { [IO.File]::WriteAllBytes($source,$original) }
    }
    $workflow=Get-Content (Join-Path $root '.github/workflows/ci.yml') -Raw
    Case 'workflow keeps four packages and exact success-only uploads' { Assert-Workflow $workflow }
    Case 'workflow gates accept LF checkout' { Assert-Workflow ($workflow.Replace("`r`n","`n")) }
    Case 'workflow gates accept CRLF checkout' { Assert-Workflow ($workflow.Replace("`r`n","`n").Replace("`n","`r`n")) }
    Case 'short CI timeout rejected' { Reject { Assert-Workflow ($workflow.Replace('timeout-minutes: 360','timeout-minutes: 120')) } 'time budget' }
    Case 'failure-path upload regression rejected' { Reject { Assert-Workflow ($workflow.Replace("success() && steps.verify_public.outcome == 'success'",'always()')) } 'success-gated' }
    Case 'broad upload regression rejected' { Reject { Assert-Workflow ($workflow.Replace('artifacts/public-candidates/foundation/foundation.vsix','artifacts/ci/**/*')) } 'exact file allowlist' }
    Case 'internal upload regression rejected' { Reject { Assert-Workflow ($workflow+"`n      - name: Hidden upload`n        uses: actions/upload-artifact@bad`n") } 'upload count' }
    Case 'reduced package testing rejected' { Reject { Assert-Workflow ($workflow.Replace('-Package foundation,pinknoise,cosmora,all-dev','-Package foundation,pinknoise,cosmora')) } 'Four-package build' }
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'chxos-public-artifacts-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "Public artifact regression suite: $count cases passed."

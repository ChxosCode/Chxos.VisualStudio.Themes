Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'VisualAudit.Common.psm1') -Force

function Get-PublicArtifactPackages {
    param([string[]]$Package)
    $catalog=Read-PackageCatalog
    $public=@($catalog.Packages | Where-Object Distribution -CEQ 'public')
    # A new public product needs a deliberate upload-policy and workflow change.
    if ((@($public.Key | Sort-Object) -join '|') -cne 'cosmora|foundation|pinknoise') { throw 'Public artifact allowlist does not match the catalog.' }
    if ($PSBoundParameters.ContainsKey('Package')) {
        if (-not $Package -or @($Package | Select-Object -Unique).Count -ne $Package.Count -or @($Package | Where-Object { $_ -cnotin $public.Key }).Count) { throw 'Select distinct public package keys using their exact catalog names.' }
        return @($public | Where-Object { $_.Key -cin $Package })
    }
    return $public
}

function Assert-ArtifactPath([string]$Path) {
    # Reject junctions/symlinks in every existing ancestor, including the output parent.
    $item=Get-Item -LiteralPath ([IO.Path]::GetFullPath($Path)) -Force -ErrorAction Stop
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Artifact paths must not contain reparse points.' }
        if ($item -is [IO.FileInfo]) { $item=$item.Directory } else { $item=$item.Parent }
    }
}

function Assert-ArtifactInspection([string]$Path,[string]$Key) {
    $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try {
        $diagnostics=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-VsixPackage.ps1') -VsixPath $Path -Package $Key 2>&1 | Out-String
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$previous }
    if ($code -ne 0) { throw "Public artifact inspection failed for $Key. $diagnostics" }
}

function Get-PublicCandidateSummary($Spec,[string]$Path) {
    # Never copy free-form report fields, paths, command logs, or Git status.
    [ordered]@{
        SchemaVersion=1
        Status='Unqualified development candidate; not a release'
        Package=$Spec.Key
        Identity=$Spec.Identity
        Version=$Spec.Version
        Themes=@(Get-PackageThemes $Spec | ForEach-Object Name)
        FileName=$Spec.Key+'.vsix'
        Sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}

function Test-PublicArtifactStage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputDirectory,[string[]]$Package)
    $directory=[IO.Path]::GetFullPath($OutputDirectory)
    Assert-ArtifactPath $directory
    $selection=@{}
    if ($PSBoundParameters.ContainsKey('Package')) { $selection.Package=$Package }
    $specs=@(Get-PublicArtifactPackages @selection)
    $expected=@($specs | ForEach-Object { $_.Key; $_.Key+'/'+$_.Key+'.vsix'; $_.Key+'/candidate.json'; $_.Key+'/SHA256SUMS.txt' } | Sort-Object)
    $actual=@(Get-ChildItem -LiteralPath $directory -Force -Recurse | ForEach-Object {
        Assert-ArtifactPath $_.FullName
        $_.FullName.Substring($directory.TrimEnd('\','/').Length+1).Replace('\','/')
    } | Sort-Object)
    if (($expected -join '|') -cne ($actual -join '|')) { throw 'Public stage contains missing or unexpected entries.' }
    foreach ($spec in $specs) {
        $dir=Join-Path $directory $spec.Key
        $vsix=Join-Path $dir ($spec.Key+'.vsix')
        Assert-ArtifactInspection $vsix $spec.Key
        $expectedSummary=Get-PublicCandidateSummary $spec $vsix
        $summary=Get-Content -LiteralPath (Join-Path $dir 'candidate.json') -Raw | ConvertFrom-Json
        if (($summary | ConvertTo-Json -Depth 5 -Compress) -cne ($expectedSummary | ConvertTo-Json -Depth 5 -Compress)) { throw "Unexpected or unsanitized candidate summary for $($spec.Key)." }
        $checksum=[IO.File]::ReadAllText((Join-Path $dir 'SHA256SUMS.txt'))
        if ($checksum -cne ($expectedSummary.Sha256+'  '+$spec.Key+".vsix`n")) { throw "Incorrect public checksum for $($spec.Key)." }
    }
    Write-Host "Public artifact stage verified: $($specs.Count) unqualified candidates, $($specs.Count * 3) allowlisted files."
}

function New-PublicArtifactStage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BuildReportPath,[Parameter(Mandatory)][string]$OutputDirectory,[string[]]$Package)
    $output=[IO.Path]::GetFullPath($OutputDirectory)
    if (Test-Path -LiteralPath $output) { throw 'Public stage must be new; refusing existing or stale output.' }
    $parent=Split-Path -Parent $output
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Create the public stage parent directory first.' }
    Assert-ArtifactPath $parent
    $reportPath=(Resolve-Path -LiteralPath $BuildReportPath -ErrorAction Stop).Path
    Assert-ArtifactPath $reportPath
    $run=Split-Path -Parent $reportPath
    $report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.SchemaVersion -ne 1 -or $report.Succeeded -isnot [bool] -or -not $report.Succeeded -or $report.Configuration -cne 'Release') { throw 'A successful Release build report is required.' }
    $selection=@{}
    if ($PSBoundParameters.ContainsKey('Package')) { $selection.Package=$Package }
    $specs=@(Get-PublicArtifactPackages @selection)
    $known=@((Read-PackageCatalog).Packages.Key)
    $keys=@($report.Packages | ForEach-Object Key)
    $counts=if ($selection.Count) { @(1,2,3,4) } else { @(3,4) }
    if ($report.Packages -isnot [array] -or $keys.Count -notin $counts -or @($keys | Select-Object -Unique).Count -ne $keys.Count -or @($keys | Where-Object { $_ -cnotin $known }).Count) { throw 'Invalid package records in build report.' }
    if ($selection.Count -and (@($keys | Sort-Object) -join '|') -cne (@($specs.Key | Sort-Object) -join '|')) { throw 'Selected package build report must contain exactly the requested products.' }
    if (@($report.Commands).Count -eq 0 -or @($report.Commands | Where-Object { $null -eq $_.ExitCode -or $_.ExitCode -ne 0 }).Count) { throw 'Build report contains unsuccessful commands.' }
    $sources=@{}
    foreach ($spec in $specs) {
        $rows=@($report.Packages | Where-Object Key -CEQ $spec.Key)
        if ($rows.Count -ne 1) { throw "Missing public package $($spec.Key)." }
        $row=$rows[0]
        if ($row.Identity -cne $spec.Identity -or $row.Version -cne $spec.Version -or $row.Distribution -cne 'public' -or $row.InspectionPassed -isnot [bool] -or -not $row.InspectionPassed) { throw 'Public package metadata does not match the catalog.' }
        $expectedThemes=@(Get-PackageThemes $spec | Select-Object File,Name,Guid,Pkgdef)
        if (($row.Themes | ConvertTo-Json -Depth 5 -Compress) -cne ($expectedThemes | ConvertTo-Json -Depth 5 -Compress)) { throw 'Public package membership does not match the catalog.' }
        $expectedPath=[IO.Path]::GetFullPath((Join-Path $run "Release/$($spec.Key)/$($spec.Version)/$($spec.Key)-$($spec.Version).vsix"))
        if ([IO.Path]::GetFullPath($row.VsixPath) -cne $expectedPath) { throw 'Archive path is outside the selected build export.' }
        Assert-ArtifactPath $expectedPath
        if ($row.VsixSha256 -cnotmatch '^[0-9A-F]{64}$' -or (Get-FileHash -LiteralPath $expectedPath).Hash -cne $row.VsixSha256) { throw 'Archive hash does not match build evidence.' }
        $payloads=Get-VsixPkgdefHashes $expectedPath
        $recorded=@($row.PkgdefHashes.PSObject.Properties | Sort-Object Name | ForEach-Object { $_.Name+'='+$_.Value })
        $actual=@($payloads.Keys | Sort-Object | ForEach-Object { $_+'='+$payloads[$_] })
        if (($recorded -join '|') -cne ($actual -join '|')) { throw 'Compiled payload hashes do not match build evidence.' }
        $sources[$spec.Key]=$expectedPath
    }
    # Only this unique sibling is written until all copied archives pass inspection.
    # Failed staging is retained outside the upload path; never delete user directories.
    $temporary=Join-Path $parent ('.candidate-staging-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temporary)
    foreach ($spec in $specs) {
        $dir=Join-Path $temporary $spec.Key
        [void][IO.Directory]::CreateDirectory($dir)
        $vsix=Join-Path $dir ($spec.Key+'.vsix')
        Copy-Item -LiteralPath $sources[$spec.Key] -Destination $vsix
        $row=@($report.Packages | Where-Object Key -CEQ $spec.Key)[0]
        if ((Get-FileHash -LiteralPath $vsix).Hash -cne $row.VsixSha256) { throw 'Archive changed during staging.' }
        $summary=Get-PublicCandidateSummary $spec $vsix
        $utf8=New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Join-Path $dir 'candidate.json'),($summary | ConvertTo-Json -Depth 5)+"`n",$utf8)
        [IO.File]::WriteAllText((Join-Path $dir 'SHA256SUMS.txt'),$summary.Sha256+'  '+$spec.Key+".vsix`n",$utf8)
    }
    Test-PublicArtifactStage -OutputDirectory $temporary @selection
    # Both resolved paths are immediate children of the verified output parent.
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($temporary))) -cne $parent -or (Split-Path -Parent $output) -cne $parent) { throw 'Unsafe stage promotion paths.' }
    [IO.Directory]::Move($temporary,$output)
}

Export-ModuleMember -Function Get-PublicArtifactPackages,New-PublicArtifactStage,Test-PublicArtifactStage

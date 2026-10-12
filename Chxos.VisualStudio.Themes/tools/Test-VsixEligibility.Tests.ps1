[CmdletBinding()]
param([Parameter(Mandatory)][string]$VsixPath, [string]$Package = 'all-dev')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$inspector=Join-Path $PSScriptRoot 'Test-VsixPackage.ps1'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('cosmora-eligibility-'+[Guid]::NewGuid().ToString('N')+'.vsix')
$script:count=0

function Test-EligibilityCase([string]$Name, [scriptblock]$Mutation, [string]$Diagnostic) {
    Copy-Item -LiteralPath $VsixPath -Destination $scratch -Force
    $zip=[IO.Compression.ZipFile]::Open($scratch,[IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry=$zip.GetEntry('extension.vsixmanifest')
        $reader=New-Object IO.StreamReader($entry.Open())
        try { [xml]$manifest=$reader.ReadToEnd() } finally { $reader.Dispose() }
        & $Mutation $manifest
        $entry.Delete()
        $writer=New-Object IO.StreamWriter($zip.CreateEntry('extension.vsixmanifest').Open())
        try { $writer.Write($manifest.OuterXml) } finally { $writer.Dispose() }
    }
    finally { $zip.Dispose() }
    $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try {
        $log=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $inspector -VsixPath $scratch -Package $Package 2>&1 | Out-String
        $code=$LASTEXITCODE
    }
    finally { $ErrorActionPreference=$previous }
    if (-not $Diagnostic) {
        if ($code -ne 0) { throw "Expected valid package ($Name): $log" }
    }
    elseif ($code -eq 0 -or $log -notmatch $Diagnostic) { throw "Expected $Diagnostic ($Name): $log" }
    $script:count++
    Write-Host "PASS $Name"
}

try {
    Test-EligibilityCase 'stable API 17.14 and matching publisher' { param($m) } ''
    foreach ($architecture in @('amd64','arm64')) {
        foreach ($range in @('[18.0,19.0)','[17.0,18.0)','[17.13,)','[19.0,20.0)','[18.0,)','[17.14,18.0)')) {
            Test-EligibilityCase "$architecture rejects $range" {
                param($m)
                $target=@($m.PackageManifest.Installation.InstallationTarget | Where-Object ProductArchitecture -CEQ $architecture)
                if ($target.Count -ne 1) { throw "Missing target $architecture" }
                $target[0].SetAttribute('Version',$range)
            } 'Unexpected installation range'
        }
    }
    foreach ($range in @('[18.0,19.0)','[17.0,)','[18.0,)','[17.14,18.0)')) {
        Test-EligibilityCase "Core Editor rejects $range" {
            param($m) $m.PackageManifest.Prerequisites.Prerequisite.SetAttribute('Version',$range)
        } 'Unexpected prerequisite range'
    }
    foreach ($publisher in @('Chxos','chxoscode')) {
        Test-EligibilityCase "publisher rejects $publisher" {
            param($m) $m.PackageManifest.Metadata.Identity.SetAttribute('Publisher',$publisher)
        } 'Unexpected VSIX publisher'
    }
}
finally { if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Force } }
Write-Host "All $script:count VSIX eligibility cases pass."
$global:LASTEXITCODE=0

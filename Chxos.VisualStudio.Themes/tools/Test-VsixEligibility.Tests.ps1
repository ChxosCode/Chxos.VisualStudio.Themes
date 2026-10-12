[CmdletBinding()]
param([Parameter(Mandatory)][string]$VsixPath, [string]$Package = 'all-dev')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$inspector=Join-Path $PSScriptRoot 'Test-VsixPackage.ps1'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('cosmora-eligibility-'+[Guid]::NewGuid().ToString('N')+'.vsix')
$count=0
try {
    foreach ($range in @('[18.0,19.0)','[17.0,18.0)','[19.0,20.0)','[18.0,)')) {
        Copy-Item -LiteralPath $VsixPath -Destination $scratch -Force
        $zip=[IO.Compression.ZipFile]::Open($scratch,[IO.Compression.ZipArchiveMode]::Update)
        try {
            $entry=$zip.GetEntry('extension.vsixmanifest')
            $reader=New-Object IO.StreamReader($entry.Open())
            try { $text=$reader.ReadToEnd() } finally {$reader.Dispose()}
            $entry.Delete()
            $writer=New-Object IO.StreamWriter($zip.CreateEntry('extension.vsixmanifest').Open())
            try {$writer.Write($text.Replace('[18.0,19.0)',$range))} finally {$writer.Dispose()}
        }
        finally {$zip.Dispose()}
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try {$log= & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $inspector -VsixPath $scratch -Package $Package 2>&1 | Out-String}
        finally {$ErrorActionPreference=$previous}
        if ($range -eq '[18.0,19.0)') {
            if ($LASTEXITCODE -ne 0) {throw "Expected valid 18.x package: $log"}
        }
        elseif ($LASTEXITCODE -eq 0 -or $log -notmatch 'Unexpected installation range') {throw "Expected eligibility diagnostic for $range : $log"}
        $count++
    }
}
finally {if (Test-Path -LiteralPath $scratch) {Remove-Item -LiteralPath $scratch -Force}}
Write-Host "All $count VSIX eligibility cases pass."

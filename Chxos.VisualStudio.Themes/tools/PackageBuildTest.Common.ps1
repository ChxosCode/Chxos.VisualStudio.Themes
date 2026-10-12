# Shared test infrastructure; no production build or validator dependency.
function Get-BuildTestPackages([string[]]$Keys) {
    $catalog=Read-PackageCatalog
    if ($null -eq $Keys) { $Keys=@($catalog.Packages | ForEach-Object Key) }
    if (-not $Keys.Count -or @($Keys | Select-Object -Unique).Count -ne $Keys.Count) { throw 'Select distinct package keys.' }
    foreach ($key in $Keys) {
        if ($key -cnotin @($catalog.Packages | ForEach-Object Key)) { throw "Unknown package key: $key" }
        Get-ThemePackage -Package $key -Catalog $catalog
    }
}

function Invoke-BuildTestCommand([string]$Name,[string]$Executable,[string[]]$Arguments) {
    $log=Join-Path $OutputDirectory ($Name+'.log')
    $started=[DateTime]::UtcNow
    $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try { & $Executable @Arguments *> $log; $code=$LASTEXITCODE }
    finally { $ErrorActionPreference=$previous }
    $records.Add([pscustomobject]@{Name=$Name;Executable=$Executable;Arguments=$Arguments;ExitCode=$code;Log=$log;StartedUtc=$started.ToString('o');FinishedUtc=[DateTime]::UtcNow.ToString('o');Seconds=([DateTime]::UtcNow-$started).TotalSeconds})
    if ($code -ne 0) { throw "$Name failed ($code). See $log." }
}

function Read-BuildTestPayloads([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $result=@{}
        foreach ($entry in @($zip.Entries | Where-Object FullName -like '*.pkgdef')) {
            if ($result.ContainsKey($entry.FullName)) { throw 'Duplicate compiled payload.' }
            $stream=$entry.Open(); $buffer=[IO.MemoryStream]::new()
            try { $stream.CopyTo($buffer); $result[$entry.FullName]=[Convert]::ToBase64String($buffer.ToArray()) }
            finally { $stream.Dispose(); $buffer.Dispose() }
        }
        return $result
    }
    finally { $zip.Dispose() }
}

function Assert-BuildTestPayloads([string]$Path,[Collections.IDictionary]$Expected) {
    $actual=Read-BuildTestPayloads $Path
    if ($actual.Count -ne $Expected.Count) { throw 'Compiled payload count changed.' }
    foreach ($name in $Expected.Keys) {
        if (-not $actual.ContainsKey($name) -or $actual[$name] -cne $Expected[$name]) { throw "Compiled payload bytes changed: $name" }
    }
}

function Assert-BuildTestArchive($Spec,[string]$Path,[string]$Label) {
    Invoke-BuildTestCommand ($Label+'-inspect') 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-VsixPackage.ps1'),'-Package',$Spec.Key,'-VsixPath',$Path)
    Assert-BuildTestPayloads $Path $baseline[$Spec.Key]
    $archives.Add([pscustomobject]@{Name=$Label;Package=$Spec.Key;Path=$Path;Sha256=(Get-FileHash -LiteralPath $Path).Hash;PayloadsEqual=$true})
}

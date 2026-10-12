[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$generator=Join-Path $PSScriptRoot 'Generate-Themes.ps1'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('cosmora-generation-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$count=0
function Invoke-Generation([string[]]$Arguments,[bool]$Pass,[string]$Name) {
    $previous=$ErrorActionPreference
    $ErrorActionPreference='Continue'
    try { $log= & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $generator @Arguments 2>&1 | Out-String }
    finally { $ErrorActionPreference=$previous }
    if (($LASTEXITCODE -eq 0) -ne $Pass) { throw "FAILED $Name : $log" }
    $script:count++
}
try {
    Invoke-Generation @('-OutputDirectory',$scratch) $true 'fresh generation'
    Invoke-Generation @('-OutputDirectory',$scratch,'-Check') $true 'deterministic generation'
    foreach ($source in Get-ChildItem -LiteralPath $project -Filter '*.vstheme') {
        [xml]$original=[IO.File]::ReadAllText($source.FullName)
        [xml]$generated=[IO.File]::ReadAllText((Join-Path $scratch $source.Name))
        if ($original.OuterXml -cne $generated.OuterXml) { throw "Generated typed XML differs: $($source.Name)" }
    }
    $count++
    $bootstrap=Join-Path $scratch 'bootstrap'
    Invoke-Generation @('-OutputDirectory',$bootstrap,'-MissingDeferred') $true 'bootstrap missing deferred themes'
    $deferred=@((Get-Content (Join-Path $project 'authoring/PackageCatalog.json') -Raw | ConvertFrom-Json).DeferredPublicThemes)
    if ((@(Get-ChildItem $bootstrap -File | ForEach-Object Name | Sort-Object) -join '|') -cne (@($deferred | Sort-Object) -join '|')) { throw 'Bootstrap wrote a public theme or catalog, or missed a deferred theme.' }
    foreach ($name in $deferred) { if ((Get-FileHash (Join-Path $bootstrap $name)).Hash -cne (Get-FileHash (Join-Path $project $name)).Hash) { throw "Bootstrap bytes differ: $name" } }
    $count++
    Add-Content (Join-Path $bootstrap 'Amberroot.vstheme') '<!-- preserve local edit -->'
    $edited=(Get-FileHash (Join-Path $bootstrap 'Amberroot.vstheme')).Hash
    Invoke-Generation @('-OutputDirectory',$bootstrap,'-MissingDeferred') $true 'bootstrap preserves existing files'
    if ((Get-FileHash (Join-Path $bootstrap 'Amberroot.vstheme')).Hash -cne $edited) { throw 'Bootstrap overwrote an existing deferred file.' }
    $count++
    Invoke-Generation @('-OutputDirectory',$bootstrap,'-Check') $false 'bootstrap does not hide missing public sources or drift'
    Invoke-Generation @('-OutputDirectory',$bootstrap,'-Check','-MissingDeferred') $false 'check and bootstrap are mutually exclusive'
    Add-Content -LiteralPath (Join-Path $scratch 'Amberroot.vstheme') -Value '<!-- drift -->'
    Invoke-Generation @('-OutputDirectory',$scratch,'-Check') $false 'drift rejected'
    $authoring=Join-Path $scratch 'authoring'
    [void][IO.Directory]::CreateDirectory($authoring)
    Copy-Item -Path (Join-Path $project 'authoring/*.json') -Destination $authoring
    $path=Join-Path $authoring 'Components.json'
    $text=[IO.File]::ReadAllText($path)
    $text=$text.Replace('"CT_RAW"','"CT_UNKNOWN"')
    [IO.File]::WriteAllText($path,$text)
    Invoke-Generation @('-AuthoringDirectory',$authoring,'-OutputDirectory',$scratch) $false 'unknown component type rejected'
}
finally {
    # Only delete this test's resolved, uniquely named temporary directory.
    $resolved=[IO.Path]::GetFullPath($scratch)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'cosmora-generation-*') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "All $count generation cases pass."

[CmdletBinding(DefaultParameterSetName='Selected')]
param(
    [Parameter(Mandatory, ParameterSetName='Selected')][string[]]$Package,
    [Parameter(Mandatory, ParameterSetName='Public')][switch]$AllPublic,
    [ValidateSet('Debug','Release')][string]$Configuration = 'Release',
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'VisualAudit.Common.psm1') -Force
$project = Split-Path -Parent $PSScriptRoot
$repository = Split-Path -Parent $project
$catalog = Read-PackageCatalog
& (Join-Path $PSScriptRoot 'Generate-Themes.ps1') -MissingDeferred
if ($AllPublic) { $Package = @($catalog.Packages | Where-Object Distribution -CEQ 'public' | ForEach-Object Key) }
if (-not $Package -or @($Package | Select-Object -Unique).Count -ne $Package.Count) { throw 'Select one or more distinct package keys.' }
$selected = @($Package | ForEach-Object { Get-ThemePackage -Package $_ -Catalog $catalog })
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repository 'artifacts/packages' }
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$runDirectory = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) $runId
[void][IO.Directory]::CreateDirectory($runDirectory)
$commands = [Collections.Generic.List[object]]::new()
$results = [Collections.Generic.List[object]]::new()
$inputs = [ordered]@{}
foreach ($file in (& git -C $repository ls-files --cached --others --exclude-standard | Sort-Object -Unique)) {
    $path = Join-Path $repository $file
    if (Test-Path -LiteralPath $path -PathType Leaf) { $inputs[$file] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
# Ignored generated themes are still compiler inputs. Fingerprint their actual
# bytes so a local edit during the build cannot escape the source-change guard.
foreach ($theme in (Get-Content (Join-Path $project 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json)) {
    $relative = (Split-Path -Leaf $project) + '/' + $theme.File
    $inputs[$relative] = (Get-FileHash -LiteralPath (Join-Path $project $theme.File) -Algorithm SHA256).Hash
}
$revision = @(& git -C $repository rev-parse --verify --quiet HEAD)
$head = if ($LASTEXITCODE -eq 0) { ($revision -join '').Trim() } else { $null }
$inputText = $inputs | ConvertTo-Json -Depth 3 -Compress
$sha = [Security.Cryptography.SHA256]::Create()
try { $fingerprint = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($inputText))).Replace('-','') }
finally { $sha.Dispose() }
$report = [ordered]@{
    SchemaVersion=1; RunId=$runId; StartedUtc=[DateTime]::UtcNow.ToString('o'); Configuration=$Configuration
    Head=$head; GitStatus=(& git -C $repository status --short | Out-String)
    WorkingTreeFingerprint=$fingerprint; Inputs=$inputs
    Tools=@{ Dotnet=(& dotnet --version | Out-String).Trim(); PowerShell=$PSVersionTable.PSVersion.ToString(); ColorCompiler='17.11.35325.10'; VssdkBuildTools='18.5.40034' }
    Commands=$commands; Packages=$results; Succeeded=$false; Failure=$null
    Scope='Build and package inspection only. Runtime acceptance and publishing are separate.'
}
function Invoke-Recorded([string]$Name, [string]$Executable, [string[]]$Arguments) {
    $log = Join-Path $runDirectory ($Name + '.log')
    $started = [DateTime]::UtcNow
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Executable @Arguments *> $log; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    $commands.Add([pscustomobject]@{Name=$Name;Executable=$Executable;Arguments=$Arguments;ExitCode=$code;Log=$log;StartedUtc=$started.ToString('o');FinishedUtc=[DateTime]::UtcNow.ToString('o')})
    if ($code -ne 0) { throw "$Name failed with exit code $code. See $log" }
}
# MSBuild's cmd.exe child must not discover PowerShell 7 modules in Windows PowerShell.
$originalModulePath = $env:PSModulePath
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
try {
    Invoke-Recorded 'theme-drift' 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Generate-Themes.ps1'),'-Check')
    Invoke-Recorded 'package-drift' 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Generate-ThemePackages.ps1'),'-Check')
    Invoke-Recorded 'source-validation' 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-ThemeContrast.ps1'),'-CoverageReportPath',(Join-Path $runDirectory 'coverage.json'))
    foreach ($spec in $selected) {
        $key = $spec.Key
        $buildDirectory = Join-Path $project "bin/$Configuration/$key"
        [void][IO.Directory]::CreateDirectory($buildDirectory)
        # This lock also protects shared per-package restore intermediates.
        $lock = [IO.File]::Open((Join-Path $buildDirectory '.build.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            Write-Host "Building $key $($spec.Version)..."
            $projectFile = Join-Path $project 'Chxos.VisualStudio.Themes.csproj'
            Invoke-Recorded "$key-restore" 'dotnet' @('restore',$projectFile,'--locked-mode',"-p:ThemePackage=$key","-p:Configuration=$Configuration")
            Invoke-Recorded "$key-build" 'dotnet' @('build',$projectFile,'-c',$Configuration,'--no-restore',"-p:ThemePackage=$key")
            $vsix = Join-Path $buildDirectory "$key-$($spec.Version).vsix"
            Invoke-Recorded "$key-inspection" 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-VsixPackage.ps1'),'-VsixPath',$vsix,'-Package',$key)
            $destination = Join-Path $runDirectory "$Configuration/$key/$($spec.Version)"
            [void][IO.Directory]::CreateDirectory($destination)
            $export = Join-Path $destination ([IO.Path]::GetFileName($vsix))
            Copy-Item -LiteralPath $vsix -Destination $export
            $result = [pscustomobject]@{
                Key=$key; Identity=$spec.Identity; Version=$spec.Version; Distribution=$spec.Distribution
                Themes=@(Get-PackageThemes $spec | Select-Object File,Name,Guid,Pkgdef)
                VsixPath=$export; VsixSha256=(Get-FileHash -LiteralPath $export -Algorithm SHA256).Hash
                PkgdefHashes=(Get-VsixPkgdefHashes -VsixPath $export); InspectionPassed=$true
            }
            $results.Add($result)
            $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'package.json') -Encoding UTF8
        }
        finally { $lock.Dispose() }
    }
    # Refuse to credit artifacts built across changing source inputs.
    foreach ($file in $inputs.Keys) {
        $path = Join-Path $repository $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $inputs[$file]) { throw "Source changed during packaging: $file. Rebuild from stable inputs." }
    }
    $report.Succeeded = $true
}
catch { $report.Failure = $_.Exception.Message; throw }
finally {
    $env:PSModulePath = $originalModulePath
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $runDirectory 'build.json') -Encoding UTF8
    Write-Host "Packaging evidence: $runDirectory"
}
Write-Host "Built and inspected $($results.Count) packages. Runtime acceptance is separate."

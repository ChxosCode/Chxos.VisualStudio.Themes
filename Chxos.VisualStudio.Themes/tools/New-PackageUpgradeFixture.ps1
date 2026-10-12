[CmdletBinding()]
param([Parameter(Mandatory)][string]$Package, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'VisualAudit.Common.psm1') -Force
$project=Split-Path -Parent $PSScriptRoot
$catalog=Read-PackageCatalog
$spec=Get-ThemePackage $Package $catalog
if ($spec.Distribution -cne 'public') { throw 'Upgrade fixtures are for public pilot packages.' }
$root=[IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $root) { throw 'Upgrade fixture output must be a new directory.' }
[void][IO.Directory]::CreateDirectory($root)
$version=[version]$spec.Version
$testVersion='{0}.{1}.{2}' -f $version.Major,$version.Minor,($version.Build+1)
$spec.Version=$testVersion
$catalogPath=Join-Path $root 'PackageCatalog.json'
$catalog | ConvertTo-Json -Depth 10 | Set-Content $catalogPath -Encoding UTF8
[xml]$manifest=[IO.File]::ReadAllText((Join-Path $project "packaging/generated/$Package/source.extension.vsixmanifest"))
$manifest.PackageManifest.Metadata.Identity.Version=$testVersion
$manifestPath=Join-Path $root 'source.extension.vsixmanifest'
$manifest.Save($manifestPath)
$obj=(Join-Path $root 'obj')+'\'
$bin=(Join-Path $root 'bin')+'\'
$properties=@("-p:ThemePackage=$Package",'-p:Configuration=Release',"-p:ThemePackageManifest=$manifestPath","-p:TargetVsixContainerName=$Package-$testVersion.vsix","-p:BaseIntermediateOutputPath=$obj","-p:IntermediateOutputPath=$obj","-p:MSBuildProjectExtensionsPath=$obj","-p:OutputPath=$bin")
$originalModulePath=$env:PSModulePath
$env:PSModulePath="$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
try {
    & dotnet restore (Join-Path $project 'Chxos.VisualStudio.Themes.csproj') --locked-mode @properties *> (Join-Path $root 'restore.log')
    if ($LASTEXITCODE -ne 0) { throw 'Upgrade fixture restore failed.' }
    & dotnet build (Join-Path $project 'Chxos.VisualStudio.Themes.csproj') -c Release --no-restore @properties *> (Join-Path $root 'build.log')
    if ($LASTEXITCODE -ne 0) { throw 'Upgrade fixture build failed.' }
    $vsix=Join-Path $bin "$Package-$testVersion.vsix"
    & powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'Test-VsixPackage.ps1') -VsixPath $vsix -Package $Package -CatalogPath $catalogPath -SourceManifestPath $manifestPath *> (Join-Path $root 'inspection.log')
    if ($LASTEXITCODE -ne 0) { throw 'Upgrade fixture inspection failed.' }
    [ordered]@{SchemaVersion=1;TestOnly=$true;PackageKey=$Package;Identity=$spec.Identity;Version=$testVersion;VsixPath=$vsix;VsixSha256=(Get-FileHash $vsix).Hash;PkgdefHashes=(Get-VsixPkgdefHashes $vsix);CatalogPath=$catalogPath;SourceManifestPath=$manifestPath;BuildProperties=$properties} |
        ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'fixture.json') -Encoding UTF8
    Write-Host "Test-only upgrade fixture: $root"
}
finally { $env:PSModulePath=$originalModulePath }

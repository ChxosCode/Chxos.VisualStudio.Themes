[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VsixPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$EvidencePath,
    [string]$EnvironmentPath,
    [string]$Package = 'all-dev'
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RuntimeAcceptance.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'VisualAudit.Common.psm1') -Force
$project = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $PSScriptRoot 'RuntimeScenarios.json') -Raw | ConvertFrom-Json
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
$selectedPackage = Get-ThemePackage $Package
$catalog = @(Get-PackageThemes $selectedPackage)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-VsixPackage.ps1') -VsixPath $VsixPath -Package $Package
if ($LASTEXITCODE -ne 0) { throw 'Package inspection failed before runtime acceptance.' }
$relationships = Get-Content (Join-Path $PSScriptRoot 'ContextualRelationships.json') -Raw | ConvertFrom-Json
$hash = (Get-FileHash -LiteralPath $VsixPath -Algorithm SHA256).Hash
$evidence = @()
if ($EvidencePath) { $evidence = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json }
$rows = @(Test-RuntimeAcceptance -Manifest $manifest -Themes @($catalog | ForEach-Object Name) -Evidence $evidence -VsixSha256 $hash)
$unresolved = @($relationships | Where-Object disposition -eq 'unresolved' | ForEach-Object id)
$environmentStatus = 'No installed-payload evidence supplied.'
$environmentVerified = $false
if ($EnvironmentPath) {
    try {
        $environment = Get-Content -LiteralPath $EnvironmentPath -Raw | ConvertFrom-Json
        # Legacy reports remain readable; exact VSIX identity/hash still controls attribution.
        if ($environment.PSObject.Properties.Name -contains 'SchemaVersion' -and $environment.SchemaVersion -notin @(1,2)) { throw 'Unsupported environment schema.' }
        if ($environment.SchemaVersion -eq 2 -or $environment.PSObject.Properties.Name -contains 'PackageIdentity') {
            if ($environment.PackageKey -cne $Package -or $environment.PackageIdentity -cne $selectedPackage.Identity -or $environment.PackageVersion -cne $selectedPackage.Version) { throw 'Environment package identity/version mismatch.' }
            $expectedThemes=@($catalog | ForEach-Object Name | Sort-Object)
            if ($environment.Themes -isnot [array] -or (@($environment.Themes | Sort-Object) -join '|') -cne ($expectedThemes -join '|')) { throw 'Environment package membership mismatch.' }
        }
        if ($environment.VsixSha256 -cne $hash -or $environment.InstallationVersion -notmatch '^18\.') { throw 'Artifact/version mismatch.' }
        $packaged = Get-VsixPkgdefHashes -VsixPath $VsixPath
        $installed = @{}
        foreach ($property in $environment.InstalledHashes.PSObject.Properties) { $installed[$property.Name] = $property.Value }
        Assert-VisualAuditPayloadIdentity -Packaged $packaged -Installed $installed
        $environmentVerified = $true
        $environmentStatus = 'Installed payload hashes match this VSIX on Visual Studio 18.x.'
    }
    catch { $environmentStatus = $_.Exception.Message }
}
$blocked = @($rows | Where-Object { $_.Required -and $_.Status -ne 'pass' }).Count -gt 0 -or $unresolved.Count -gt 0 -or -not $environmentVerified
[void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
[ordered]@{ SchemaVersion=2; PackageKey=$Package; PackageIdentity=$selectedPackage.Identity; PackageVersion=$selectedPackage.Version; Themes=@($catalog | ForEach-Object Name); Scope='Runtime and consumer acceptance only; build/package/hosted CI gates remain additional'; VsixSha256=$hash; Ready=(-not $blocked); EnvironmentStatus=$environmentStatus; UnresolvedRelationships=$unresolved; Scenarios=$rows } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
if ($blocked) { Write-Host 'Release blocked: unresolved consumers or incomplete required runtime evidence.'; exit 1 }
Write-Host 'Runtime and consumer acceptance passed. Verify remaining release checklist gates before publishing.'

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Ref
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
if ($Package -cnotin @('foundation','pinknoise','cosmora')) { throw 'Release preparation requires an exact public product key.' }
$spec=Get-ThemePackage -Package $Package
if ($spec.Distribution -cne 'public') { throw 'Release preparation requires a public product.' }
if ($Version -cne $spec.Version) { throw "Requested version '$Version' does not match $Package catalog version '$($spec.Version)'. Update and regenerate package metadata before preparing a different version." }
if ($Ref.StartsWith('refs/tags/',[StringComparison]::Ordinal)) {
    if ($Ref -cne "refs/tags/$Package/v$Version") { throw 'Release tag must match the selected product and catalog version.' }
}
elseif (-not $Ref.StartsWith('refs/heads/',[StringComparison]::Ordinal) -or $Ref.Length -le 11) { throw 'Release preparation requires a branch or product version tag.' }
$spec

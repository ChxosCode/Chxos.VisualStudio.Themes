[CmdletBinding(DefaultParameterSetName='Stage')]
param(
    [Parameter(Mandatory,ParameterSetName='Stage')][string]$BuildReportPath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory,ParameterSetName='Check')][switch]$Check,
    [string[]]$Package
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PublicArtifacts.psm1') -Force
$selection=@{}
if ($PSBoundParameters.ContainsKey('Package')) { $selection.Package=$Package }
if ($Check) { Test-PublicArtifactStage -OutputDirectory $OutputDirectory @selection }
else { New-PublicArtifactStage -BuildReportPath $BuildReportPath -OutputDirectory $OutputDirectory @selection }

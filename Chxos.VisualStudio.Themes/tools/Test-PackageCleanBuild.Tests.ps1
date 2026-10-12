[CmdletBinding()]
param([string]$OutputDirectory,[string[]]$Package)
$ErrorActionPreference='Stop'
if ($PSBoundParameters.ContainsKey('Package') -and -not $Package) { throw 'Select distinct package keys.' }
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
. (Join-Path $PSScriptRoot 'PackageBuildTest.Common.ps1')
$specs=@(Get-BuildTestPackages $Package)
$project=Split-Path -Parent $PSScriptRoot
$baseline=@{}
foreach ($spec in $specs) { $baseline[$spec.Key]=Read-BuildTestPayloads (Join-Path $project "bin/Release/$($spec.Key)/$($spec.Key)-$($spec.Version).vsix") }
if (-not $OutputDirectory) { $OutputDirectory=Join-Path (Split-Path -Parent $project) ('artifacts/package-clean-'+[Guid]::NewGuid().ToString('N')) }
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Clean-build evidence directory must be new.' }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$records=[Collections.Generic.List[object]]::new(); $archives=[Collections.Generic.List[object]]::new(); $passed=$false
$original=$env:PSModulePath
$env:PSModulePath="$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
try {
    foreach ($spec in $specs) {
        $key=$spec.Key; $work=Join-Path $OutputDirectory $key
        $properties=@("-p:ThemePackage=$key",'-p:Configuration=Release',"-p:BaseIntermediateOutputPath=$work/obj/","-p:IntermediateOutputPath=$work/obj/","-p:MSBuildProjectExtensionsPath=$work/obj/","-p:OutputPath=$work/bin/")
        Invoke-BuildTestCommand ($key+'-restore') 'dotnet' (@('restore',(Join-Path $project 'Chxos.VisualStudio.Themes.csproj'),'--locked-mode')+$properties)
        Invoke-BuildTestCommand ($key+'-build') 'dotnet' (@('build',(Join-Path $project 'Chxos.VisualStudio.Themes.csproj'),'--no-restore')+$properties)
        Assert-BuildTestArchive $spec (Join-Path $work "bin/$key-$($spec.Version).vsix") ($key+'-clean')
    }
    $passed=$true
    Write-Host "All $($specs.Count) clean isolated restore/build/inspection cases pass; compiled bytes match ordinary builds."
}
finally {
    $env:PSModulePath=$original
    @{SchemaVersion=1;Passed=$passed;Packages=@($specs.Key);Commands=@($records.ToArray());Archives=@($archives.ToArray());OutputDirectory=$OutputDirectory} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDirectory 'results.json') -Encoding UTF8
}

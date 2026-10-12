[CmdletBinding()]
param([string]$OutputDirectory,[string[]]$Package)
$ErrorActionPreference='Stop'
if ($PSBoundParameters.ContainsKey('Package') -and -not $Package) { throw 'Select distinct package keys.' }
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
. (Join-Path $PSScriptRoot 'PackageBuildTest.Common.ps1')
$specs=@(Get-BuildTestPackages $Package)
$project=Split-Path -Parent $PSScriptRoot
$projectFile=Join-Path $project 'Chxos.VisualStudio.Themes.csproj'
$baseline=@{}
foreach ($spec in $specs) { $baseline[$spec.Key]=Read-BuildTestPayloads (Join-Path $project "bin/Release/$($spec.Key)/$($spec.Key)-$($spec.Version).vsix") }
if (-not $OutputDirectory) { $OutputDirectory=Join-Path (Split-Path -Parent $project) ('artifacts/package-isolation-'+[Guid]::NewGuid().ToString('N')) }
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Isolation evidence directory must be new.' }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$records=[Collections.Generic.List[object]]::new(); $archives=[Collections.Generic.List[object]]::new()
$probes=[Collections.Generic.List[string]]::new(); $jobs=[Collections.Generic.List[object]]::new(); $passed=$false
$originalModulePath=$env:PSModulePath
$env:PSModulePath="$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
function Build-Checked($Spec,[string]$Label) {
    Invoke-BuildTestCommand $Label 'dotnet' @('build',$projectFile,'-c','Release','--no-restore',"-p:ThemePackage=$($Spec.Key)")
    Assert-BuildTestArchive $Spec (Join-Path $project "bin/Release/$($Spec.Key)/$($Spec.Key)-$($Spec.Version).vsix") $Label
}
try {
    foreach ($spec in $specs) {
        $key=$spec.Key
        $stray=Join-Path $project ("bin/Release/$key/Unlisted-"+[Guid]::NewGuid().ToString('N')+'.pkgdef')
        $payload=@($baseline[$key].Values)[0]
        # CreateNew guarantees cleanup can never remove a pre-existing file.
        $stream=[IO.File]::Open($stray,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
        $probes.Add($stray)
        try { $bytes=[Convert]::FromBase64String($payload); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
        Build-Checked $spec ($key+'-stale-output')
        Remove-Item -LiteralPath $stray -Force; [void]$probes.Remove($stray)
    }
    foreach ($spec in $specs) { Build-Checked $spec ($spec.Key+'-forward') }
    $reverse=@($specs); [Array]::Reverse($reverse)
    foreach ($spec in $reverse) { Build-Checked $spec ($spec.Key+'-reverse-repeat') }
    # Disjoint pairs cover every selected product without concurrent writes to
    # a single package's obj/bin. For odd selections the last pair overlaps in
    # membership only after the preceding pair has finished.
    for ($i=0;$i -lt $specs.Count-1;$i+=2) {
        $pair=@($specs[$i],$specs[$i+1])
        if ($i+2 -eq $specs.Count-1) { $pair+=@($specs[$i+2]) }
        foreach ($job in $jobs) { $job.Process.Dispose() }
        $jobs.Clear()
        foreach ($spec in $pair) {
            $key=$spec.Key; $label=$key+'-parallel'
            $log=Join-Path $OutputDirectory ($label+'.log'); $err=Join-Path $OutputDirectory ($label+'-errors.log')
            $buildArguments=@('build',('"'+$projectFile+'"'),'-c','Release','--no-restore',"-p:ThemePackage=$key")
            $start=[DateTime]::UtcNow
            $process=Start-Process -FilePath 'dotnet' -ArgumentList $buildArguments -RedirectStandardOutput $log -RedirectStandardError $err -PassThru -WindowStyle Hidden
            $processHandle=$process.Handle
            $jobs.Add(@{Spec=$spec;Process=$process;Log=$log;ErrorLog=$err;Name=$label;Started=$start;Arguments=$buildArguments})
        }
        $failed=$false
        foreach ($job in $jobs) {
            $job.Process.WaitForExit(); $code=$job.Process.ExitCode
            $records.Add([pscustomobject]@{Name=$job.Name;Executable='dotnet';Arguments=$job.Arguments;ExitCode=$code;Log=$job.Log;ErrorLog=$job.ErrorLog;StartedUtc=$job.Started.ToString('o');FinishedUtc=$job.Process.ExitTime.ToUniversalTime().ToString('o');Seconds=($job.Process.ExitTime.ToUniversalTime()-$job.Started).TotalSeconds})
            if ($code -ne 0) { $failed=$true }
        }
        if ($failed) { throw 'Independent concurrent package build failed; see retained logs.' }
        foreach ($job in $jobs) { Assert-BuildTestArchive $job.Spec (Join-Path $project "bin/Release/$($job.Spec.Key)/$($job.Spec.Key)-$($job.Spec.Version).vsix") $job.Name }
    }
    $passed=$true
    Write-Host "Package isolation passes for $($specs.Count) packages. See results.json for the exact scenario coverage."
}
finally {
    # Wait for only processes started here before leaving the output state.
    foreach ($job in $jobs) { if (-not $job.Process.HasExited) { $job.Process.WaitForExit() }; $job.Process.Dispose() }
    $env:PSModulePath=$originalModulePath
    foreach ($probe in $probes) { if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force } }
    @{SchemaVersion=1;Passed=$passed;Packages=@($specs.Key);Commands=@($records.ToArray());Archives=@($archives.ToArray());ConcurrentCoverage=if ($specs.Count -gt 1) {'selected distinct packages'} else {'not applicable: one package selected'}} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDirectory 'results.json') -Encoding UTF8
}

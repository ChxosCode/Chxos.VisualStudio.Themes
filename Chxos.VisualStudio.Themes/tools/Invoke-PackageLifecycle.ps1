[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Initialize','Install','Upgrade','Uninstall','Inspect','Refresh')][string]$Action,
    [Parameter(Mandatory)][string]$StatePath,
    [string]$Package,
    [string]$VsixPath,
    [string]$UpgradeFixturePath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'VisualAudit.Common.psm1') -Force
$catalog=Read-PackageCatalog
$StatePath=[IO.Path]::GetFullPath($StatePath)
$directory=Split-Path -Parent $StatePath
[void][IO.Directory]::CreateDirectory($directory)
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$instance=(& $vswhere -latest -products * -version '[18.0,19.0)' -format json | ConvertFrom-Json)
if (@($instance).Count -ne 1) { throw 'Expected one selected Visual Studio 18 installation.' }
$ide=Join-Path $instance.installationPath 'Common7/IDE'
if ($Action -ceq 'Initialize') {
    if (Test-Path -LiteralPath $StatePath) { throw 'Lifecycle state already exists; choose a new state path.' }
    $suffix='ThemePackages'+[DateTime]::UtcNow.ToString('yyyyMMdd')+[Guid]::NewGuid().ToString('N').Substring(0,8)
    $profile=Join-Path $env:LOCALAPPDATA "Microsoft/VisualStudio/18.0_$($instance.instanceId)$suffix"
    if (Test-Path -LiteralPath $profile) { throw 'Lifecycle profile already exists.' }
    $state=[pscustomobject]@{SchemaVersion=1;RootSuffix=$suffix;ProfileDirectory=$profile;InstanceId=$instance.instanceId;InstallationVersion=$instance.installationVersion;InstallationPath=$instance.installationPath;CreatedUtc=[DateTime]::UtcNow.ToString('o');Packages=@();Events=@();Scope='Package lifecycle only; theme rendering acceptance remains separate.'}
}
else {
    $state=Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.SchemaVersion -ne 1 -or $state.RootSuffix -cnotmatch '^ThemePackages\d{8}[a-f0-9]{8}$' -or $state.InstanceId -cne $instance.instanceId) { throw 'Invalid lifecycle state or wrong Visual Studio instance.' }
    $expected=Join-Path $env:LOCALAPPDATA "Microsoft/VisualStudio/18.0_$($instance.instanceId)$($state.RootSuffix)"
    if ([IO.Path]::GetFullPath($state.ProfileDirectory) -cne [IO.Path]::GetFullPath($expected)) { throw 'Lifecycle profile path mismatch.' }
}
function Invoke-LifecycleProcess([string]$Name,[string]$Executable,[string[]]$Arguments) {
    $started=[DateTime]::UtcNow
    $log=Join-Path $directory ($Name+'-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.log')
    # Devenv parses quoted switches as filenames. Quote only arguments that need it.
    $quoted=@($Arguments | ForEach-Object {
        if ($_ -match '"' -or $_ -match '[\r\n]') { throw 'Unexpected quote/newline in lifecycle argument.' }
        if ($_ -match '\s' -or $_ -eq '') { '"'+$_+'"' } else { $_ }
    })
    $process=Start-Process -FilePath $Executable -ArgumentList $quoted -RedirectStandardOutput $log -RedirectStandardError ($log+'.err') -PassThru -WindowStyle Hidden
    $processHandle=$process.Handle # Cache the handle before a short-lived process exits (Windows PowerShell 5.1).
    if (-not $process.WaitForExit(300000)) {
        $state.Events+=@([pscustomobject]@{Kind='command';Name=$Name;Executable=$Executable;Arguments=$Arguments;ProcessId=$process.Id;ExitCode=$null;TimedOut=$true;Log=$log;Utc=[DateTime]::UtcNow.ToString('o')})
        throw "Lifecycle process $Name is still running (PID $($process.Id)); no unrelated process was closed."
    }
    $code=$process.ExitCode
    $nativeLogs=@()
    if ([IO.Path]::GetFileName($Executable) -ieq 'VSIXInstaller.exe') {
        # Recent installers can ignore /logFile and write their own temp log.
        foreach ($candidate in Get-ChildItem -LiteralPath $env:TEMP -Filter 'dd_VSIXInstaller_*.log' -File | Where-Object CreationTimeUtc -GE $started.AddSeconds(-2)) {
            if (([IO.File]::ReadAllText($candidate.FullName)).Contains($state.RootSuffix)) {
                $copy=Join-Path $directory ($Name+'-native-'+$candidate.Name)
                Copy-Item -LiteralPath $candidate.FullName -Destination $copy
                $nativeLogs+=@($copy)
            }
        }
    }
    $state.Events+=@([pscustomobject]@{Kind='command';Name=$Name;Executable=$Executable;Arguments=$Arguments;ExitCode=$code;Log=$log;NativeLogs=$nativeLogs;StartedUtc=$started.ToString('o');Utc=[DateTime]::UtcNow.ToString('o')})
    if ($code -ne 0) { throw "$Name failed with exit code $code. See $log." }
}
function Get-ProfileSnapshot {
    $installed=@()
    if (Test-Path -LiteralPath $state.ProfileDirectory) {
        $installed=@(Get-ChildItem -LiteralPath $state.ProfileDirectory -Filter 'extension.vsixmanifest' -Recurse -File | ForEach-Object {
            [xml]$m=[IO.File]::ReadAllText($_.FullName)
            [pscustomobject]@{Identity=[string]$m.PackageManifest.Metadata.Identity.Id;Version=[string]$m.PackageManifest.Metadata.Identity.Version;Path=$_.Directory.FullName}
        })
    }
    $expectedIds=@($state.Packages | ForEach-Object Identity)
    $ownedIds=@($catalog.Packages | ForEach-Object Identity)+@('Chxos.Cosmora.VisualStudio.Themes')
    foreach ($item in $installed | Where-Object Identity -CIN $ownedIds) {
        if ($item.Identity -cnotin $expectedIds) { throw "Unexpected collection/pilot installation: $($item.Identity)." }
    }
    $payloads=@()
    foreach ($record in $state.Packages) {
        $matches=@($installed | Where-Object Identity -CEQ $record.Identity)
        if ($matches.Count -ne 1 -or $matches[0].Version -cne $record.Version) { throw "Installed identity/version mismatch for $($record.Key)." }
        $packaged=Get-VsixPkgdefHashes $record.VsixPath
        $hashes=Get-InstalledPkgdefHashes -RootSuffix $state.RootSuffix -ProfileDirectory $state.ProfileDirectory -ExtensionIdentity $record.Identity -Names @($packaged.Keys)
        Assert-VisualAuditPayloadIdentity -Packaged $packaged -Installed $hashes
        $payloads+=@([pscustomobject]@{Package=$record.Key;InstalledHashes=$hashes})
    }
    return [pscustomobject]@{Kind='snapshot';Action=$Action;Package=$Package;Utc=[DateTime]::UtcNow.ToString('o');InstalledExtensions=$installed;Payloads=$payloads;ExpectedThemeNames=@($state.Packages | ForEach-Object { Get-PackageThemes (Get-ThemePackage $_.Key) } | ForEach-Object Name)}
}
try {
    if ($Action -cne 'Inspect') {
        $profileProcesses=@(Get-CimInstance Win32_Process -Filter "Name='devenv.exe'" | Where-Object { $_.CommandLine -match [regex]::Escape($state.RootSuffix) })
        if ($profileProcesses.Count) { throw 'Close the IDE for this dedicated lifecycle profile before changing its installed packages.' }
    }
    if ($Action -ceq 'Initialize') {
        $creator=Join-Path $instance.installationPath 'VSSDK/VisualStudioIntegration/Tools/Bin/CreateExpInstance.exe'
        Invoke-LifecycleProcess 'create-profile' $creator @('/Create','/VSInstance=18.0',"/RootSuffix:$($state.RootSuffix)".Replace('/RootSuffix:','/RootSuffix='))
    }
    elseif ($Action -cin @('Install','Upgrade','Uninstall')) {
        $spec=Get-ThemePackage $Package
        if ($spec.Distribution -cne 'public') { throw 'Only public pilots may share this lifecycle profile.' }
        $existing=@($state.Packages | Where-Object Key -CEQ $Package)
        if ($Action -ceq 'Install' -and $existing.Count) { throw 'Package already installed; use Upgrade.' }
        if ($Action -cne 'Install' -and $existing.Count -ne 1) { throw 'Expected exactly one existing package.' }
        $installerArgs=@('/quiet',"/instanceIds:$($state.InstanceId)","/rootSuffix:$($state.RootSuffix)","/logFile:$(Join-Path $directory "$Action-$Package-installer.log")")
        if ($Action -ceq 'Uninstall') { $installerArgs+=@("/uninstall:$($spec.Identity)") }
        else {
            $inspectArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-VsixPackage.ps1'),'-Package',$Package)
            $version=$spec.Version
            if ($Action -ceq 'Upgrade') {
                $fixture=Get-Content -LiteralPath $UpgradeFixturePath -Raw | ConvertFrom-Json
                if (-not $fixture.TestOnly -or $fixture.PackageKey -cne $Package -or $fixture.Identity -cne $spec.Identity -or [version]$fixture.Version -le [version]$existing[0].Version) { throw 'Invalid test-only upgrade fixture.' }
                $VsixPath=$fixture.VsixPath; $version=$fixture.Version
                $inspectArgs+=@('-CatalogPath',$fixture.CatalogPath,'-SourceManifestPath',$fixture.SourceManifestPath)
                $before=Get-VsixPkgdefHashes $existing[0].VsixPath; $after=Get-VsixPkgdefHashes $VsixPath
                Assert-VisualAuditThemeInventory -Packaged $after -ExpectedNames @($before.Keys)
                foreach ($name in $before.Keys) { if ($before[$name] -cne $after[$name]) { throw "Upgrade changes theme payload: $name." } }
            }
            $VsixPath=(Resolve-Path -LiteralPath $VsixPath).Path
            Invoke-LifecycleProcess "$Action-$Package-inspect" 'powershell.exe' ($inspectArgs+@('-VsixPath',$VsixPath))
            $installerArgs+=@($VsixPath)
        }
        Invoke-LifecycleProcess "$Action-$Package" (Join-Path $ide 'VSIXInstaller.exe') $installerArgs
        $state.Packages=@($state.Packages | Where-Object Key -CNE $Package)
        if ($Action -cne 'Uninstall') { $state.Packages+=@([pscustomobject]@{Key=$Package;Identity=$spec.Identity;Version=$version;VsixPath=$VsixPath;VsixSha256=(Get-FileHash -LiteralPath $VsixPath).Hash}) }
        # The installer succeeded even if configuration refresh later fails. Retain that
        # fact so Refresh can resume without reinstalling or losing upgrade attribution.
        $state | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $StatePath -Encoding UTF8
        Invoke-LifecycleProcess "$Action-$Package-refresh" (Join-Path $ide 'devenv.exe') @('/RootSuffix',$state.RootSuffix,'/UpdateConfiguration')
    }
    elseif ($Action -ceq 'Refresh') {
        [void](Get-ProfileSnapshot)
        Invoke-LifecycleProcess 'resume-refresh' (Join-Path $ide 'devenv.exe') @('/RootSuffix',$state.RootSuffix,'/UpdateConfiguration')
    }
    $snapshot=Get-ProfileSnapshot
    $state.Events+=@($snapshot)
    Write-Host "$Action verified in $($state.RootSuffix): $(@($snapshot.ExpectedThemeNames).Count) expected themes."
}
catch { $state.Events+=@([pscustomobject]@{Kind='failure';Action=$Action;Package=$Package;Message=$_.Exception.Message;Utc=[DateTime]::UtcNow.ToString('o')}); throw }
finally { $state | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $StatePath -Encoding UTF8 }

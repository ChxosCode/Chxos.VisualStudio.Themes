[CmdletBinding()]
param([string]$VsixDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'VisualAudit.Common.psm1') -Force
$project=Split-Path -Parent $PSScriptRoot
if (-not $VsixDirectory) { $VsixDirectory=Join-Path $project 'bin/Release' }
$catalog=Read-PackageCatalog
$themes=Get-Content (Join-Path $project 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('theme-packaging-tests-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$script:count=0
function Test-Case([string]$Name,[scriptblock]$Body) { & $Body; $script:count++; Write-Host "PASS $Name" }
function Reject-Catalog([scriptblock]$Mutation,[string]$Message) {
    $copy=$catalog | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    & $Mutation $copy
    $errorText=$null
    try { Assert-PackageCatalog -Catalog $copy -Themes $themes } catch { $errorText=$_.Exception.Message }
    if (-not $errorText -or $errorText -notmatch $Message) { throw "Expected catalog rejection '$Message'; got '$errorText'." }
}
function Invoke-Inspector([string]$Path,[string]$Key,[bool]$Pass,[string]$Diagnostic) {
    $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try { $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-VsixPackage.ps1') -VsixPath $Path -Package $Key 2>&1 | Out-String; $code=$LASTEXITCODE }
    finally { $ErrorActionPreference=$previous }
    if (($Pass -and $code -ne 0) -or (-not $Pass -and ($code -eq 0 -or ($Diagnostic -and $output -notmatch $Diagnostic)))) { throw "Unexpected inspector result ($code): $output" }
}
function Mutate-Archive([scriptblock]$Mutation,[string]$Diagnostic) {
    $copy=Join-Path $fixture 'mutation.vsix'
    Copy-Item -LiteralPath $foundationVsix -Destination $copy -Force
    $zip=[IO.Compression.ZipFile]::Open($copy,[IO.Compression.ZipArchiveMode]::Update)
    try { & $Mutation $zip } finally { $zip.Dispose() }
    Invoke-Inspector $copy 'foundation' $false $Diagnostic
}
function Replace-Manifest($Zip,[scriptblock]$Mutation) {
    $entry=$Zip.GetEntry('extension.vsixmanifest'); $reader=[IO.StreamReader]::new($entry.Open())
    try { $text=$reader.ReadToEnd() } finally { $reader.Dispose() }
    $entry.Delete(); $writer=[IO.StreamWriter]::new($Zip.CreateEntry('extension.vsixmanifest').Open())
    try { $writer.Write((& $Mutation $text)) } finally { $writer.Dispose() }
}
try {
    Test-Case 'valid catalog reconciles thirteen themes' { Assert-PackageCatalog $catalog $themes }
    Test-Case 'product PNG and editable SVG assets survive source-control ignore rules' {
        foreach ($package in $catalog.Packages) {
            foreach ($asset in @($package.Icon,$package.PreviewImage)) {
                foreach ($path in @($asset,[IO.Path]::ChangeExtension($asset,'.svg'))) {
                    if (-not (Test-Path -LiteralPath (Join-Path $project $path))) { throw "Missing product asset source: $path" }
                    & git -C $project check-ignore --no-index -q -- $path
                    if ($LASTEXITCODE -ne 1) { throw "Product asset is ignored or Git inspection failed: $path" }
                }
            }
        }
    }
    Test-Case 'malformed membership scalar' { Reject-Catalog {param($c) $c.Packages[0].Themes='Foundation.vstheme'} 'malformed package membership' }
    Test-Case 'duplicate package keys' { Reject-Catalog {param($c) $c.Packages[1].Key='foundation'} 'duplicate package key' }
    Test-Case 'duplicate package identities' { Reject-Catalog {param($c) $c.Packages[1].Identity=$c.Packages[0].Identity} 'duplicate package identity' }
    Test-Case 'unknown theme' { Reject-Catalog {param($c) $c.Packages[0].Themes=@('Unknown.vstheme')} 'Unknown or duplicate package member' }
    Test-Case 'duplicate member' { Reject-Catalog {param($c) $c.Packages[0].Themes=@('Foundation.vstheme','Foundation.vstheme')} 'duplicate package member' }
    Test-Case 'public ownership overlap' { Reject-Catalog {param($c) $c.Packages[1].Themes=@('Foundation.vstheme')} 'Duplicate public ownership' }
    Test-Case 'missing public/deferred owner' { Reject-Catalog {param($c) $c.DeferredPublicThemes=@($c.DeferredPublicThemes | Select-Object -Skip 1)} 'do not reconcile' }
    Test-Case 'deferred and public overlap' { Reject-Catalog {param($c) $c.DeferredPublicThemes+=@('Foundation.vstheme')} 'already owned deferred' }
    Test-Case 'invalid version' { Reject-Catalog {param($c) $c.Packages[0].Version='1.0-preview'} 'Invalid package version' }
    Test-Case 'version segment overflow' { Reject-Catalog {param($c) $c.Packages[0].Version='1.0.65536'} 'exceeds 65535' }
    Test-Case 'unsafe asset traversal' { Reject-Catalog {param($c) $c.Packages[0].Icon='../icon.png'} 'Unsafe package asset' }
    Test-Case 'missing asset' { Reject-Catalog {param($c) $c.Packages[0].Icon='assets/missing.png'} 'Missing package asset' }
    Test-Case 'internal pack must remain complete' { Reject-Catalog {param($c) $c.Packages[3].Themes=@('Foundation.vstheme')} 'contain every theme' }
    Test-Case 'unknown selector' {
        $failed=$false; try { Get-ThemePackage 'FOUNDATION' | Out-Null } catch { $failed=$true }
        if (-not $failed) { throw 'Noncanonical selector accepted.' }
    }
    Test-Case 'pilot runtime defaults and All use membership' {
        $p=Get-ThemePackage 'cosmora'
        if (@(Resolve-PackageThemeNames $p).Count -ne 4 -or @(Resolve-PackageThemeNames $p @('All')).Count -ne 4) { throw 'Incorrect Cosmora runtime scope.' }
        if ((Resolve-PackageThemeNames (Get-ThemePackage 'all-dev')) -cne 'Nightglass') { throw 'Development runtime default changed.' }
        $failed=$false; try { Resolve-PackageThemeNames $p @('Foundation') | Out-Null } catch { $failed=$true }
        if (-not $failed) { throw 'Cross-package runtime theme accepted.' }
    }
    $devSpec=Get-ThemePackage 'all-dev'
    $allDev=Join-Path $VsixDirectory ('all-dev/all-dev-'+$devSpec.Version+'.vsix')
    $shared=Get-VsixPkgdefHashes $allDev
    foreach ($p in $catalog.Packages) {
        $vsix=Join-Path $VsixDirectory "$($p.Key)/$($p.Key)-$($p.Version).vsix"
        Test-Case "$($p.Key) exact archive and shared payloads" {
            Invoke-Inspector $vsix $p.Key $true ''
            $hashes=Get-VsixPkgdefHashes $vsix
            foreach ($name in $hashes.Keys) { if ($hashes[$name] -cne $shared[$name]) { throw "Payload differs for $name." } }
        }
    }
    $foundationSpec=Get-ThemePackage 'foundation'
    $foundationVsix=Join-Path $VsixDirectory ('foundation/foundation-'+$foundationSpec.Version+'.vsix')
    Test-Case 'incorrect package context' { Invoke-Inspector $foundationVsix 'pinknoise' $false 'Expected one.*Pinknoise.pkgdef' }
    Test-Case 'missing payload' { Mutate-Archive {param($z) $z.GetEntry('Foundation.pkgdef').Delete()} 'Expected one.*Foundation.pkgdef' }
    Test-Case 'extra payload' { Mutate-Archive {param($z) $s=$z.CreateEntry('Pinknoise.pkgdef').Open();$s.Dispose()} 'Unexpected archive entry' }
    Test-Case 'duplicate payload' { Mutate-Archive {param($z) $s=$z.CreateEntry('Foundation.pkgdef').Open();$s.Dispose()} 'Duplicate archive entry' }
    Test-Case 'wrong identity' { Mutate-Archive {param($z) Replace-Manifest $z {param($t) $t.Replace('Chxos.Foundation.VisualStudio.Theme','Chxos.Wrong.Theme')}} 'Unexpected VSIX identity' }
    Test-Case 'wrong installer JSON identity' { Mutate-Archive {
        param($z) $e=$z.GetEntry('manifest.json');$r=[IO.StreamReader]::new($e.Open());try{$t=$r.ReadToEnd()}finally{$r.Dispose()};$e.Delete()
        $w=[IO.StreamWriter]::new($z.CreateEntry('manifest.json').Open());try{$w.Write($t.Replace('Chxos.Foundation.VisualStudio.Theme','Chxos.Wrong.Theme'))}finally{$w.Dispose()}
    } 'manifest.json identity/version' }
    Test-Case 'wrong version' { Mutate-Archive {param($z) Replace-Manifest $z {param($t) $t.Replace(('Version="'+$foundationSpec.Version+'"'),'Version="65535.65535.65535"')}} 'VSIX version' }
    Test-Case 'wrong presentation asset' { Mutate-Archive {param($z) $z.GetEntry('assets/icon.png').Delete();$s=$z.CreateEntry('assets/icon.png').Open();$s.WriteByte(1);$s.Dispose()} 'Wrong presentation asset' }
    Test-Case 'wrong presentation metadata' { Mutate-Archive {param($z) Replace-Manifest $z {param($t) $t.Replace('<DisplayName>Foundation Theme</DisplayName>','<DisplayName>Pinknoise Theme</DisplayName>')}} 'Manifest DisplayName' }
    Test-Case 'managed payload forbidden' { Mutate-Archive {param($z) $s=$z.CreateEntry('unexpected.dll').Open();$s.Dispose()} 'Managed assemblies' }
    Test-Case 'wrong registration GUID' { Mutate-Archive {
        param($z) $e=$z.GetEntry('Foundation.pkgdef');$r=[IO.StreamReader]::new($e.Open());try{$t=$r.ReadToEnd()}finally{$r.Dispose()};$e.Delete()
        $w=[IO.StreamWriter]::new($z.CreateEntry('Foundation.pkgdef').Open());try{$w.Write($t.Replace('41f1b4f7-6f5d-40ba-8182-80ee4f3831f7','00000000-0000-0000-0000-000000000000'))}finally{$w.Dispose()}
    } 'expected theme GUID' }
    Test-Case 'runtime readiness remains blocked and scoped to Foundation' {
        $out=Join-Path $fixture 'readiness.json'
        & powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'Test-ReleaseReadiness.ps1') -VsixPath $foundationVsix -Package foundation -OutputPath $out *> (Join-Path $fixture 'readiness.log')
        if ($LASTEXITCODE -ne 1) { throw 'Missing runtime evidence did not block release.' }
        $report=Get-Content $out -Raw | ConvertFrom-Json
        if ($report.Ready -or $report.SchemaVersion -ne 2 -or $report.PackageKey -cne 'foundation' -or @($report.Scenarios | Where-Object Theme -CNE 'Foundation').Count) { throw 'Incorrect package runtime report.' }
    }
    Test-Case 'exact installed extension rejects duplicate consumers' {
        $profile=Join-Path $fixture '18.0_12345678PackagingFixture'
        $first=Join-Path $profile 'Extensions/one'; $second=Join-Path $profile 'Extensions/two'
        [void][IO.Directory]::CreateDirectory($first); [void][IO.Directory]::CreateDirectory($second)
        foreach ($dir in @($first,$second)) {
            Copy-Item (Join-Path $project 'packaging/generated/foundation/source.extension.vsixmanifest') (Join-Path $dir 'extension.vsixmanifest')
            Copy-Item (Join-Path $VsixDirectory 'foundation/Foundation.pkgdef') (Join-Path $dir 'Foundation.pkgdef')
        }
        $failure=$null
        try { Get-InstalledPkgdefHashes -RootSuffix PackagingFixture -ProfileDirectory $profile -ExtensionIdentity $foundationSpec.Identity -Names @('Foundation.pkgdef') | Out-Null } catch { $failure=$_.Exception.Message }
        if ($failure -notmatch 'Expected one installed extension') { throw "Duplicate installation accepted: $failure" }
        Remove-Item -LiteralPath (Join-Path $second 'extension.vsixmanifest')
        $hashes=Get-InstalledPkgdefHashes -RootSuffix PackagingFixture -ProfileDirectory $profile -ExtensionIdentity $foundationSpec.Identity -Names @('Foundation.pkgdef')
        if (-not $hashes['Foundation.pkgdef'].Path.StartsWith($first)) { throw 'Wrong extension directory selected.' }
        Copy-Item (Join-Path $project 'packaging/generated/all-dev/source.extension.vsixmanifest') (Join-Path $second 'extension.vsixmanifest')
        $failure=$null
        try { Get-InstalledPkgdefHashes -RootSuffix PackagingFixture -ProfileDirectory $profile -ExtensionIdentity $foundationSpec.Identity -Names @('Foundation.pkgdef') | Out-Null } catch { $failure=$_.Exception.Message }
        if ($failure -notmatch 'Ambiguous installed payload') { throw 'An overlapping collection registration was accepted.' }
        $failure=$null
        try { Get-InstalledPkgdefHashes -RootSuffix Fixture -ProfileDirectory $profile -ExtensionIdentity $foundationSpec.Identity -Names @('Foundation.pkgdef') | Out-Null } catch { $failure=$_.Exception.Message }
        if ($failure -notmatch 'exact Visual Studio 18 root suffix') { throw 'A suffix of another profile was accepted.' }
    }
    Test-Case 'runtime environment rejects another package, version, membership, and archive' {
        $hashes=Get-VsixPkgdefHashes $foundationVsix
        $installed=@{}; foreach ($name in $hashes.Keys) { $installed[$name]=@{Hash=$hashes[$name]} }
        $environment=@{SchemaVersion=2;PackageKey='foundation';PackageIdentity=$foundationSpec.Identity;PackageVersion=$foundationSpec.Version;Themes=@('Foundation');VsixSha256=(Get-FileHash $foundationVsix).Hash;InstallationVersion='18.9.12120.119';InstalledHashes=$installed}
        foreach ($kind in @('identity','version','membership','archive','valid','legacy')) {
            $copy=$environment | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            switch ($kind) {
                identity { $copy.PackageIdentity=(Get-ThemePackage 'pinknoise').Identity }
                version { $copy.PackageVersion='1.0.1' }
                membership { $copy.Themes=@('Pinknoise') }
                archive { $copy.VsixSha256='0'*64 }
                legacy { foreach ($field in @('SchemaVersion','PackageKey','PackageIdentity','PackageVersion','Themes')) { $copy.PSObject.Properties.Remove($field) } }
            }
            $envPath=Join-Path $fixture ('environment-'+$kind+'.json'); $out=Join-Path $fixture ('readiness-'+$kind+'.json')
            $copy | ConvertTo-Json -Depth 8 | Set-Content $envPath -Encoding UTF8
            & powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'Test-ReleaseReadiness.ps1') -VsixPath $foundationVsix -Package foundation -EnvironmentPath $envPath -OutputPath $out *> (Join-Path $fixture ('readiness-'+$kind+'.log'))
            if ($LASTEXITCODE -ne 1) { throw 'Required evidence or unresolved consumers no longer block release.' }
            $report=Get-Content $out -Raw | ConvertFrom-Json
            $diagnostic=switch ($kind) { identity {'identity/version mismatch'} version {'identity/version mismatch'} membership {'membership mismatch'} archive {'Artifact/version mismatch'} default {'Installed payload hashes match'} }
            if ($report.EnvironmentStatus -notmatch $diagnostic) { throw "Incorrect $kind evidence assessment: $($report.EnvironmentStatus)" }
        }
    }
    . (Join-Path $PSScriptRoot 'PackageBuildTest.Common.ps1')
    Test-Case 'build-test selectors default to every catalog package' {
        $selected=@(Get-BuildTestPackages $null)
        if (($selected.Key -join '|') -cne ($catalog.Packages.Key -join '|')) { throw 'Build-test defaults omit catalog products.' }
    }
    foreach ($suite in @('Test-PackageCleanBuild.Tests.ps1','Test-PackageBuildIsolation.Tests.ps1')) {
        foreach ($keys in @("@('unknown')","@('foundation','foundation')","@('Foundation')","@()")) {
            Test-Case ("invalid selection before side effects: $suite $keys") {
                $out=Join-Path $fixture ('invalid-'+[Guid]::NewGuid().ToString('N'))
                $scriptPath=Join-Path $PSScriptRoot $suite
                $command="& '"+$scriptPath.Replace("'","''")+"' -Package "+$keys+" -OutputDirectory '"+$out.Replace("'","''")+"'"
                $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
                try { $log=& powershell.exe -NoProfile -Command $command 2>&1 | Out-String; $code=$LASTEXITCODE }
                finally { $ErrorActionPreference=$previous }
                if ($code -eq 0 -or $log -notmatch 'Unknown package key|Select distinct package keys') { throw "Wrong selection failure: $log" }
                if (Test-Path -LiteralPath $out) { throw 'Invalid selection created build evidence.' }
            }
        }
    }
    Write-Host "All $script:count packaging regression cases pass."
}
finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'theme-packaging-tests-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

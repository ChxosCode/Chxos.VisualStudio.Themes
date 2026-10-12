[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
$project=Split-Path -Parent $PSScriptRoot
$scratch=Join-Path $project ('obj/catalog-probe-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$stray=Join-Path $scratch 'Unlisted.vstheme'
try {
    Copy-Item -LiteralPath (Join-Path $project 'Amberroot.vstheme') -Destination $stray
    $catalog = Read-PackageCatalog
    foreach ($package in $catalog.Packages) {
        $output = & dotnet msbuild (Join-Path $project 'Chxos.VisualStudio.Themes.csproj') '-t:AddVsThemeFile' '-getItem:VsTheme' '-getProperty:BaseIntermediateOutputPath,MSBuildProjectExtensionsPath,OutputPath,ThemePackageIdentity' '-verbosity:quiet' "-p:ThemePackage=$($package.Key)" '-p:Configuration=Release' | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Compiler input evaluation failed: $output" }
        $evaluation = $output | ConvertFrom-Json
        $actual = @($evaluation.Items.VsTheme | ForEach-Object Identity | Sort-Object)
        $expected = @($package.Themes | Sort-Object)
        if (($actual -join '|') -cne ($expected -join '|')) { throw "Compiler membership differs for $($package.Key)." }
        if ($evaluation.Properties.ThemePackageIdentity -cne $package.Identity) { throw 'Wrong evaluated package identity.' }
        foreach ($property in @('BaseIntermediateOutputPath','MSBuildProjectExtensionsPath','OutputPath')) {
            if ($evaluation.Properties.$property -notmatch [regex]::Escape($package.Key)) { throw "Unisolated $property for $($package.Key)." }
        }
    }
    $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try { $output = & dotnet msbuild (Join-Path $project 'Chxos.VisualStudio.Themes.csproj') '-t:ValidateThemePackageSelection' '-p:ThemePackage=unknown' '-verbosity:quiet' 2>&1 | Out-String; $code=$LASTEXITCODE }
    finally { $ErrorActionPreference=$previous }
    if ($code -eq 0 -or $output -notmatch 'Unknown ThemePackage') { throw 'Unknown compiler package was not rejected.' }
    Write-Host 'Compiler catalog regressions passed: four isolated selections, stray theme excluded, invalid selector rejected.'
}
finally {
    $resolved=[IO.Path]::GetFullPath($scratch)
    $allowed=[IO.Path]::GetFullPath((Join-Path $project 'obj')).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'catalog-probe-*') { throw 'Unsafe catalog test cleanup path.' }
    if (Test-Path -LiteralPath $stray) {Remove-Item -LiteralPath $stray -Force}
    Remove-Item -LiteralPath $resolved -Force
}

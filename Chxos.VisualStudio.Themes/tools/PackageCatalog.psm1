Set-StrictMode -Version Latest

function Resolve-PackageAsset {
    param([string]$ProjectDirectory, [string]$Path)
    if (-not $Path -or $Path -match '(^[\\/]|[:*?<>|"\x00-\x1f]|(^|[\\/])\.\.?([\\/]|$))') { throw "Unsafe package asset path: '$Path'." }
    $root = [IO.Path]::GetFullPath($ProjectDirectory).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath((Join-Path $root $Path))
    if (-not $resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "Asset escapes project: '$Path'." }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing package asset: '$Path'." }
    return $resolved
}

function Assert-PackageCatalog {
    param([Parameter(Mandatory)]$Catalog, [Parameter(Mandatory)][object[]]$Themes,
          [string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot))
    if ($Catalog.SchemaVersion -ne 1 -or $Catalog.Packages -isnot [array] -or @($Catalog.Packages).Count -eq 0 -or $Catalog.DeferredPublicThemes -isnot [array]) { throw 'Invalid package catalog schema or empty packages.' }
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($theme in $Themes) {
        if ($theme.File -cnotmatch '^[A-Za-z][A-Za-z0-9]*\.vstheme$' -or -not $files.Add($theme.File)) { throw 'Invalid or duplicate theme file identity.' }
    }
    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $owners = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($package in $Catalog.Packages) {
        if ($package.Key -cnotmatch '^[a-z][a-z0-9-]*$' -or -not $keys.Add($package.Key)) { throw "Invalid or duplicate package key: '$($package.Key)'." }
        if ($package.Identity -cnotmatch '^[A-Za-z][A-Za-z0-9.]+$' -or $package.Identity.Length -gt 100 -or -not $ids.Add($package.Identity)) { throw "Invalid or duplicate package identity: '$($package.Identity)'." }
        if ($package.Version -cnotmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw "Invalid package version: '$($package.Version)'." }
        foreach ($part in $package.Version.Split('.')) { if ([decimal]$part -gt 65535) { throw 'Package version segment exceeds 65535.' } }
        if ($package.Publisher -cne 'Chxos') { throw 'Unexpected package publisher.' }
        if (-not $package.DisplayName -or $package.DisplayName.Length -gt 50) { throw 'Invalid package display name.' }
        if (-not $package.Description -or $package.Description.Length -gt 1000 -or $package.Description -notmatch 'Visual Studio 2026') { throw 'Invalid package description.' }
        if (-not $package.Tags -or $package.Tags.Length -gt 100) { throw 'Invalid package tags.' }
        if ($package.Distribution -cnotin @('public','internal')) { throw 'Invalid package distribution.' }
        $members = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        if ($package.Themes -isnot [array] -or @($package.Themes).Count -eq 0) { throw 'Empty or malformed package membership.' }
        foreach ($file in $package.Themes) {
            if (-not $files.Contains($file) -or -not $members.Add($file)) { throw "Unknown or duplicate package member: '$file'." }
            if ($package.Distribution -ceq 'public' -and -not $owners.Add($file)) { throw "Duplicate public ownership: '$file'." }
        }
        foreach ($asset in @($package.Icon, $package.PreviewImage)) {
            if ($asset -cnotmatch '\.png$') { throw 'Packaged presentation assets must be PNG.' }
            [void](Resolve-PackageAsset $ProjectDirectory $asset)
        }
    }
    foreach ($file in $Catalog.DeferredPublicThemes) {
        if (-not $files.Contains($file) -or -not $owners.Add($file)) { throw "Unknown, duplicate, or already owned deferred theme: '$file'." }
    }
    if ($owners.Count -ne $files.Count) { throw 'Public ownership and deferred themes do not reconcile with the theme catalog.' }
    $development = @($Catalog.Packages | Where-Object Key -CEQ 'all-dev')
    if ($development.Count -ne 1 -or $development[0].Distribution -cne 'internal' -or @($development[0].Themes).Count -ne $files.Count) { throw 'all-dev must be internal and contain every theme.' }
}

function Read-PackageCatalog {
    param([string]$CatalogPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'authoring/PackageCatalog.json'),
          [string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot))
    $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $themes = Get-Content -LiteralPath (Join-Path $ProjectDirectory 'authoring/ThemeCatalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-PackageCatalog -Catalog $catalog -Themes $themes -ProjectDirectory $ProjectDirectory
    return $catalog
}

function Get-ThemePackage {
    param([string]$Package = 'all-dev', $Catalog = (Read-PackageCatalog))
    $matches = @($Catalog.Packages | Where-Object Key -CEQ $Package)
    if ($matches.Count -ne 1) { throw "Unknown package '$Package'. Use an exact catalog key." }
    return $matches[0]
}

function Get-PackageThemes {
    param([Parameter(Mandatory)]$Package, [string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot))
    $themes = Get-Content -LiteralPath (Join-Path $ProjectDirectory 'authoring/ThemeCatalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($file in $Package.Themes) { $themes | Where-Object File -CEQ $file }
}

function Resolve-PackageThemeNames {
    param([Parameter(Mandatory)]$Package, [string[]]$ThemeName)
    $names = @(Get-PackageThemes $Package | ForEach-Object Name)
    if (-not $ThemeName) { if ($Package.Key -ceq 'all-dev') { return @('Nightglass') }; return $names }
    foreach ($name in $ThemeName) { if ($name -cne 'All' -and $name -cnotin $names) { throw "Theme '$name' is outside package '$($Package.Key)'." } }
    if ($ThemeName -ccontains 'All') { return $names }
    return @($ThemeName | Select-Object -Unique)
}

Export-ModuleMember -Function Resolve-PackageAsset, Assert-PackageCatalog, Read-PackageCatalog, Get-ThemePackage, Get-PackageThemes, Resolve-PackageThemeNames

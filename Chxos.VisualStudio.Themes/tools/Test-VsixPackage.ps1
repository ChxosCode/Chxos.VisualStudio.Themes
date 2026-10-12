[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $VsixPath,

    [string] $SourceManifestPath,
    [string] $Package = 'all-dev',
    [string] $CatalogPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
$project = Split-Path -Parent $PSScriptRoot
$catalogArguments = @{}
if ($CatalogPath) { $catalogArguments.CatalogPath = $CatalogPath }
$packageCatalog = Read-PackageCatalog @catalogArguments
$selectedPackage = Get-ThemePackage -Package $Package -Catalog $packageCatalog

$failures = New-Object System.Collections.Generic.List[string]
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Add-Failure {
    param([string] $Message)
    $failures.Add($Message)
}

function Read-ZipEntryText {
    param([IO.Compression.ZipArchiveEntry] $Entry)
    $stream = $Entry.Open()
    $reader = New-Object IO.StreamReader($stream)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$expectedThemes = [ordered] @{
    'Amberroot.pkgdef' = @('Amberroot', '{e102d760-8591-40ac-bf78-47a8ba8df9c2}')
    'Biolume.pkgdef' = @('Biolume', '{4d9cd7e1-6516-41b7-bb91-882f6c8a381e}')
    'Nullsector.pkgdef' = @('Nullsector', '{53f3c5be-5371-4322-9525-300e6a0aada5}')
    'Aquatoxic.pkgdef' = @('Aquatoxic', '{e38b0d54-a4cf-4b53-ba35-e09d1fdc3578}')
    'Cosmora.pkgdef' = @('Cosmora', '{27dc80d5-8c3f-4fb7-ab87-84d5e4ffb399}')
    'CosmoraBlueshift.pkgdef' = @('Cosmora Blueshift', '{ff442c60-e3fc-421e-86fb-5f808e41ff1c}')
    'CosmoraUltraviolet.pkgdef' = @('Cosmora Ultraviolet', '{120561ee-01c5-4016-b41b-615a59ba0d96}')
    'CosmoraRedshift.pkgdef' = @('Cosmora Redshift', '{dadccee6-c0fa-446d-a412-4add268588c7}')
    'Foundation.pkgdef' = @('Foundation', '{41f1b4f7-6f5d-40ba-8182-80ee4f3831f7}')
    'Hardline.pkgdef' = @('Hardline', '{f1ac81a9-90de-4001-957f-94f970c8cd4a}')
    'Nightglass.pkgdef' = @('Nightglass', '{74ebffcf-0561-49d5-b63e-6c0a26536b32}')
    'Pinknoise.pkgdef' = @('Pinknoise', '{2c24e257-cbed-4c27-877c-39b52a813782}')
    'Silverphase.pkgdef' = @('Silverphase', '{12e4fd10-175e-43c9-956e-60c64f049dd9}')
}
$themeCatalog = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json
if ($themeCatalog.Count -ne 13) { throw 'Theme catalog must retain thirteen identities.' }
foreach ($catalogEntry in $themeCatalog) {
    if (-not $expectedThemes.Contains($catalogEntry.Pkgdef) -or $expectedThemes[$catalogEntry.Pkgdef][0] -cne $catalogEntry.Name -or $expectedThemes[$catalogEntry.Pkgdef][1] -cne $catalogEntry.Guid) { throw 'Catalog differs from independent package identity pins.' }
}

$identityPins = $expectedThemes
$expectedThemes = [ordered]@{}
foreach ($theme in Get-PackageThemes $selectedPackage) { $expectedThemes[$theme.Pkgdef] = $identityPins[$theme.Pkgdef] }

$requiredEntries = @(
    '[Content_Types].xml',
    'catalog.json',
    'extension.vsixmanifest',
    'manifest.json',
    'LICENSE.txt',
    'assets/icon.png',
    'assets/preview.png'
)

if ([string]::IsNullOrWhiteSpace($SourceManifestPath)) {
    $SourceManifestPath = Join-Path $project "packaging/generated/$Package/source.extension.vsixmanifest"
}
$resolvedSourceManifestPath = [IO.Path]::GetFullPath($SourceManifestPath)
if (-not (Test-Path -LiteralPath $resolvedSourceManifestPath -PathType Leaf)) {
    Write-Error "Source VSIX manifest does not exist: $resolvedSourceManifestPath"
    exit 1
}

try {
    [xml] $sourceManifest = [IO.File]::ReadAllText($resolvedSourceManifestPath)
    $sourceNamespace = New-Object Xml.XmlNamespaceManager($sourceManifest.NameTable)
    $sourceNamespace.AddNamespace('v', 'http://schemas.microsoft.com/developer/vsx-schema/2011')
    $sourceIdentity = $sourceManifest.SelectSingleNode('/v:PackageManifest/v:Metadata/v:Identity', $sourceNamespace)
    if ($null -eq $sourceIdentity) {
        throw 'Source manifest has no Metadata/Identity element.'
    }
    if ($sourceIdentity.Id -cne $selectedPackage.Identity) {
        throw "Unexpected source VSIX identity '$($sourceIdentity.Id)'."
    }
    if ($sourceIdentity.Publisher -cne $selectedPackage.Publisher) {
        throw "Unexpected source VSIX publisher '$($sourceIdentity.Publisher)'."
    }
    $expectedVersion = [string] $selectedPackage.Version
    if ($sourceIdentity.Version -cne $expectedVersion) { throw 'Source manifest version differs from package catalog.' }
    $expectedPreview = $selectedPackage.Preview.ToString().ToLowerInvariant()
    $sourcePreview = @($sourceManifest.SelectNodes('/v:PackageManifest/v:Metadata/v:Preview', $sourceNamespace))
    if ($sourcePreview.Count -ne 1 -or $sourcePreview[0].InnerText -cne $expectedPreview) { throw 'Source manifest Preview differs from package catalog.' }
    if ($expectedVersion -notmatch '^\d+(\.\d+){1,3}$') {
        throw "Source VSIX version '$expectedVersion' is not a valid numeric version."
    }
}
catch {
    Write-Error "Unable to read source VSIX manifest '$resolvedSourceManifestPath': $($_.Exception.Message)"
    exit 1
}

$resolvedPath = [IO.Path]::GetFullPath($VsixPath)
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
    Write-Error "VSIX does not exist: $resolvedPath"
    exit 1
}

try {
    $archive = [IO.Compression.ZipFile]::OpenRead($resolvedPath)
}
catch {
    Write-Error "Unable to open VSIX '$resolvedPath' as a ZIP archive: $($_.Exception.Message)"
    exit 1
}

try {
    $entriesByName = @{}
    foreach ($entry in $archive.Entries) {
        $normalizedName = $entry.FullName.Replace('\', '/')
        if (-not $entriesByName.ContainsKey($normalizedName)) {
            $entriesByName[$normalizedName] = New-Object System.Collections.Generic.List[object]
        }
        $entriesByName[$normalizedName].Add($entry)
    }

    $allowedEntries = @($requiredEntries) + @($expectedThemes.Keys)
    foreach ($name in $entriesByName.Keys) {
        if ($name -cnotin $allowedEntries) { Add-Failure "Unexpected archive entry '$name'." }
        if ($entriesByName[$name].Count -ne 1) { Add-Failure "Duplicate archive entry '$name'." }
    }
    foreach ($assetSpec in @(@('assets/icon.png',$selectedPackage.Icon), @('assets/preview.png',$selectedPackage.PreviewImage))) {
        $entry = $archive.GetEntry($assetSpec[0])
        if ($null -ne $entry) {
            $stream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
            try { $actualHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
            finally { $stream.Dispose(); $sha.Dispose() }
            $expectedHash = (Get-FileHash -LiteralPath (Resolve-PackageAsset $project $assetSpec[1]) -Algorithm SHA256).Hash
            if ($actualHash -cne $expectedHash) { Add-Failure "Wrong presentation asset: $($assetSpec[0])." }
        }
    }
    foreach ($entryName in $requiredEntries) {
        $count = if ($entriesByName.ContainsKey($entryName)) { $entriesByName[$entryName].Count } else { 0 }
        if ($count -ne 1) {
            Add-Failure "Expected one '$entryName' entry; found $count."
        }
    }
    try {
        $packageManifest = Read-ZipEntryText $archive.GetEntry('manifest.json') | ConvertFrom-Json
        if ($packageManifest.id -cne $selectedPackage.Identity -or $packageManifest.vsixId -cne $selectedPackage.Identity -or $packageManifest.version -cne $expectedVersion) { Add-Failure 'manifest.json identity/version differs from the selected package.' }
        $installerCatalog = Read-ZipEntryText $archive.GetEntry('catalog.json') | ConvertFrom-Json
        if ($installerCatalog.info.id -cne ($selectedPackage.Identity+',version='+$expectedVersion)) { Add-Failure 'catalog.json identity/version differs from the selected package.' }
        $vsixRecords = @($installerCatalog.packages | Where-Object type -CEQ 'Vsix')
        $componentRecords = @($installerCatalog.packages | Where-Object type -CEQ 'Component')
        if ($vsixRecords.Count -ne 1 -or $vsixRecords[0].id -cne $selectedPackage.Identity -or $vsixRecords[0].vsixId -cne $selectedPackage.Identity -or $vsixRecords[0].version -cne $expectedVersion) { Add-Failure 'catalog.json VSIX registration differs from the selected package.' }
        if ($componentRecords.Count -ne 1 -or $componentRecords[0].id -cne ('Component.'+$selectedPackage.Identity) -or $componentRecords[0].version -cne $expectedVersion -or $componentRecords[0].dependencies.($selectedPackage.Identity) -cne $expectedVersion) { Add-Failure 'catalog.json component registration differs from the selected package.' }
    }
    catch { Add-Failure "Installer JSON metadata is invalid: $($_.Exception.Message)" }
    foreach ($pkgdefName in $expectedThemes.Keys) {
        $count = if ($entriesByName.ContainsKey($pkgdefName)) { $entriesByName[$pkgdefName].Count } else { 0 }
        if ($count -ne 1) {
            Add-Failure "Expected one '$pkgdefName' entry; found $count."
        }
    }

    $pkgdefEntries = @($archive.Entries | Where-Object { $_.FullName -match '(?i)\.pkgdef$' })
    if ($pkgdefEntries.Count -ne $expectedThemes.Count) {
        Add-Failure "Expected exactly $($expectedThemes.Count) .pkgdef entries; found $($pkgdefEntries.Count)."
    }
    foreach ($entry in $archive.Entries) {
        $normalizedName = $entry.FullName.Replace('\', '/')
        if ($normalizedName -match '(?i)dark.*\.pkgdef$') {
            Add-Failure "Former Dark-named package entry is forbidden: '$normalizedName'."
        }
        if ([IO.Path]::GetFileName($normalizedName) -ceq 'Corporo.pkgdef') {
            Add-Failure "Former Corporo package entry is forbidden: '$normalizedName'."
        }
        if ([IO.Path]::GetFileName($normalizedName) -ceq 'CosmoraPurple.pkgdef') {
            Add-Failure "Former Cosmora Purple package entry is forbidden: '$normalizedName'."
        }
        if ($normalizedName -match '(?i)\.(dll|pdb)$') {
            Add-Failure "Managed assemblies and symbols are forbidden in this data-only VSIX: '$normalizedName'."
        }
    }

    if ($entriesByName.ContainsKey('extension.vsixmanifest')) {
        try {
            [xml] $manifest = Read-ZipEntryText $entriesByName['extension.vsixmanifest'][0]
            $namespace = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
            $namespace.AddNamespace('v', 'http://schemas.microsoft.com/developer/vsx-schema/2011')
            $identity = $manifest.SelectSingleNode('/v:PackageManifest/v:Metadata/v:Identity', $namespace)
            if ($null -eq $identity) {
                Add-Failure 'Generated manifest has no Metadata/Identity element.'
            }
            else {
                if ($identity.Id -cne $selectedPackage.Identity) { Add-Failure "Unexpected VSIX identity '$($identity.Id)'." }
                if ($identity.Publisher -cne $selectedPackage.Publisher) { Add-Failure "Unexpected VSIX publisher '$($identity.Publisher)'." }
                if ($identity.Version -cne $expectedVersion) { Add-Failure "VSIX version '$($identity.Version)' does not match source manifest version '$expectedVersion'." }
            }

            $targets = @($manifest.SelectNodes('/v:PackageManifest/v:Installation/v:InstallationTarget', $namespace))
            if ($targets.Count -ne 2) {
                Add-Failure "Expected two installation targets; found $($targets.Count)."
            }
            $architectures = @{}
            foreach ($target in $targets) {
                if ($target.Id -cne 'Microsoft.VisualStudio.Community') { Add-Failure "Unexpected installation target SKU '$($target.Id)'." }
                if ($target.Version -cne '[17.14,)') { Add-Failure "Unexpected installation range '$($target.Version)'; expected stable API range '[17.14,)'." }
                $architecture = [string] $target.ProductArchitecture
                if ($architectures.ContainsKey($architecture)) {
                    Add-Failure "Duplicate installation architecture '$architecture'."
                }
                $architectures[$architecture] = $true
            }
            foreach ($architecture in @('amd64', 'arm64')) {
                if (-not $architectures.ContainsKey($architecture)) { Add-Failure "Missing '$architecture' installation target." }
            }

            $prerequisites = @($manifest.SelectNodes('/v:PackageManifest/v:Prerequisites/v:Prerequisite', $namespace))
            if ($prerequisites.Count -ne 1) {
                Add-Failure "Expected one prerequisite; found $($prerequisites.Count)."
            }
            else {
                $prerequisite = $prerequisites[0]
                if ($prerequisite.Id -cne 'Microsoft.VisualStudio.Component.CoreEditor') {
                    Add-Failure "Unexpected prerequisite '$($prerequisite.Id)'."
                }
                if ($prerequisite.Version -cne '[17.14,)') {
                    Add-Failure "Unexpected prerequisite range '$($prerequisite.Version)'."
                }
            }

            $description = $manifest.SelectSingleNode('/v:PackageManifest/v:Metadata/v:Description', $namespace)
            if ($null -eq $description -or $description.InnerText -notmatch 'Visual Studio 2026') {
                Add-Failure 'Manifest description must identify Visual Studio 2026.'
            }
            elseif ($description.InnerText -match 'Visual Studio 2022') {
                Add-Failure 'Manifest description must not advertise Visual Studio 2022.'
            }

            $metadataChecks = [ordered] @{
                'Preview' = $expectedPreview
                'DisplayName' = $selectedPackage.DisplayName
                'Description' = $selectedPackage.Description
                'Tags' = $selectedPackage.Tags
                'MoreInfo' = 'https://github.com/ChxosCode/Chxos.VisualStudio.Themes'
                'License' = 'LICENSE.txt'
                'ReleaseNotes' = 'https://github.com/ChxosCode/Chxos.VisualStudio.Themes/releases'
                'Icon' = 'assets\icon.png'
                'PreviewImage' = 'assets\preview.png'
            }
            foreach ($elementName in $metadataChecks.Keys) {
                $nodes = @($manifest.SelectNodes("/v:PackageManifest/v:Metadata/v:$elementName", $namespace))
                if ($nodes.Count -ne 1 -or $nodes[0].InnerText -cne $metadataChecks[$elementName]) {
                    Add-Failure "Manifest $elementName must be '$($metadataChecks[$elementName])'."
                }
            }
            $frameworkDependencies = @($manifest.SelectNodes('/v:PackageManifest/v:Dependencies/v:Dependency[@Id="Microsoft.Framework.NDP"]', $namespace))
            if ($frameworkDependencies.Count -ne 0) {
                Add-Failure 'The data-only VSIX must not declare Microsoft.Framework.NDP.'
            }
        }
        catch {
            Add-Failure "Generated extension.vsixmanifest is invalid XML: $($_.Exception.Message)"
        }
    }

    foreach ($pkgdefName in $expectedThemes.Keys) {
        if (-not $entriesByName.ContainsKey($pkgdefName)) { continue }
        $themeName = $expectedThemes[$pkgdefName][0]
        $themeGuid = $expectedThemes[$pkgdefName][1]
        $content = Read-ZipEntryText $entriesByName[$pkgdefName][0]
        $registrationHeader = '[$RootKey$\Themes\' + $themeGuid + ']'
        if (-not $content.Contains($registrationHeader)) {
            Add-Failure "'$pkgdefName' does not register expected theme GUID '$themeGuid'."
        }
        if (-not $content.Contains('@="' + $themeName + '"') -or -not $content.Contains('"Name"="' + $themeName + '"')) {
            Add-Failure "'$pkgdefName' does not register expected display name '$themeName'."
        }
    }
}
finally {
    $archive.Dispose()
}

if ($failures.Count -gt 0) {
    Write-Host "VSIX package validation failed with $($failures.Count) issue(s):" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'VSIX package validation passed.' -ForegroundColor Green
Write-Host "  Package: $resolvedPath"
Write-Host "  Identity: $($selectedPackage.Identity) ($Package)"
Write-Host "  Version: $expectedVersion"
Write-Host "  Themes: $($expectedThemes.Count)"
Write-Host '  API target: 17.14 and later (Visual Studio 2026; Visual Studio 2022 17.14 eligible but untested)'
Write-Host '  Architectures: amd64, arm64'
Write-Host '  Managed payload: none'
exit 0

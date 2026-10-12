[CmdletBinding()]
param([switch]$Check, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
$project = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = $project }
$catalog = Read-PackageCatalog
$utf8 = New-Object Text.UTF8Encoding($false)
function Save-Generated([string]$RelativePath, [string]$Content) {
    $path = Join-Path $OutputDirectory $RelativePath
    $text = $Content.Replace("`r`n", "`n").TrimEnd() + "`n"
    if ($Check) {
        if (-not (Test-Path -LiteralPath $path) -or [IO.File]::ReadAllText($path) -cne $text) { throw "Packaging generation drift: $RelativePath. Run Generate-ThemePackages.ps1." }
    }
    else {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [IO.File]::WriteAllText($path, $text, $utf8)
    }
}
function Escape-Xml([string]$Value) { [Security.SecurityElement]::Escape($Value) }
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
$lines.Add('  <!-- Generated from authoring/PackageCatalog.json. Do not edit. -->')
foreach ($package in $catalog.Packages) {
    $key = $package.Key
    $lines.Add(('  <PropertyGroup Condition="''$(ThemePackage)'' == ''{0}''">' -f $key))
    foreach ($entry in @(
        @('ThemePackageKnown','true'), @('ThemePackageKey',$package.Key), @('ThemePackageVersion',$package.Version),
        @('ThemePackageIdentity',$package.Identity), @('ThemePackageIcon',$package.Icon),
        @('ThemePackagePreview',$package.PreviewImage),
        @('ThemePackageManifest',"packaging/generated/$key/source.extension.vsixmanifest"),
        @('TargetVsixContainerName',"$key-$($package.Version).vsix")
    )) { $lines.Add(('    <{0}>{1}</{0}>' -f $entry[0], (Escape-Xml $entry[1]))) }
    $lines.Add('  </PropertyGroup>')
    $lines.Add(('  <ItemGroup Condition="''$(ThemePackage)'' == ''{0}''">' -f $key))
    foreach ($file in $package.Themes) { $lines.Add(('    <SelectedTheme Include="{0}" />' -f (Escape-Xml $file))) }
    $lines.Add('  </ItemGroup>')
    [xml]$manifest = [IO.File]::ReadAllText((Join-Path $project 'packaging/manifest.template.xml'))
    $manifest.PackageManifest.Metadata.Identity.Id = $package.Identity
    $manifest.PackageManifest.Metadata.Identity.Version = $package.Version
    $manifest.PackageManifest.Metadata.Identity.Publisher = $package.Publisher
    $manifest.PackageManifest.Metadata.DisplayName = $package.DisplayName
    $manifest.PackageManifest.Metadata.Description.InnerText = $package.Description
    $manifest.PackageManifest.Metadata.Tags = $package.Tags
    $writer = New-Object IO.StringWriter
    $settings = New-Object Xml.XmlWriterSettings
    $settings.Indent = $true; $settings.OmitXmlDeclaration = $true; $settings.NewLineChars = "`n"
    $xmlWriter = [Xml.XmlWriter]::Create($writer, $settings)
    try { $manifest.Save($xmlWriter); $xmlWriter.Flush() } finally { $xmlWriter.Dispose() }
    Save-Generated "packaging/generated/$key/source.extension.vsixmanifest" $writer.ToString()
}
$lines.Add('</Project>')
Save-Generated 'PackageCatalog.props' ($lines -join "`n")
Write-Host "Packaging generation $(if ($Check) {'check'} else {'write'}) passed for $($catalog.Packages.Count) packages."

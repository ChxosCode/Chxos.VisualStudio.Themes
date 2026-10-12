[CmdletBinding(DefaultParameterSetName='Write')]
param(
    [Parameter(ParameterSetName='Check')][switch] $Check,
    [Parameter(ParameterSetName='MissingDeferred')][switch] $MissingDeferred,
    [string] $AuthoringDirectory,
    [string] $OutputDirectory
)
$ErrorActionPreference = 'Stop'
if (-not $AuthoringDirectory) { $AuthoringDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'authoring' }
if (-not $OutputDirectory) { $OutputDirectory = Split-Path -Parent $PSScriptRoot }
Set-StrictMode -Version Latest
$catalog = Get-Content (Join-Path $AuthoringDirectory 'ThemeCatalog.json') -Raw | ConvertFrom-Json
$model = Get-Content (Join-Path $AuthoringDirectory 'Components.json') -Raw | ConvertFrom-Json
$palettes = Get-Content (Join-Path $AuthoringDirectory 'Palettes.json') -Raw | ConvertFrom-Json
$deferred = @()
if ($MissingDeferred) {
    Import-Module (Join-Path $PSScriptRoot 'PackageCatalog.psm1') -Force
    $packages = Read-PackageCatalog -CatalogPath (Join-Path $AuthoringDirectory 'PackageCatalog.json')
    $deferred = @($packages.DeferredPublicThemes)
}
if ($model.SchemaVersion -ne 1) { throw 'Unsupported authoring schema.' }
if ($catalog.Count -ne 13 -or ($model.ThemeOrder -join '|') -cne (($catalog | ForEach-Object File) -join '|')) { throw 'Theme catalog/order mismatch.' }
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$guids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$utf8 = New-Object Text.UTF8Encoding($false)
function Escape-Xml([string]$Value) { return [Security.SecurityElement]::Escape($Value) }
function Save-Generated([string]$Name,[string]$Text) {
    $path = Join-Path $OutputDirectory $Name
    # Fresh checkouts omit only deferred generated themes. Never overwrite an
    # existing file or repair a missing public theme/catalog in bootstrap mode.
    if ($MissingDeferred -and ($Name -cnotin $deferred -or (Test-Path -LiteralPath $path))) { return }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $path) -or [IO.File]::ReadAllText($path) -cne $Text) { throw "Generated output drift: $Name. Run Generate-Themes.ps1 explicitly." }
    }
    else { [IO.File]::WriteAllText($path,$Text,$utf8) }
}
if (-not $Check) { [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory)) }
for ($i=0; $i -lt $catalog.Count; $i++) {
    $theme = $catalog[$i]
    if ($theme.File -notmatch '^[A-Za-z]+\.vstheme$' -or $theme.Pkgdef -cne ([IO.Path]::GetFileNameWithoutExtension($theme.File)+'.pkgdef') -or -not $names.Add($theme.File) -or -not $guids.Add($theme.Guid)) { throw 'Invalid or duplicate theme identity.' }
    if ($theme.Guid -notmatch '^\{[0-9a-fA-F-]{36}\}$') { throw 'Malformed theme GUID.' }
    $lines = New-Object System.Collections.Generic.List[string]
    # Preserve established formatting to keep color review diffs focused.
    $spaced = $theme.SpacedEmptyElements
    $lines.Add($(if ($spaced) { '<?xml version="1.0" encoding="utf-8"?>' } else { "<?xml version='1.0' encoding='UTF-8'?>" }))
    $lines.Add('<Themes>')
    $lines.Add(('  <Theme Name="{0}" GUID="{1}" BaseGUID="{2}" FallbackId="{3}">' -f (Escape-Xml $theme.Name),$theme.Guid,$model.BaseGuid,$model.FallbackId))
    $identities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($category in $model.Categories) {
        $lines.Add(('    <Category Name="{0}" GUID="{1}">' -f (Escape-Xml $category.Name),$category.Guid))
        foreach ($color in $category.Colors) {
            $lines.Add(('      <Color Name="{0}">' -f (Escape-Xml $color.Name)))
            foreach ($component in $color.Components) {
                $identity = @($category.Name,$color.Name,$component.Component) -join [char]31
                if (-not $identities.Add($identity)) { throw "Duplicate authoring component '$identity'." }
                if ($component.Component -notin @('Background','Foreground') -or $component.Type -notin @('CT_RAW','CT_INVALID','CT_AUTOMATIC','CT_SYSCOLOR','CT_COLORINDEX')) { throw "Invalid typed component '$identity'." }
                $fields = @($component.PSObject.Properties.Name | Where-Object { $_ -in @('Source','Sources','Anchors') })
                if ($fields.Count -ne 1) { throw "Exactly one source or anchor binding required: $identity." }
                switch ($fields[0]) {
                    'Source' { $source = $component.Source }
                    'Sources' {
                        if ($component.Sources.Count -ne $catalog.Count) { throw "Source cardinality mismatch: $identity." }
                        $source = $component.Sources[$i]
                    }
                    'Anchors' {
                        if ($component.Type -cne 'CT_RAW' -or $component.Anchors.Count -ne $catalog.Count) { throw "Only raw components can bind palette anchors: $identity." }
                        $source = $palettes.($theme.File).($component.Anchors[$i])
                    }
                }
                if ($source -cnotmatch '^[0-9A-F]{8}$') { throw "Invalid source for '$identity'." }
                $lines.Add(('        <{0} Type="{1}" Source="{2}"{3}/>' -f $component.Component,$component.Type,$source,$(if ($spaced) {' '} else {''})))
            }
            $lines.Add('      </Color>')
        }
        $lines.Add('    </Category>')
    }
    $lines.Add('  </Theme>'); $lines.Add('</Themes>')
    Save-Generated $theme.File (($lines -join "`n")+"`n")
}
$props = @('<Project>', '  <!-- Generated from authoring/ThemeCatalog.json. -->', '  <ItemGroup>')
foreach ($theme in $catalog) {
    $props += ('    <None Include="{0}"><SubType>Designer</SubType></None>' -f $theme.File)
    $props += ('    <CosmoraTheme Include="{0}" />' -f $theme.File)
}
$props += @('  </ItemGroup>', '</Project>')
Save-Generated 'ThemeCatalog.props' (($props -join "`n")+"`n")
Write-Host "Theme generation $(if ($Check) {'check'} elseif ($MissingDeferred) {'missing-deferred bootstrap'} else {'write'}) passed for all thirteen themes."

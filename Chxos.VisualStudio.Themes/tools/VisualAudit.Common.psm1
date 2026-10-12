Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-VisualAuditFileHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $stream = [IO.File]::OpenRead($resolved)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '')
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-VsixPkgdefHashes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $VsixPath)

    $resolved = (Resolve-Path -LiteralPath $VsixPath).Path
    $archive = [IO.Compression.ZipFile]::OpenRead($resolved)
    try {
        $result = [ordered] @{}
        foreach ($entry in $archive.Entries | Where-Object { $_.FullName -match '\.pkgdef$' }) {
            $stream = $entry.Open()
            try {
                $sha = [Security.Cryptography.SHA256]::Create()
                try {
                    $hash = $sha.ComputeHash($stream)
                    $result[[IO.Path]::GetFileName($entry.FullName)] = ([BitConverter]::ToString($hash) -replace '-', '')
                }
                finally {
                    $sha.Dispose()
                }
            }
            finally {
                $stream.Dispose()
            }
        }
        return $result
    }
    finally {
        $archive.Dispose()
    }
}

function Get-InstalledPkgdefHashes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RootSuffix,
        [Parameter(Mandatory)][string[]] $Names,
        [string] $ExtensionIdentity,
        [string] $ProfileDirectory
    )

    $visualStudioRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio'
    $pattern = '^18\.0_[a-fA-F0-9]{8}' + [regex]::Escape($RootSuffix) + '$'
    if ($ProfileDirectory) {
        $profiles = @(Get-Item -LiteralPath $ProfileDirectory -ErrorAction Stop)
        if ($profiles[0].Name -notmatch $pattern) { throw 'Profile directory does not match the exact Visual Studio 18 root suffix.' }
    }
    else {
        $profiles = @(Get-ChildItem -LiteralPath $visualStudioRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $pattern })
    }
    if ($profiles.Count -ne 1) {
        throw "Expected exactly one Visual Studio profile for root suffix '$RootSuffix'; found $($profiles.Count)."
    }

    $searchRoot = $profiles[0].FullName
    $allExtensionRoots = @(Get-ChildItem -LiteralPath $searchRoot -Filter 'extension.vsixmanifest' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DirectoryName -Unique)
    if ($ExtensionIdentity) {
        $extensionRoots = @(Get-ChildItem -LiteralPath $searchRoot -Filter 'extension.vsixmanifest' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                [xml]$manifest = [IO.File]::ReadAllText($_.FullName)
                if ($manifest.PackageManifest.Metadata.Identity.Id -ceq $ExtensionIdentity) { $_.Directory.FullName }
            } catch { }
        })
        if ($extensionRoots.Count -ne 1) { throw "Expected one installed extension '$ExtensionIdentity'; found $($extensionRoots.Count)." }
        $searchRoot = $extensionRoots[0]
    }

    $result = [ordered] @{}
    foreach ($name in $Names) {
        # An internal collection and a pilot can share a theme GUID/filename.
        # Do not credit one extension's bytes while another registration can win.
        $registeredCopies = @($allExtensionRoots | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter $name -File -Recurse -ErrorAction SilentlyContinue })
        if ($registeredCopies.Count -gt 1) { throw "Ambiguous installed payload '$name' across extension registrations in '$RootSuffix'." }
        $matches = @(Get-ChildItem -LiteralPath $searchRoot -Filter $name -File -Recurse -ErrorAction SilentlyContinue)
        if ($matches.Count -ne 1) {
            throw "Expected one installed payload '$name' in '$RootSuffix'; found $($matches.Count)."
        }
        $result[$name] = [pscustomobject]@{
            Path = $matches[0].FullName
            Hash = Get-VisualAuditFileHash -Path $matches[0].FullName
        }
    }
    return $result
}

function Assert-VisualAuditPayloadIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Collections.IDictionary] $Packaged,
        [Parameter(Mandatory)][Collections.IDictionary] $Installed
    )

    foreach ($name in $Packaged.Keys) {
        if (-not $Installed.Contains($name)) {
            throw "Installed payload is missing '$name'."
        }
        if ([string] $Installed[$name].Hash -cne [string] $Packaged[$name]) {
            throw "Installed '$name' hash '$($Installed[$name].Hash)' does not match packaged hash '$($Packaged[$name])'."
        }
    }
}

function Assert-VisualAuditThemeInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Collections.IDictionary] $Packaged,
        [Parameter(Mandatory)][string[]] $ExpectedNames
    )

    $expected = @($ExpectedNames | Sort-Object -Unique)
    if ($Packaged.Count -ne $expected.Count) {
        throw "Expected $($expected.Count) packaged .pkgdef files; found $($Packaged.Count)."
    }
    $missing = @($expected | Where-Object { -not $Packaged.Contains($_) })
    $unexpected = @($Packaged.Keys | Where-Object { $_ -notin $expected })
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        $details = @()
        if ($missing.Count -gt 0) { $details += "missing: $($missing -join ', ')" }
        if ($unexpected.Count -gt 0) { $details += "unexpected: $($unexpected -join ', ')" }
        throw "Packaged theme inventory mismatch ($($details -join '; '))."
    }
}

function Save-WindowScreenshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr] $WindowHandle,
        [Parameter(Mandatory)][string] $Path
    )

    if (-not ('VisualAuditNativeMethods' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class VisualAuditNativeMethods {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@
    }

    $rectangle = New-Object VisualAuditNativeMethods+RECT
    if (-not [VisualAuditNativeMethods]::GetWindowRect($WindowHandle, [ref] $rectangle)) {
        throw "Could not read the Visual Studio window rectangle."
    }
    $width = $rectangle.Right - $rectangle.Left
    $height = $rectangle.Bottom - $rectangle.Top
    if ($width -lt 100 -or $height -lt 100) {
        throw "Visual Studio window rectangle is invalid: ${width}x${height}."
    }

    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $bitmap = New-Object Drawing.Bitmap $width, $height
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rectangle.Left, $rectangle.Top, 0, 0, $bitmap.Size)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-VisualAuditImageMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [int] $SampleStep = 4,
        [Collections.IEnumerable] $Masks = @()
    )

    $bitmap = [Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $Path).Path)
    try {
        $count = 0L
        $luminance = 0.0
        $edge = 0.0
        for ($y = 0; $y -lt $bitmap.Height; $y += $SampleStep) {
            for ($x = 0; $x -lt $bitmap.Width; $x += $SampleStep) {
                $masked = $false
                foreach ($mask in $Masks) {
                    if ($x -ge $mask.X -and $x -lt ($mask.X + $mask.Width) -and
                        $y -ge $mask.Y -and $y -lt ($mask.Y + $mask.Height)) {
                        $masked = $true
                        break
                    }
                }
                if ($masked) { continue }

                $color = $bitmap.GetPixel($x, $y)
                $current = (0.2126 * $color.R + 0.7152 * $color.G + 0.0722 * $color.B) / 255.0
                $luminance += $current
                if (($x + $SampleStep) -lt $bitmap.Width) {
                    $right = $bitmap.GetPixel($x + $SampleStep, $y)
                    $rightLuminance = (0.2126 * $right.R + 0.7152 * $right.G + 0.0722 * $right.B) / 255.0
                    $edge += [Math]::Abs($current - $rightLuminance)
                }
                if (($y + $SampleStep) -lt $bitmap.Height) {
                    $down = $bitmap.GetPixel($x, $y + $SampleStep)
                    $downLuminance = (0.2126 * $down.R + 0.7152 * $down.G + 0.0722 * $down.B) / 255.0
                    $edge += [Math]::Abs($current - $downLuminance)
                }
                $count++
            }
        }
        if ($count -eq 0) {
            throw "No unmasked pixels were available in '$Path'."
        }
        return [pscustomobject]@{
            Width = $bitmap.Width
            Height = $bitmap.Height
            Samples = $count
            MeanLuminance = $luminance / $count
            MeanEdgeStrength = $edge / (2.0 * $count)
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

function Get-VisualAuditDominantColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][pscustomobject] $Region,
        [int] $SampleStep = 1
    )

    $bitmap = [Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $Path).Path)
    try {
        $left = [Math]::Max(0, [int] $Region.X)
        $top = [Math]::Max(0, [int] $Region.Y)
        $right = [Math]::Min($bitmap.Width, $left + [Math]::Max(1, [int] $Region.Width))
        $bottom = [Math]::Min($bitmap.Height, $top + [Math]::Max(1, [int] $Region.Height))
        if ($left -ge $right -or $top -ge $bottom) {
            throw "Visual-audit region is outside '$Path': $left,$top through $right,$bottom."
        }

        $counts = @{}
        $samples = 0L
        for ($y = $top; $y -lt $bottom; $y += $SampleStep) {
            for ($x = $left; $x -lt $right; $x += $SampleStep) {
                $pixel = $bitmap.GetPixel($x, $y)
                $key = '{0:X2}{1:X2}{2:X2}' -f $pixel.R, $pixel.G, $pixel.B
                if ($counts.ContainsKey($key)) {
                    $counts[$key]++
                }
                else {
                    $counts[$key] = 1L
                }
                $samples++
            }
        }
        if ($samples -eq 0) {
            throw "Visual-audit region contained no sampled pixels in '$Path'."
        }

        $dominant = $counts.GetEnumerator() |
            Sort-Object -Property @(
                @{ Expression = 'Value'; Descending = $true },
                @{ Expression = 'Name'; Descending = $false }
            ) |
            Select-Object -First 1
        $red = [Convert]::ToInt32($dominant.Name.Substring(0, 2), 16)
        $green = [Convert]::ToInt32($dominant.Name.Substring(2, 2), 16)
        $blue = [Convert]::ToInt32($dominant.Name.Substring(4, 2), 16)
        return [pscustomobject]@{
            Color = "#$($dominant.Name)"
            Red = $red
            Green = $green
            Blue = $blue
            Luminance = (0.2126 * $red + 0.7152 * $green + 0.0722 * $blue) / 255.0
            Count = [long] $dominant.Value
            Samples = $samples
            Share = [long] $dominant.Value / [double] $samples
            Region = [pscustomobject]@{
                X = $left
                Y = $top
                Width = $right - $left
                Height = $bottom - $top
            }
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

function Get-VisualAuditShellHierarchy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $bitmap = [Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $Path).Path)
    try {
        $width = $bitmap.Width
        $height = $bitmap.Height
    }
    finally {
        $bitmap.Dispose()
    }

    $regions = [ordered] @{
        TopShell = [pscustomobject]@{
            X = [Math]::Round($width * 0.01)
            Y = [Math]::Round($height * 0.01)
            Width = [Math]::Round($width * 0.65)
            Height = [Math]::Round($height * 0.06)
        }
        Workspace = [pscustomobject]@{
            X = [Math]::Round($width * 0.02)
            Y = [Math]::Round($height * 0.14)
            Width = [Math]::Round($width * 0.55)
            Height = [Math]::Round($height * 0.65)
        }
        DockSurround = [pscustomobject]@{
            X = [Math]::Round($width * 0.58)
            Y = [Math]::Round($height * 0.14)
            Width = [Math]::Round($width * 0.15)
            Height = [Math]::Round($height * 0.65)
        }
        StatusBar = [pscustomobject]@{
            X = [Math]::Round($width * 0.02)
            Y = [Math]::Round($height * 0.96)
            Width = [Math]::Round($width * 0.92)
            Height = [Math]::Round($height * 0.03)
        }
    }

    $measurements = [ordered] @{}
    foreach ($name in $regions.Keys) {
        $measurements[$name] = Get-VisualAuditDominantColor -Path $Path -Region $regions[$name] -SampleStep 2
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('Workspace', 'DockSurround')) {
        $difference = [Math]::Max(
            [Math]::Abs($measurements.TopShell.Red - $measurements[$name].Red),
            [Math]::Max(
                [Math]::Abs($measurements.TopShell.Green - $measurements[$name].Green),
                [Math]::Abs($measurements.TopShell.Blue - $measurements[$name].Blue)))
        if ($difference -gt 3) {
            $candidates.Add("$name dominant color $($measurements[$name].Color) differs from the top shell $($measurements.TopShell.Color); inspect the continuous main-shell background.")
        }
    }

    $statusDelta = $measurements.TopShell.Luminance - $measurements.StatusBar.Luminance
    if ($statusDelta -lt 0.002) {
        $candidates.Add("Idle status-bar dominant color $($measurements.StatusBar.Color) is not visibly darker than the shell body $($measurements.TopShell.Color).")
    }

    return [pscustomobject]@{
        Measurements = $measurements
        StatusLuminanceDelta = $statusDelta
        Candidates = @($candidates)
    }
}

function Get-VisualAuditDocumentTabHierarchy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [string] $ExpectedShellColor,
        [string] $ExpectedTabChannelColor
    )

    $bitmap = [Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $Path).Path)
    try {
        $width = $bitmap.Width
        $height = $bitmap.Height
    }
    finally {
        $bitmap.Dispose()
    }

    # The capture harness fixes the Visual Studio window at 1600x1000. These
    # proportional regions deliberately avoid menu text, open document tabs,
    # the editor, and the right-docked tool window.
    $regions = [ordered] @{
        Shell = [pscustomobject]@{
            X = [Math]::Round($width * 0.34)
            Y = [Math]::Round($height * 0.01)
            Width = [Math]::Round($width * 0.24)
            Height = [Math]::Round($height * 0.04)
        }
        TabChannel = [pscustomobject]@{
            X = [Math]::Round($width * 0.55)
            Y = [Math]::Round($height * 0.075)
            Width = [Math]::Round($width * 0.17)
            Height = [Math]::Round($height * 0.03)
        }
    }

    $measurements = [ordered] @{
        Shell = Get-VisualAuditDominantColor -Path $Path -Region $regions.Shell -SampleStep 2
        TabChannel = Get-VisualAuditDominantColor -Path $Path -Region $regions.TabChannel -SampleStep 2
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $maximumChannelDifference = [Math]::Max(
        [Math]::Abs($measurements.Shell.Red - $measurements.TabChannel.Red),
        [Math]::Max(
            [Math]::Abs($measurements.Shell.Green - $measurements.TabChannel.Green),
            [Math]::Abs($measurements.Shell.Blue - $measurements.TabChannel.Blue)))
    $luminanceDelta = $measurements.TabChannel.Luminance - $measurements.Shell.Luminance

    if ($maximumChannelDifference -le 3) {
        $candidates.Add("Document-tab channel $($measurements.TabChannel.Color) collapses into the shell base $($measurements.Shell.Color).")
    }
    if ($luminanceDelta -le 0.002) {
        $candidates.Add("Document-tab channel $($measurements.TabChannel.Color) is not visibly lighter than the shell base $($measurements.Shell.Color).")
    }
    if ($luminanceDelta -gt 0.12) {
        $candidates.Add("Document-tab channel $($measurements.TabChannel.Color) is excessively lighter than the shell base $($measurements.Shell.Color).")
    }

    foreach ($expectation in @(
        [pscustomobject]@{ Name = 'shell'; Actual = $measurements.Shell; Expected = $ExpectedShellColor },
        [pscustomobject]@{ Name = 'document-tab channel'; Actual = $measurements.TabChannel; Expected = $ExpectedTabChannelColor }
    )) {
        if ([string]::IsNullOrWhiteSpace($expectation.Expected) -or
            $expectation.Expected -notmatch '^#[0-9A-Fa-f]{6}$') {
            continue
        }
        $expectedRed = [Convert]::ToInt32($expectation.Expected.Substring(1, 2), 16)
        $expectedGreen = [Convert]::ToInt32($expectation.Expected.Substring(3, 2), 16)
        $expectedBlue = [Convert]::ToInt32($expectation.Expected.Substring(5, 2), 16)
        $expectedDifference = [Math]::Max(
            [Math]::Abs($expectation.Actual.Red - $expectedRed),
            [Math]::Max(
                [Math]::Abs($expectation.Actual.Green - $expectedGreen),
                [Math]::Abs($expectation.Actual.Blue - $expectedBlue)))
        if ($expectedDifference -gt 3) {
            $candidates.Add("Measured $($expectation.Name) $($expectation.Actual.Color) differs from the package-derived expectation $($expectation.Expected).")
        }
    }

    return [pscustomobject]@{
        Measurements = $measurements
        MaximumChannelDifference = $maximumChannelDifference
        LuminanceDelta = $luminanceDelta
        ExpectedShellColor = $ExpectedShellColor
        ExpectedTabChannelColor = $ExpectedTabChannelColor
        Candidates = @($candidates)
    }
}

function Compare-VisualAuditImages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ReferencePath,
        [Parameter(Mandatory)][string] $CandidatePath,
        [Collections.IEnumerable] $Masks = @(),
        [string] $Scenario = 'unspecified'
    )

    $reference = Get-VisualAuditImageMetrics -Path $ReferencePath -Masks $Masks
    $candidate = Get-VisualAuditImageMetrics -Path $CandidatePath -Masks $Masks
    if ($reference.Width -ne $candidate.Width -or $reference.Height -ne $candidate.Height) {
        throw "Scenario '$Scenario' image dimensions differ: $($reference.Width)x$($reference.Height) versus $($candidate.Width)x$($candidate.Height)."
    }

    $luminanceDelta = [Math]::Abs($reference.MeanLuminance - $candidate.MeanLuminance)
    $edgeRatio = if ($reference.MeanEdgeStrength -le 0.000001) {
        1.0
    }
    else {
        $candidate.MeanEdgeStrength / $reference.MeanEdgeStrength
    }
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($edgeRatio -lt 0.65) {
        $candidates.Add("Edge strength is only $([Math]::Round($edgeRatio * 100, 1))% of official Dark; inspect disappearing separators, glyphs, or boundaries.")
    }
    if ($edgeRatio -gt 1.8) {
        $candidates.Add("Edge strength is $([Math]::Round($edgeRatio * 100, 1))% of official Dark; inspect competing surfaces or excessive borders.")
    }

    return [pscustomobject]@{
        Scenario = $Scenario
        Reference = $reference
        Candidate = $candidate
        MeanLuminanceDelta = $luminanceDelta
        EdgeStrengthRatio = $edgeRatio
        Candidates = @($candidates)
    }
}

function Get-VisualAuditInteractionHierarchy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $NeutralAnchor,
        [Parameter(Mandatory)][string] $Rest,
        [Parameter(Mandatory)][string] $Hover,
        [Parameter(Mandatory)][string] $Pressed,
        [Parameter(Mandatory)][string] $QuietBorder,
        [Parameter(Mandatory)][string] $PressedBorder,
        [Parameter(Mandatory)][string] $FocusBorder,
        [Parameter(Mandatory)][string] $SelectedBorder,
        [Parameter(Mandatory)][string] $Accent
    )

    function Convert-HexColor {
        param([string] $Value)
        if ($Value -notmatch '^#[0-9A-Fa-f]{6}$') {
            throw "Interaction color '$Value' must use #RRGGBB notation."
        }
        return @(
            [Convert]::ToInt32($Value.Substring(1, 2), 16),
            [Convert]::ToInt32($Value.Substring(3, 2), 16),
            [Convert]::ToInt32($Value.Substring(5, 2), 16)
        )
    }

    function Get-ColorDistance {
        param([int[]] $Left, [int[]] $Right)
        return [Math]::Sqrt(
            [Math]::Pow(($Left[0] - $Right[0]) / 255.0, 2) +
            [Math]::Pow(($Left[1] - $Right[1]) / 255.0, 2) +
            [Math]::Pow(($Left[2] - $Right[2]) / 255.0, 2))
    }

    function Get-Luminance {
        param([int[]] $Rgb)
        $linear = foreach ($channel in $Rgb) {
            $value = $channel / 255.0
            if ($value -le 0.04045) { $value / 12.92 }
            else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
        }
        return (0.2126 * $linear[0]) + (0.7152 * $linear[1]) + (0.0722 * $linear[2])
    }

    function Get-ColorContrast {
        param([int[]] $First, [int[]] $Second)
        $firstLuminance = Get-Luminance $First
        $secondLuminance = Get-Luminance $Second
        $lighter = [Math]::Max($firstLuminance, $secondLuminance)
        $darker = [Math]::Min($firstLuminance, $secondLuminance)
        return ($lighter + 0.05) / ($darker + 0.05)
    }

    $colors = [ordered] @{}
    foreach ($entry in @{
        NeutralAnchor = $NeutralAnchor
        Rest = $Rest
        Hover = $Hover
        Pressed = $Pressed
        QuietBorder = $QuietBorder
        PressedBorder = $PressedBorder
        FocusBorder = $FocusBorder
        SelectedBorder = $SelectedBorder
        Accent = $Accent
    }.GetEnumerator()) {
        $colors[$entry.Key] = Convert-HexColor $entry.Value
    }

    $distances = [ordered] @{
        RestToHover = Get-ColorDistance $colors.Rest $colors.Hover
        HoverToPressed = Get-ColorDistance $colors.Hover $colors.Pressed
        RestToAccent = Get-ColorDistance $colors.Rest $colors.Accent
        RestToNeutral = Get-ColorDistance $colors.Rest $colors.NeutralAnchor
        HoverToAccent = Get-ColorDistance $colors.Hover $colors.Accent
        HoverToNeutral = Get-ColorDistance $colors.Hover $colors.NeutralAnchor
        QuietBorderToAccent = Get-ColorDistance $colors.QuietBorder $colors.Accent
        SelectedBorderToAccent = Get-ColorDistance $colors.SelectedBorder $colors.Accent
    }
    $contrasts = [ordered] @{
        PressedBorder = Get-ColorContrast $colors.PressedBorder $colors.Pressed
        FocusBorder = Get-ColorContrast $colors.FocusBorder $colors.Rest
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($distances.RestToHover -lt 0.025) {
        $candidates.Add('Resting and hover surfaces are not perceptibly distinct.')
    }
    if ($distances.HoverToPressed -lt 0.025) {
        $candidates.Add('Hover and pressed surfaces are not perceptibly distinct.')
    }
    if ($distances.RestToAccent -lt $distances.RestToNeutral -or
        $distances.HoverToAccent -lt $distances.HoverToNeutral) {
        $candidates.Add('A generic control surface is closer to the accent than to the neutral anchor.')
    }
    if ($distances.QuietBorderToAccent -lt 0.02) {
        $candidates.Add('The generic control border collapses into the selected accent.')
    }
    if ($contrasts.PressedBorder -lt 3.0) {
        $candidates.Add("The strong pressed-input border is only $([Math]::Round($contrasts.PressedBorder, 2)):1.")
    }
    if ($contrasts.FocusBorder -lt 3.0) {
        $candidates.Add("The keyboard-focus border is only $([Math]::Round($contrasts.FocusBorder, 2)):1.")
    }
    if ($distances.SelectedBorderToAccent -gt 0.02) {
        $candidates.Add('The selected/default-action border no longer uses the theme accent.')
    }

    return [pscustomobject] @{
        Distances = $distances
        Contrasts = $contrasts
        Candidates = @($candidates)
    }
}

function Get-VisualAuditRuntimeStateHierarchy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ScrollbarTrack,
        [Parameter(Mandatory)][string] $ScrollbarRest,
        [Parameter(Mandatory)][string] $ScrollbarHover,
        [Parameter(Mandatory)][string] $ScrollbarPressed,
        [Parameter(Mandatory)][string] $Editor,
        [Parameter(Mandatory)][string] $ActiveSelection,
        [Parameter(Mandatory)][string] $InactiveSelection,
        [Parameter(Mandatory)][string] $CurrentLine,
        [Parameter(Mandatory)][string] $FindHighlight,
        [Parameter(Mandatory)][string] $ReferenceHighlight,
        [Parameter(Mandatory)][string] $SyntaxForeground,
        [Parameter(Mandatory)][string] $Shell,
        [Parameter(Mandatory)][string] $SolutionTitle,
        [Parameter(Mandatory)][string] $ControlRest,
        [Parameter(Mandatory)][string] $FocusBorder
    )

    function Convert-HexColor {
        param([string] $Value)
        if ($Value -notmatch '^#[0-9A-Fa-f]{6}$') {
            throw "Runtime-state color '$Value' must use #RRGGBB notation."
        }
        return @(
            [Convert]::ToInt32($Value.Substring(1, 2), 16),
            [Convert]::ToInt32($Value.Substring(3, 2), 16),
            [Convert]::ToInt32($Value.Substring(5, 2), 16)
        )
    }

    function Get-ColorDistance {
        param([int[]] $Left, [int[]] $Right)
        return [Math]::Sqrt(
            [Math]::Pow(($Left[0] - $Right[0]) / 255.0, 2) +
            [Math]::Pow(($Left[1] - $Right[1]) / 255.0, 2) +
            [Math]::Pow(($Left[2] - $Right[2]) / 255.0, 2))
    }

    function Get-Luminance {
        param([int[]] $Rgb)
        $linear = foreach ($channel in $Rgb) {
            $value = $channel / 255.0
            if ($value -le 0.04045) { $value / 12.92 }
            else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
        }
        return (0.2126 * $linear[0]) + (0.7152 * $linear[1]) + (0.0722 * $linear[2])
    }

    function Get-ColorContrast {
        param([int[]] $First, [int[]] $Second)
        $firstLuminance = Get-Luminance $First
        $secondLuminance = Get-Luminance $Second
        return ([Math]::Max($firstLuminance, $secondLuminance) + 0.05) /
            ([Math]::Min($firstLuminance, $secondLuminance) + 0.05)
    }

    $colors = [ordered] @{}
    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        $colors[$entry.Key] = Convert-HexColor ([string] $entry.Value)
    }

    $distances = [ordered] @{
        ScrollbarRestHover = Get-ColorDistance $colors.ScrollbarRest $colors.ScrollbarHover
        ScrollbarHoverPressed = Get-ColorDistance $colors.ScrollbarHover $colors.ScrollbarPressed
        ActiveSelection = Get-ColorDistance $colors.Editor $colors.ActiveSelection
        InactiveSelection = Get-ColorDistance $colors.Editor $colors.InactiveSelection
        CurrentLine = Get-ColorDistance $colors.Editor $colors.CurrentLine
        Find = Get-ColorDistance $colors.Editor $colors.FindHighlight
        Reference = Get-ColorDistance $colors.Editor $colors.ReferenceHighlight
        SolutionTitle = Get-ColorDistance $colors.Shell $colors.SolutionTitle
    }
    $contrasts = [ordered] @{
        ScrollbarRest = Get-ColorContrast $colors.ScrollbarRest $colors.ScrollbarTrack
        ScrollbarHover = Get-ColorContrast $colors.ScrollbarHover $colors.ScrollbarTrack
        ScrollbarPressed = Get-ColorContrast $colors.ScrollbarPressed $colors.ScrollbarTrack
        FindSyntax = Get-ColorContrast $colors.SyntaxForeground $colors.FindHighlight
        ReferenceSyntax = Get-ColorContrast $colors.SyntaxForeground $colors.ReferenceHighlight
        Focus = Get-ColorContrast $colors.FocusBorder $colors.ControlRest
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($contrasts.ScrollbarRest -lt 3.0) {
        $candidates.Add("The resting scrollbar silhouette is only $([Math]::Round($contrasts.ScrollbarRest, 2)):1.")
    }
    if ($contrasts.ScrollbarHover -lt 3.5 -or $contrasts.ScrollbarPressed -lt 4.5 -or
        $distances.ScrollbarRestHover -lt 0.025 -or $distances.ScrollbarHoverPressed -lt 0.025) {
        $candidates.Add('Scrollbar rest, hover, and pressed states do not retain their ordered visual hierarchy.')
    }
    if ($distances.ActiveSelection -lt 0.12 -or
        ($distances.ActiveSelection - $distances.InactiveSelection) -lt 0.04) {
        $candidates.Add('Active selection is not sufficiently stronger than the inactive selection.')
    }
    if ($distances.CurrentLine -lt 0.06) {
        $candidates.Add('Current-line highlighting collapses into the editor background.')
    }
    if ($contrasts.FindSyntax -lt 4.5 -or $contrasts.ReferenceSyntax -lt 4.5 -or
        ($distances.Find - $distances.Reference) -lt 0.03) {
        $candidates.Add('Find/reference highlighting does not preserve text or its intended visibility ordering.')
    }
    if ($distances.SolutionTitle -lt 0.005 -or $distances.SolutionTitle -gt 0.08) {
        $candidates.Add('The resting solution-title surface is either collapsed or too prominent.')
    }
    if ($contrasts.Focus -lt 3.0) {
        $candidates.Add("The keyboard-focus border is only $([Math]::Round($contrasts.Focus, 2)):1.")
    }

    return [pscustomobject] @{
        Distances = $distances
        Contrasts = $contrasts
        Candidates = @($candidates)
    }
}

function Get-VisualAuditSyntaxHierarchy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Editor,
        [Parameter(Mandatory)][string] $InactiveSelection,
        [Parameter(Mandatory)][Collections.IDictionary] $Families
    )

    function Convert-SyntaxHex {
        param([string] $Value)
        if ($Value -notmatch '^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') {
            throw "Syntax-region color '$Value' must use #RRGGBB or #AARRGGBB notation."
        }
        $offset = if ($Value.Length -eq 9) { 3 } else { 1 }
        $alpha = if ($Value.Length -eq 9) { [Convert]::ToInt32($Value.Substring(1, 2), 16) } else { 255 }
        return [pscustomobject] @{
            A = $alpha
            R = [Convert]::ToInt32($Value.Substring($offset, 2), 16)
            G = [Convert]::ToInt32($Value.Substring($offset + 2, 2), 16)
            B = [Convert]::ToInt32($Value.Substring($offset + 4, 2), 16)
        }
    }

    function Get-SyntaxLuminance {
        param([double[]] $Rgb)
        $linear = foreach ($channel in $Rgb) {
            $value = $channel / 255.0
            if ($value -le 0.04045) { $value / 12.92 }
            else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
        }
        return (0.2126 * $linear[0]) + (0.7152 * $linear[1]) + (0.0722 * $linear[2])
    }

    function Convert-SyntaxToOkLab {
        param([double[]] $Rgb)
        $linear = foreach ($channel in $Rgb) {
            $value = $channel / 255.0
            if ($value -le 0.04045) { $value / 12.92 }
            else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
        }
        $l = (0.4122214708 * $linear[0]) + (0.5363325363 * $linear[1]) + (0.0514459929 * $linear[2])
        $m = (0.2119034982 * $linear[0]) + (0.6806995451 * $linear[1]) + (0.1073969566 * $linear[2])
        $s = (0.0883024619 * $linear[0]) + (0.2817188376 * $linear[1]) + (0.6299787005 * $linear[2])
        $lRoot = [Math]::Pow([Math]::Max(0.0, $l), 1.0 / 3.0)
        $mRoot = [Math]::Pow([Math]::Max(0.0, $m), 1.0 / 3.0)
        $sRoot = [Math]::Pow([Math]::Max(0.0, $s), 1.0 / 3.0)
        return [pscustomobject] @{
            L = (0.2104542553 * $lRoot) + (0.7936177850 * $mRoot) - (0.0040720468 * $sRoot)
            A = (1.9779984951 * $lRoot) - (2.4285922050 * $mRoot) + (0.4505937099 * $sRoot)
            B = (0.0259040371 * $lRoot) + (0.7827717662 * $mRoot) - (0.8086757660 * $sRoot)
        }
    }

    function Get-SyntaxDistance {
        param($First, $Second)
        return [Math]::Sqrt(
            [Math]::Pow($First.L - $Second.L, 2) +
            [Math]::Pow($First.A - $Second.A, 2) +
            [Math]::Pow($First.B - $Second.B, 2))
    }

    $editorArgb = Convert-SyntaxHex $Editor
    $inactiveArgb = Convert-SyntaxHex $InactiveSelection
    $alpha = $inactiveArgb.A / 255.0
    [double[]] $inactiveRgb = [double[]]::new(3)
    $inactiveRgb[0] = ($inactiveArgb.R * $alpha) + ($editorArgb.R * (1.0 - $alpha))
    $inactiveRgb[1] = ($inactiveArgb.G * $alpha) + ($editorArgb.G * (1.0 - $alpha))
    $inactiveRgb[2] = ($inactiveArgb.B * $alpha) + ($editorArgb.B * (1.0 - $alpha))
    $inactiveLuminance = Get-SyntaxLuminance $inactiveRgb
    $editorRgb = @([double] $editorArgb.R, [double] $editorArgb.G, [double] $editorArgb.B)
    $editorLuminance = Get-SyntaxLuminance $editorRgb

    $measurements = [ordered] @{}
    foreach ($name in $Families.Keys) {
        $argb = Convert-SyntaxHex ([string] $Families[$name])
        [double[]] $rgb = [double[]]::new(3)
        $rgb[0] = $argb.R
        $rgb[1] = $argb.G
        $rgb[2] = $argb.B
        $lab = Convert-SyntaxToOkLab $rgb
        $luminance = Get-SyntaxLuminance $rgb
        $contrast = ([Math]::Max($luminance, $inactiveLuminance) + 0.05) /
            ([Math]::Min($luminance, $inactiveLuminance) + 0.05)
        $editorContrast = ([Math]::Max($luminance, $editorLuminance) + 0.05) /
            ([Math]::Min($luminance, $editorLuminance) + 0.05)
        $measurements[$name] = [pscustomobject] @{
            Color = [string] $Families[$name]
            L = $lab.L
            A = $lab.A
            B = $lab.B
            Chroma = [Math]::Sqrt(($lab.A * $lab.A) + ($lab.B * $lab.B))
            EditorContrast = $editorContrast
            InactiveSelectionContrast = $contrast
        }
    }

    $distances = [ordered] @{}
    foreach ($pair in @(
        @('Type', 'Plain'),
        @('Method', 'Type'),
        @('Comment', 'Operator')
    )) {
        if ($measurements.Contains($pair[0]) -and $measurements.Contains($pair[1])) {
            $first = $measurements[$pair[0]]
            $second = $measurements[$pair[1]]
            $distances["$($pair[0])To$($pair[1])"] = Get-SyntaxDistance $first $second
        }
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($distances.Contains('TypeToPlain') -and $distances.TypeToPlain -lt 0.06) {
        $candidates.Add('The labelled type region collapses into the plain-text lane.')
    }
    if ($distances.Contains('MethodToType') -and $distances.MethodToType -lt 0.06) {
        $candidates.Add('The labelled method region collapses into the type lane.')
    }
    if ($distances.Contains('CommentToOperator') -and $distances.CommentToOperator -lt 0.06) {
        $candidates.Add('The labelled comment region collapses into the operator lane.')
    }
    $chromaticFamilies = @($measurements.Keys | Where-Object { $_ -notin @('Plain', 'Operator') })
    $lowChromaCount = @($chromaticFamilies | Where-Object { $measurements[$_].Chroma -lt 0.04 }).Count
    if ($chromaticFamilies.Count -gt 0 -and $lowChromaCount -ge [Math]::Ceiling($chromaticFamilies.Count * 0.75)) {
        $candidates.Add('The labelled syntax regions concentrate too heavily in low-chroma neutral lanes.')
    }
    foreach ($name in $measurements.Keys) {
        if ($measurements[$name].InactiveSelectionContrast -lt 4.5) {
            $candidates.Add("The labelled $name syntax region falls below 4.5:1 inside the inactive selection.")
        }
    }

    return [pscustomobject] @{
        Measurements = $measurements
        Distances = $distances
        Candidates = @($candidates)
    }
}

function Write-VisualAuditReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $VsixPath,
        [Parameter(Mandatory)][string] $RootSuffix,
        [Parameter(Mandatory)][Collections.IEnumerable] $Results,
        [Parameter(Mandatory)][Collections.IDictionary] $PackagedHashes,
        [Collections.IEnumerable] $InfrastructureNotes = @()
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Automated Visual Theme Audit')
    $lines.Add('')
    $lines.Add("- Generated: $([DateTimeOffset]::Now.ToString('u'))")
    $lines.Add("- VSIX: ``$([IO.Path]::GetFullPath($VsixPath))``")
    $lines.Add("- Root suffix: ``$RootSuffix``")
    $lines.Add('- Mode: advisory; this report never modifies theme sources')
    $lines.Add('')
    $lines.Add('## Artifact identity')
    $lines.Add('')
    $lines.Add('| Packaged payload | SHA-256 |')
    $lines.Add('|---|---|')
    foreach ($name in $PackagedHashes.Keys) {
        $lines.Add("| ``$name`` | ``$($PackagedHashes[$name])`` |")
    }
    $lines.Add('')
    $lines.Add('## Scenario results')
    $lines.Add('')
    foreach ($result in $Results) {
        $lines.Add("### $($result.Scenario)")
        $lines.Add('')
        $lines.Add("- Mean luminance delta: $([Math]::Round($result.MeanLuminanceDelta, 4))")
        $lines.Add("- Edge-strength ratio: $([Math]::Round($result.EdgeStrengthRatio, 4))")
        $shellProperty = $result.PSObject.Properties['ShellHierarchy']
        if ($null -ne $shellProperty -and $null -ne $shellProperty.Value) {
            $shell = $shellProperty.Value
            $lines.Add("- Shell hierarchy: top ``$($shell.Measurements.TopShell.Color)``, workspace ``$($shell.Measurements.Workspace.Color)``, dock surround ``$($shell.Measurements.DockSurround.Color)``, status ``$($shell.Measurements.StatusBar.Color)``")
            $lines.Add("- Status luminance delta: $([Math]::Round($shell.StatusLuminanceDelta, 4))")
        }
        $tabProperty = $result.PSObject.Properties['DocumentTabHierarchy']
        if ($null -ne $tabProperty -and $null -ne $tabProperty.Value) {
            $tabs = $tabProperty.Value
            $lines.Add("- Document tabs: shell ``$($tabs.Measurements.Shell.Color)``, channel ``$($tabs.Measurements.TabChannel.Color)``")
            $lines.Add("- Document-tab luminance delta: $([Math]::Round($tabs.LuminanceDelta, 4))")
        }
        if (@($result.Candidates).Count -eq 0) {
            $lines.Add('- Candidates: none from the current numerical heuristics')
        }
        else {
            foreach ($candidate in $result.Candidates) {
                $lines.Add("- Candidate: $candidate")
            }
        }
        $lines.Add('')
    }
    if (@($InfrastructureNotes).Count -gt 0) {
        $lines.Add('## Infrastructure notes')
        $lines.Add('')
        foreach ($note in $InfrastructureNotes) {
            $lines.Add("- $note")
        }
        $lines.Add('')
    }
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllLines($Path, $lines, (New-Object Text.UTF8Encoding($false)))
}

Export-ModuleMember -Function @(
    'Assert-VisualAuditPayloadIdentity',
    'Assert-VisualAuditThemeInventory',
    'Compare-VisualAuditImages',
    'Get-InstalledPkgdefHashes',
    'Get-VisualAuditFileHash',
    'Get-VisualAuditDominantColor',
    'Get-VisualAuditDocumentTabHierarchy',
    'Get-VisualAuditImageMetrics',
    'Get-VisualAuditInteractionHierarchy',
    'Get-VisualAuditRuntimeStateHierarchy',
    'Get-VisualAuditSyntaxHierarchy',
    'Get-VisualAuditShellHierarchy',
    'Get-VsixPkgdefHashes',
    'Save-WindowScreenshot',
    'Write-VisualAuditReport'
)

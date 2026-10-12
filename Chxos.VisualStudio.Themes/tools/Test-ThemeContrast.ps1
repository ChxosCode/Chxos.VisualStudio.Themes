[CmdletBinding()]
param(
    [Parameter()]
    [string] $ThemeDirectory,

    [Parameter()]
    [string] $PolicyPath,

    [Parameter()]
    [Alias('AliasReportPath')]
    [string] $AdvisoryReportPath,

    # Regression fixtures mutate one theme at a time. This optional focus keeps
    # inventory, identity, structure, and relevant Cosmora mapping checks global
    # while avoiding repeated deep checks on eight untouched disposable copies.
    [Parameter()]
    [string] $FocusThemeFile,

    [string] $CoverageReportPath,

    # Metadata fixture/alternate registry path; validation cannot be disabled.
    [string] $RenderingRegistryPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ThemeDirectory)) {
    $ThemeDirectory = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1'
}
if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    throw "Theme role policy was not found at '$PolicyPath'."
}
$policyScript = [scriptblock]::Create([IO.File]::ReadAllText((Resolve-Path -LiteralPath $PolicyPath).Path))
$rolePolicy = & $policyScript
if ($rolePolicy -isnot [Collections.IDictionary]) {
    throw "Theme role policy '$PolicyPath' did not return a dictionary."
}
Import-Module (Join-Path $PSScriptRoot 'ContextualContrast.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EditorSurfaceContrast.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EditorSelectionContrast.psm1')
Import-Module (Join-Path $PSScriptRoot 'PriorityThemeRefinements.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DebuggerHighlightContrast.psm1') -Force
$debuggerHighlightResults = New-Object System.Collections.Generic.List[object]
$priorityRefinementResults = New-Object System.Collections.Generic.List[object]
$editorSurfacePolicy = Get-Content (Join-Path $PSScriptRoot 'EditorSurfacePolicy.json') -Raw | ConvertFrom-Json
$editorSurfaceResults = New-Object System.Collections.Generic.List[object]
$contextualRelationships = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ContextualRelationships.json') -Raw | ConvertFrom-Json)
$componentInventory = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ComponentInventory.json') -Raw | ConvertFrom-Json)
$componentClassifications = @{}
foreach ($item in $componentInventory) { $componentClassifications[($item.key -join [char]31)] = $item }
$contextualResults = New-Object System.Collections.Generic.List[object]
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Advisories = New-Object System.Collections.Generic.List[object]
$script:PairCount = 0
$script:SingleComponentPairCount = 0
$script:DisabledAdvisoryCount = 0
$script:InteractionStateAdvisoryCount = 0
$script:SeparatorAdvisoryCount = 0
$script:SemanticVariableThemeCount = 0
$script:InactiveSelectionPairCount = 0
$script:ContextualEditorOverlayPairCount = 0
$script:CoreSyntaxRoleCount = 0
$script:CoreSyntaxSurfacePairCount = 0
$script:CoreSyntaxDistancePairCount = 0
$script:CoreSyntaxAdvisoryCount = 0
$script:NeutralSeparatorRoleCount = 0
$script:DocumentLayerThemeCount = 0
$script:NeutralInteractionRoleCount = 0
$script:GenericStrokeRoleCount = 0
$script:FocusIndicatorRoleCount = 0
$script:SelectedAccentRoleCount = 0
$script:ScrollbarStateThemeCount = 0
$script:HighlightSyntaxPairCount = 0
$script:MarkerOutlineRoleCount = 0
$script:MarkerSemanticThemeCount = 0
$script:CurrentLineSyntaxPairCount = 0
$script:SolutionTitleThemeCount = 0
$script:ModernSolutionTitleThemeCount = 0

function Add-Failure {
    param([string] $Message)
    $script:Failures.Add($Message)
}

function Add-Advisory {
    param(
        [string] $Theme,
        [string] $Kind,
        [string] $Role,
        [string] $Message
    )
    $script:Advisories.Add([pscustomobject]@{
        Theme = $Theme
        Kind = $Kind
        Role = $Role
        Message = $Message
    })
}

# Rendering metadata is additive. Keep the existing evaluator's source checks,
# thresholds and disposition switches unchanged while reporting evidence honestly.
$renderingContext = $null
$renderingMetadataErrors = @()
try {
    Import-Module (Join-Path $PSScriptRoot 'RenderingContracts.psm1') -Force
    $renderingArguments = @{ Policy = $rolePolicy }
    if (-not [string]::IsNullOrWhiteSpace($RenderingRegistryPath)) { $renderingArguments.RegistryPath = $RenderingRegistryPath }
    $renderingContext = Read-RenderingContracts @renderingArguments
    $renderingMetadataErrors = @(Test-RenderingContracts -Context $renderingContext)
    foreach ($metadataError in $renderingMetadataErrors) { Add-Failure "Rendering metadata: $metadataError" }
}
catch {
    $renderingMetadataErrors = @($_.Exception.Message)
    Add-Failure "Rendering metadata: $($_.Exception.Message)"
}

function Get-PolicyExpectedSource {
    param(
        [xml] $Xml,
        [Collections.IDictionary] $Entry
    )

    if ($Entry.ContainsKey('Literal')) {
        $literal = ([string] $Entry.Literal).ToUpperInvariant()
        if (-not (Test-RawColor $literal)) {
            return $null
        }
        return $literal
    }

    if (-not $Entry.ContainsKey('Anchor') -or
        [string]::IsNullOrWhiteSpace([string] $Entry.Anchor)) {
        return $null
    }
    $anchor = Get-ComponentSource $Xml 'Shell' ([string] $Entry.Anchor)
    if ($null -eq $anchor) {
        return $null
    }
    if ($Entry.ContainsKey('Alpha')) {
        $alpha = ([string] $Entry.Alpha).ToUpperInvariant()
        if ($alpha -notmatch '^[0-9A-F]{2}$' -or -not (Test-RawColor $anchor)) {
            return $null
        }
        return $alpha + $anchor.Substring(2)
    }
    return $anchor
}

function Get-ColorNode {
    param(
        [xml] $Xml,
        [string] $Category,
        [string] $Color
    )

    $cacheKey = "$Category`u{001F}$Color"
    if ([object]::ReferenceEquals($script:CurrentXml, $Xml) -and
        $null -ne $script:CurrentColorIndex -and
        $script:CurrentColorIndex.ContainsKey($cacheKey)) {
        return $script:CurrentColorIndex[$cacheKey]
    }

    $categories = @($Xml.Themes.Theme.Category | Where-Object { $_.Name -eq $Category })
    if ($categories.Count -ne 1) {
        Add-Failure "[$($Xml.Themes.Theme.Name)] Expected one category '$Category'; found $($categories.Count)."
        return $null
    }

    $colors = @($categories[0].Color | Where-Object { $_.Name -eq $Color })
    if ($colors.Count -ne 1) {
        Add-Failure "[$($Xml.Themes.Theme.Name)] Expected one color '$Category/$Color'; found $($colors.Count)."
        return $null
    }

    return $colors[0]
}

function Get-ComponentSource {
    param(
        [xml] $Xml,
        [string] $Category,
        [string] $Color,
        [ValidateSet('Foreground', 'Background')]
        [string] $Component = 'Background'
    )

    $node = Get-ColorNode -Xml $Xml -Category $Category -Color $Color
    if ($null -eq $node) {
        return $null
    }

    $componentNode = $node.$Component
    if ($null -eq $componentNode) {
        Add-Failure "[$($Xml.Themes.Theme.Name)] Missing $Component component at '$Category/$Color'."
        return $null
    }

    return [string] $componentNode.Source
}

function Test-RawColor {
    param([string] $Source)
    return $Source -match '^[0-9A-Fa-f]{8}$'
}

function Test-CanonicalGuid {
    param([string] $Value)
    return $Value -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$'
}

function ConvertTo-Rgb {
    param([string] $Source)
    # Structural validation records the precise category/color/component
    # diagnostic for malformed sources. Return a neutral sentinel here so later
    # aggregate/advisory calculations cannot replace that actionable failure
    # with a low-level Convert.ToInt32 exception.
    if (-not (Test-RawColor $Source)) {
        return @(0, 0, 0)
    }
    return @(
        [Convert]::ToInt32($Source.Substring(2, 2), 16),
        [Convert]::ToInt32($Source.Substring(4, 2), 16),
        [Convert]::ToInt32($Source.Substring(6, 2), 16)
    )
}

function ConvertTo-LinearChannel {
    param([double] $Channel)
    if ($Channel -le 0.04045) {
        return $Channel / 12.92
    }
    return [Math]::Pow(($Channel + 0.055) / 1.055, 2.4)
}

function Get-RelativeLuminance {
    param([double[]] $Rgb)
    return (
        0.2126 * (ConvertTo-LinearChannel ($Rgb[0] / 255.0)) +
        0.7152 * (ConvertTo-LinearChannel ($Rgb[1] / 255.0)) +
        0.0722 * (ConvertTo-LinearChannel ($Rgb[2] / 255.0))
    )
}

function ConvertTo-OkLab {
    param([string] $Source)

    if (-not (Test-RawColor $Source)) {
        throw "OKLab conversion requires an eight-digit ARGB color; received '$Source'."
    }

    $rgb = ConvertTo-Rgb $Source
    $red = ConvertTo-LinearChannel ($rgb[0] / 255.0)
    $green = ConvertTo-LinearChannel ($rgb[1] / 255.0)
    $blue = ConvertTo-LinearChannel ($rgb[2] / 255.0)

    $l = 0.4122214708 * $red + 0.5363325363 * $green + 0.0514459929 * $blue
    $m = 0.2119034982 * $red + 0.6806995451 * $green + 0.1073969566 * $blue
    $s = 0.0883024619 * $red + 0.2817188376 * $green + 0.6299787005 * $blue

    $lRoot = [Math]::Pow($l, 1.0 / 3.0)
    $mRoot = [Math]::Pow($m, 1.0 / 3.0)
    $sRoot = [Math]::Pow($s, 1.0 / 3.0)

    return @(
        (0.2104542553 * $lRoot + 0.7936177850 * $mRoot - 0.0040720468 * $sRoot),
        (1.9779984951 * $lRoot - 2.4285922050 * $mRoot + 0.4505937099 * $sRoot),
        (0.0259040371 * $lRoot + 0.7827717662 * $mRoot - 0.8086757660 * $sRoot)
    )
}

function Get-OkLabDistance {
    param(
        [string] $First,
        [string] $Second
    )

    $firstLab = ConvertTo-OkLab $First
    $secondLab = ConvertTo-OkLab $Second
    return [Math]::Sqrt(
        [Math]::Pow($firstLab[0] - $secondLab[0], 2) +
        [Math]::Pow($firstLab[1] - $secondLab[1], 2) +
        [Math]::Pow($firstLab[2] - $secondLab[2], 2)
    )
}

function Get-CompositedForeground {
    param(
        [string] $Foreground,
        [string] $Background
    )

    if (-not (Test-RawColor $Foreground) -or -not (Test-RawColor $Background)) {
        return @(0, 0, 0)
    }
    $alpha = [Convert]::ToInt32($Foreground.Substring(0, 2), 16) / 255.0
    $foregroundRgb = ConvertTo-Rgb $Foreground
    $backgroundRgb = ConvertTo-Rgb $Background
    return @(
        [Math]::Round($foregroundRgb[0] * $alpha + $backgroundRgb[0] * (1.0 - $alpha)),
        [Math]::Round($foregroundRgb[1] * $alpha + $backgroundRgb[1] * (1.0 - $alpha)),
        [Math]::Round($foregroundRgb[2] * $alpha + $backgroundRgb[2] * (1.0 - $alpha))
    )
}

function Get-CompositedSource {
    param(
        [string] $Foreground,
        [string] $Background
    )

    $rgb = Get-CompositedForeground -Foreground $Foreground -Background $Background
    return 'FF{0:X2}{1:X2}{2:X2}' -f ([int] $rgb[0]), ([int] $rgb[1]), ([int] $rgb[2])
}

function Get-ContrastRatio {
    param(
        [string] $Foreground,
        [string] $Background
    )

    if (-not (Test-RawColor $Foreground) -or -not (Test-RawColor $Background)) {
        throw "Contrast requires eight-digit ARGB colors; received '$Foreground' and '$Background'."
    }
    if (-not $Background.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Contrast requires an opaque background; received '$Background'."
    }

    $foregroundRgb = Get-CompositedForeground -Foreground $Foreground -Background $Background
    $backgroundRgb = ConvertTo-Rgb $Background
    $foregroundLuminance = Get-RelativeLuminance $foregroundRgb
    $backgroundLuminance = Get-RelativeLuminance $backgroundRgb
    $lighter = [Math]::Max($foregroundLuminance, $backgroundLuminance)
    $darker = [Math]::Min($foregroundLuminance, $backgroundLuminance)
    return ($lighter + 0.05) / ($darker + 0.05)
}

function Test-Contrast {
    param(
        [string] $Theme,
        [string] $Role,
        [string] $Foreground,
        [string] $Background,
        [double] $Minimum = 4.5
    )

    if (-not (Test-RawColor $Foreground) -or -not (Test-RawColor $Background)) {
        Add-Failure "[$Theme] $Role has a non-raw or malformed test color ('$Foreground' on '$Background')."
        return
    }
    if (-not $Background.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure "[$Theme] $Role cannot be tested because its background is not opaque ('$Background')."
        return
    }

    $ratio = Get-ContrastRatio -Foreground $Foreground -Background $Background
    $script:PairCount++
    if (($ratio + 0.0001) -lt $Minimum) {
        Add-Failure "[$Theme] $Role is $([Math]::Round($ratio, 2)):1; required $Minimum`:1 ('$Foreground' on '$Background')."
    }
}

function Test-ContextPair {
    param(
        [xml] $Xml,
        [string] $ForegroundCategory,
        [string] $ForegroundColor,
        [string] $BackgroundCategory,
        [string] $BackgroundColor,
        [string] $BackgroundBaseCategory,
        [string] $BackgroundBaseColor,
        [double] $Minimum = 4.5,
        [string] $Label = ''
    )

    $foreground = Get-ComponentSource -Xml $Xml -Category $ForegroundCategory -Color $ForegroundColor
    $background = Get-ComponentSource -Xml $Xml -Category $BackgroundCategory -Color $BackgroundColor
    if ($null -eq $foreground -or $null -eq $background) {
        return
    }
    if (-not $background.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::IsNullOrWhiteSpace($BackgroundBaseCategory) -or
            [string]::IsNullOrWhiteSpace($BackgroundBaseColor)) {
            Add-Failure "[$($Xml.Themes.Theme.Name)] $BackgroundCategory/$BackgroundColor is translucent ('$background') without a contextual base surface."
            return
        }
        $backgroundBase = Get-ComponentSource `
            -Xml $Xml `
            -Category $BackgroundBaseCategory `
            -Color $BackgroundBaseColor
        if ($null -eq $backgroundBase) {
            return
        }
        if (-not $backgroundBase.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "[$($Xml.Themes.Theme.Name)] $BackgroundBaseCategory/$BackgroundBaseColor must be opaque when compositing $BackgroundCategory/$BackgroundColor; found '$backgroundBase'."
            return
        }
        $background = Get-CompositedSource -Foreground $background -Background $backgroundBase
    }
    if ([string]::IsNullOrWhiteSpace($Label)) {
        $Label = "$ForegroundCategory/$ForegroundColor on $BackgroundCategory/$BackgroundColor"
    }
    Test-Contrast -Theme ([string] $Xml.Themes.Theme.Name) -Role $Label -Foreground $foreground -Background $background -Minimum $Minimum
}

function Get-StructureSignature {
    param([xml] $Xml)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($category in $Xml.Themes.Theme.Category) {
        $parts.Add("Category|$($category.Name)|$($category.GUID)")
        foreach ($color in $category.Color) {
            $backgroundType = if ($null -eq $color.Background) { '<missing>' } else { [string] $color.Background.Type }
            $foregroundType = if ($null -eq $color.Foreground) { '<missing>' } else { [string] $color.Foreground.Type }
            $parts.Add("Color|$($category.Name)|$($color.Name)|B:$backgroundType|F:$foregroundType")
        }
    }
    return $parts -join "`n"
}

function Get-RawAssignments {
    param([xml] $Xml)
    $assignments = @{}
    foreach ($category in $Xml.Themes.Theme.Category) {
        foreach ($color in $category.Color) {
            foreach ($componentName in @('Background', 'Foreground')) {
                $component = $color.$componentName
                if ($null -ne $component -and $component.Type -eq 'CT_RAW') {
                    $key = "$($category.Name)`u{001F}$($color.Name)`u{001F}$componentName"
                    $assignments[$key] = [string] $component.Source
                }
            }
        }
    }
    return $assignments
}

function Test-CosmoraMapping {
    param(
        [xml] $Base,
        [xml] $Shift
    )

    $baseAssignments = Get-RawAssignments $Base
    $shiftAssignments = Get-RawAssignments $Shift
    $forwardMapping = @{}
    $reverseMapping = @{}
    foreach ($path in $baseAssignments.Keys) {
        if (-not $shiftAssignments.ContainsKey($path)) {
            Add-Failure "[$($Shift.Themes.Theme.Name)] Missing raw assignment corresponding to '$path'."
            continue
        }
        $baseSource = $baseAssignments[$path]
        $shiftSource = $shiftAssignments[$path]
        if (-not $forwardMapping.ContainsKey($baseSource)) {
            $forwardMapping[$baseSource] = New-Object System.Collections.Generic.HashSet[string]
        }
        [void] $forwardMapping[$baseSource].Add($shiftSource)
        if (-not $reverseMapping.ContainsKey($shiftSource)) {
            $reverseMapping[$shiftSource] = New-Object System.Collections.Generic.HashSet[string]
        }
        [void] $reverseMapping[$shiftSource].Add($baseSource)
    }

    foreach ($source in $forwardMapping.Keys) {
        if ($forwardMapping[$source].Count -ne 1) {
            Add-Failure "[$($Shift.Themes.Theme.Name)] Cosmora source '$source' maps to $($forwardMapping[$source].Count) shifted values: $(@($forwardMapping[$source]) -join ', ')."
        }
    }
    foreach ($source in $reverseMapping.Keys) {
        if ($reverseMapping[$source].Count -ne 1) {
            Add-Failure "[$($Shift.Themes.Theme.Name)] Shifted value '$source' merges $($reverseMapping[$source].Count) Cosmora source values: $(@($reverseMapping[$source]) -join ', ')."
        }
    }
}

$expectedThemes = [ordered] @{
    'Amberroot.vstheme' = 'Amberroot'
    'Aquatoxic.vstheme' = 'Aquatoxic'
    'Biolume.vstheme' = 'Biolume'
    'Nullsector.vstheme' = 'Nullsector'
    'Cosmora.vstheme' = 'Cosmora'
    'CosmoraBlueshift.vstheme' = 'Cosmora Blueshift'
    'CosmoraRedshift.vstheme' = 'Cosmora Redshift'
    'CosmoraUltraviolet.vstheme' = 'Cosmora Ultraviolet'
    'Foundation.vstheme' = 'Foundation'
    'Hardline.vstheme' = 'Hardline'
    'Nightglass.vstheme' = 'Nightglass'
    'Pinknoise.vstheme' = 'Pinknoise'
    'Silverphase.vstheme' = 'Silverphase'
}
$expectedFiles = @($expectedThemes.Keys)
$expectedDarkGuid = '{1DED0138-47CE-435E-84EF-9EC1F439B749}'
$supportedComponentTypes = @{
    'CT_AUTOMATIC' = $true
    'CT_COLORINDEX' = $true
    'CT_INVALID' = $true
    'CT_RAW' = $true
    'CT_SYSCOLOR' = $true
}

$activeRoles = @(
    @('Cider', 'BreadcrumbButtonSelected'),
    @('Cider', 'BreadcrumbButtonSelectedOnHover'),
    @('Cider', 'SplitBarTabSelected'),
    @('Cider', 'TabItemSelected'),
    @('ClientDiagnosticsMemory', 'SnapshotButtonActive'),
    @('GraphicsDesigners', 'SnapshotButtonActive'),
    @('IntelliTrace', 'ReportHeaderActive'),
    @('ManifestDesigner', 'TabActive'),
    @('ManifestDesigner', 'TabInactive'),
    @('ProjectDesigner', 'SelectedCategoryTab'),
    @('Promotion', 'LightboxDialogButtonFocused'),
    @('SharePointTools', 'DesignerSelectedTab'),
    @('TaskRunnerExplorerControls', 'ButtonFocused'),
    @('TeamExplorer', 'InnerTabActive'),
    @('TeamExplorer', 'InnerTabInactive'),
    @('UserNotifications', 'BadgeButtonCountActive'),
    @('UserNotifications', 'BadgeButtonCountInactive'),
    @('UserNotifications', 'BadgeButtonCountMouseOverActive'),
    @('UserNotifications', 'BadgeButtonCountMouseOverInactive'),
    @('WorkItemEditor', 'GridActiveColumnHeader'),
    @('WorkItemEditor', 'GridActiveRowHeader')
)

$overlayRoles = [ordered] @{
    'Text Editor MEF Items/xml literal - embedded expression' = 'Background-only editor marker; syntax foreground must remain inherited.'
    'Text Editor MEF Items/HTML Server-Side Script' = 'Background-only editor marker; syntax foreground must remain inherited.'
    'Text Editor MEF Items/Call Return' = 'Background-only debugger marker; syntax foreground must remain inherited.'
    'Text Editor MEF Items/Call Return (historical mode)' = 'Background-only debugger marker; syntax foreground must remain inherited.'
    'Text Editor MEF Items/mergeEditor.WordDiffBoxAccepted' = 'Background-only merge marker; syntax foreground must remain inherited.'
    'Text Editor MEF Items/mergeEditor.WordDiffBoxConflict' = 'Background-only merge marker; syntax foreground must remain inherited.'
    'Text Editor Text Marker Items/Coverage Touched Area' = 'Background-only coverage marker; syntax foreground must remain inherited.'
    'Text Editor Text Marker Items/Coverage Not Touched Area' = 'Background-only coverage marker; syntax foreground must remain inherited.'
}

$disabledExemptions = @{}
foreach ($key in @(
    'Cider/ComboBoxDisabled',
    'Cider/CommandDisabled',
    'Cider/InputDisabled',
    'Cider/ListItemDisabled',
    'Cider/TabItemDisabled',
    'Cider/ToggleDisabled',
    'Cider/ToolWindowGroupDisabled',
    'CommonControls/ButtonDisabled',
    'Environment/AccessKeyToolTipDisabled',
    'Environment/PanelDisabledHyperlinkInsideSelectionActive',
    'Environment/PanelDisabledHyperlinkInsideSelectionInactive',
    'Environment/ToolboxDisabledContent',
    'Environment/ToolboxDisabledContentMouseOver',
    'Promotion/LightboxDialogButtonDisabled',
    'SearchControl/Disabled',
    'TaskRunnerExplorerControls/ButtonDisabled',
    'TeamExplorer/ButtonDisabled',
    'TeamExplorer/CallToActionButtonDisabled'
)) {
    $disabledExemptions[$key] = 'Disabled content is threshold-exempt but must remain distinguishable from its surface.'
}

$decorativeExemptions = @{}
foreach ($key in @(
    'Cider/ArtboardBackgroundAlternate',
    'NewProjectDialog/ImageBorder',
    'SharePointTools/DesignerWindow',
    'UserInformation/IDCardSeparator'
)) {
    $decorativeExemptions[$key] = 'Background, border, separator, or other non-content decoration.'
}

$normalTextRoles = @{}
foreach ($role in $activeRoles) {
    $normalTextRoles["$($role[0])/$($role[1])"] = 'Enabled active-state text.'
}

$glyphRoles = @{
    'NewProjectDialog/TreeArrowChecked' = 'Meaningful disclosure glyph; WCAG non-text contrast applies.'
}

$contextChecks = @(
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'TextFillPrimary'; BackgroundCategory = 'Shell'; BackgroundColor = 'SolidBackgroundFillBase'; Minimum = 4.5; Label = 'Primary text on base'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'TextFillSecondary'; BackgroundCategory = 'Shell'; BackgroundColor = 'SurfaceBackgroundFillDefault'; Minimum = 4.5; Label = 'Secondary text on surface'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'TextFillTertiary'; BackgroundCategory = 'Shell'; BackgroundColor = 'SurfaceBackgroundFillDefault'; Minimum = 4.5; Label = 'Tertiary text on surface'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'HyperlinkFillPrimary'; BackgroundCategory = 'Shell'; BackgroundColor = 'SurfaceBackgroundFillDefault'; Minimum = 4.5; Label = 'Hyperlink on surface'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'TextOnAccentFillPrimary'; BackgroundCategory = 'Shell'; BackgroundColor = 'AccentFillDefault'; Minimum = 4.5; Label = 'Primary text on accent'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'TextOnAccentFillSelectedText'; BackgroundCategory = 'Shell'; BackgroundColor = 'AccentFillSelectedTextBackground'; Minimum = 4.5; Label = 'Selected text on selected accent'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'SystemFillAttention'; BackgroundCategory = 'Shell'; BackgroundColor = 'SystemFillAttentionBackground'; Minimum = 4.5; Label = 'Attention semantic pair'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'SystemFillCaution'; BackgroundCategory = 'Shell'; BackgroundColor = 'SystemFillCautionBackground'; Minimum = 4.5; Label = 'Caution semantic pair'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'SystemFillCritical'; BackgroundCategory = 'Shell'; BackgroundColor = 'SystemFillCriticalBackground'; Minimum = 4.5; Label = 'Critical semantic pair'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'Shell'; ForegroundColor = 'SystemFillSuccess'; BackgroundCategory = 'Shell'; BackgroundColor = 'SystemFillSuccessBackground'; Minimum = 4.5; Label = 'Success semantic pair'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'ShellInternal'; ForegroundColor = 'StatusBarTextFillBuilding'; BackgroundCategory = 'ShellInternal'; BackgroundColor = 'StatusBarBackgroundFillBuilding'; Minimum = 4.5; Label = 'Building status'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'ShellInternal'; ForegroundColor = 'StatusBarTextFillDebugging'; BackgroundCategory = 'ShellInternal'; BackgroundColor = 'StatusBarBackgroundFillDebugging'; Minimum = 4.5; Label = 'Debugging status'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'ShellInternal'; ForegroundColor = 'StatusBarTextFillRest'; BackgroundCategory = 'ShellInternal'; BackgroundColor = 'StatusBarBackgroundFillRest'; BackgroundBaseCategory = 'ShellInternal'; BackgroundBaseColor = 'EnvironmentBody'; Minimum = 4.5; Label = 'Resting status'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'ShellInternal'; ForegroundColor = 'StatusBarTextFillSolutionLoading'; BackgroundCategory = 'ShellInternal'; BackgroundColor = 'StatusBarBackgroundFillSolutionLoading'; Minimum = 4.5; Label = 'Solution-loading status'; Classification = 'normal text' },
    [pscustomobject]@{ ForegroundCategory = 'ShellInternal'; ForegroundColor = 'CaptionControlCloseTextFillPrimary'; BackgroundCategory = 'ShellInternal'; BackgroundColor = 'CaptionControlCloseFillPrimary'; Minimum = 3.0; Label = 'Caption-close glyph'; Classification = 'meaningful glyph' }
)

$razorHtmlAnchors = @(
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'HTML Element Name'; AnchorCategory = 'Text Editor MEF Items'; AnchorColor = 'Markup Node' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'HTML Attribute Name'; AnchorCategory = 'Text Editor MEF Items'; AnchorColor = 'CSS Property Name' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'HTML Attribute Value'; AnchorCategory = 'Text Editor Language Service Items'; AnchorColor = 'String' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'HTML Entity'; AnchorCategory = 'Text Editor Language Service Items'; AnchorColor = 'Number' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'HTML Operator'; AnchorCategory = 'Text Editor MEF Items'; AnchorColor = 'HTML Comment' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'HTML Tag Delimiter'; AnchorCategory = 'Text Editor MEF Items'; AnchorColor = 'HTML Comment' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'RazorTagHelperAttribute'; AnchorCategory = 'Text Editor MEF Items'; AnchorColor = 'CSS Property Name' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'RazorTagHelperElement'; AnchorCategory = 'Text Editor Language Service Items'; AnchorColor = 'Keyword' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'RazorDirectiveAttribute'; AnchorCategory = 'Text Editor MEF Items'; AnchorColor = 'CSS Property Name' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'RazorComponentElement'; AnchorCategory = 'Text Editor Language Service Items'; AnchorColor = 'Keyword' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'RazorComponentAttribute'; AnchorCategory = 'Text Editor MEF Items'; AnchorColor = 'CSS Property Name' },
    [pscustomobject]@{ TargetCategory = 'Text Editor MEF Items'; TargetColor = 'RazorTransition'; AnchorCategory = 'Text Editor MEF Items'; AnchorColor = 'RazorDirective' }
)
$razorHtmlDistinctRoles = @(
    'HTML Element Name',
    'HTML Attribute Name',
    'HTML Attribute Value',
    'HTML Tag Delimiter',
    'RazorComponentElement'
)
$cssDistinctRoles = @(
    'CSS Keyword',
    'CSS Comment',
    'CSS Selector',
    'CSS Property Name',
    'CSS Property Value',
    'CSS String Value'
)
$semanticVariableRoles = @(
    'local name',
    'parameter name',
    'CppGlobalVariableSemanticTokenFormat',
    'CppLocalVariableSemanticTokenFormat',
    'CppParameterSemanticTokenFormat'
)
$semanticVariableAnchors = [ordered] @{
    'Amberroot' = 'FF91B8B5'
    'Aquatoxic' = 'FF86E6EC'
    'Biolume' = 'FFC4B5FD'
    'Nullsector' = 'FF71C4FF'
    'Cosmora' = 'FF9DB6FF'
    'Cosmora Blueshift' = 'FF7CC8F4'
    'Cosmora Redshift' = 'FFFFA08F'
    'Cosmora Ultraviolet' = 'FFE58FF2'
    'Foundation' = 'FF5EEAD4'
    'Hardline' = 'FF89AABD'
    'Nightglass' = 'FFA5B4FC'
    'Pinknoise' = 'FF56D8D0'
    'Silverphase' = 'FF72B5FF'
}
$inheritedMemberRoles = @(
    'field name',
    'property name',
    'event name'
)

$amberrootAnchors = @(
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillPrimary'; Component = 'Background'; Source = 'FFF2ECD8' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillSecondary'; Component = 'Background'; Source = 'FFB8B29E' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillTertiary'; Component = 'Background'; Source = 'FFB0AC98' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillDisabled'; Component = 'Background'; Source = 'FF858574' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillDefault'; Component = 'Background'; Source = 'FFD8AB52' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillSelectedTextBackground'; Component = 'Background'; Source = 'FFB88935' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'HyperlinkFillPrimary'; Component = 'Background'; Source = 'FFAFC58F' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextOnAccentFillPrimary'; Component = 'Background'; Source = 'FF1C1E19' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillBase'; Component = 'Background'; Source = 'FF303228' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSecondary'; Component = 'Background'; Source = 'FF36382D' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillTertiary'; Component = 'Background'; Source = 'FF3D4033' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSenary'; Component = 'Background'; Source = 'FF3C4733' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'ControlSolidFillDefault'; Component = 'Background'; Source = 'FF414438' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'CardStrokeDefaultSolid'; Component = 'Background'; Source = 'FF626650' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillAttention'; Component = 'Background'; Source = 'FF9CAF7F' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindowShelf'; Component = 'Background'; Source = 'FF393C30' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindow'; Component = 'Background'; Source = 'FF2F3127' },
    [pscustomobject]@{ Category = 'Text Editor Text Manager Items'; Color = 'Plain Text'; Component = 'Background'; Source = 'FF1C1E19' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Keyword'; Component = 'Foreground'; Source = 'FFE0B862' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'String'; Component = 'Foreground'; Source = 'FFAFC58F' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Number'; Component = 'Foreground'; Source = 'FFF9A05B' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS Property Name'; Component = 'Foreground'; Source = 'FFDBA07B' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'method name'; Component = 'Foreground'; Source = 'FFF1D18E' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'Markup Node'; Component = 'Foreground'; Source = 'FFCBDDB5' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'HTML Comment'; Component = 'Foreground'; Source = 'FFB7AB93' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS String Value'; Component = 'Foreground'; Source = 'FFAFC58F' }
)

$aquatoxicAnchors = @(
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillPrimary'; Component = 'Background'; Source = 'FFF4FBFD' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillSecondary'; Component = 'Background'; Source = 'FFD9EDF2' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillTertiary'; Component = 'Background'; Source = 'FFB8D8E0' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillDisabled'; Component = 'Background'; Source = 'FF6798A5' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillDefault'; Component = 'Background'; Source = 'FFA4D63A' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillSecondary'; Component = 'Background'; Source = 'E5C0E67B' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillSelectedTextBackground'; Component = 'Background'; Source = 'FF76A92C' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'HyperlinkFillPrimary'; Component = 'Background'; Source = 'FF86E6EC' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextOnAccentFillPrimary'; Component = 'Background'; Source = 'FF001D20' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillSuccess'; Component = 'Background'; Source = 'FFB3D88C' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillCaution'; Component = 'Background'; Source = 'FFE7A830' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillCritical'; Component = 'Background'; Source = 'FFD8787C' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillBase'; Component = 'Background'; Source = 'FF001D20' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSecondary'; Component = 'Background'; Source = 'FF072E32' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillTertiary'; Component = 'Background'; Source = 'FF103A3F' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSenary'; Component = 'Background'; Source = 'FF285F61' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindowShelf'; Component = 'Background'; Source = 'FF0D353A' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindow'; Component = 'Background'; Source = 'FF001C1F' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'ControlSolidFillDefault'; Component = 'Background'; Source = 'FF2D4F4E' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'urlformat'; Component = 'Foreground'; Source = 'FF43CFE0' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'NavigableSymbolFormat'; Component = 'Foreground'; Source = 'FF43CFE0' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS Property Name'; Component = 'Foreground'; Source = 'FF86E6EC' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'method name'; Component = 'Foreground'; Source = 'FFC0E67B' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS String Value'; Component = 'Foreground'; Source = 'FFE2F2B8' }
)

$pinknoiseAnchors = @(
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillPrimary'; Component = 'Background'; Source = 'FFF8EDF3' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillSecondary'; Component = 'Background'; Source = 'FFEAD8E2' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillTertiary'; Component = 'Background'; Source = 'FFC9A9B8' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillDisabled'; Component = 'Background'; Source = 'FF836C77' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillDefault'; Component = 'Background'; Source = 'FFF27CAF' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillSecondary'; Component = 'Background'; Source = 'E5F69BC0' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillSelectedTextBackground'; Component = 'Background'; Source = 'FFD65B91' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'HyperlinkFillPrimary'; Component = 'Background'; Source = 'FF56D8D0' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextOnAccentFillPrimary'; Component = 'Background'; Source = 'FF0D0A10' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillBase'; Component = 'Background'; Source = 'FF0D0A10' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSecondary'; Component = 'Background'; Source = 'FF171019' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillTertiary'; Component = 'Background'; Source = 'FF211522' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSenary'; Component = 'Background'; Source = 'FF244448' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindowShelf'; Component = 'Background'; Source = 'FF1C121E' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindow'; Component = 'Background'; Source = 'FF0C0910' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS Property Name'; Component = 'Foreground'; Source = 'FF56D8D0' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'method name'; Component = 'Foreground'; Source = 'FFF69BC0' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS String Value'; Component = 'Foreground'; Source = 'FFF3B6D1' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Keyword'; Component = 'Foreground'; Source = 'FFF27CAF' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'Markup Node'; Component = 'Foreground'; Source = 'FFB59AF7' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'HTML Comment'; Component = 'Foreground'; Source = 'FFA78E9B' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Number'; Component = 'Foreground'; Source = 'FFF3A56F' }
)

$nullsectorAnchors = @(
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillPrimary'; Component = 'Background'; Source = 'FFE7EEF7' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillSecondary'; Component = 'Background'; Source = 'FF9AA7B7' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillTertiary'; Component = 'Background'; Source = 'FF748395' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillDisabled'; Component = 'Background'; Source = 'FF5C6A7A' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillDefault'; Component = 'Background'; Source = 'FFB6FF2E' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillSelectedTextBackground'; Component = 'Background'; Source = 'FF8FD323' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'HyperlinkFillPrimary'; Component = 'Background'; Source = 'FF2ED9FF' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextOnAccentFillPrimary'; Component = 'Background'; Source = 'FF080B12' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillBase'; Component = 'Background'; Source = 'FF080B12' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSecondary'; Component = 'Background'; Source = 'FF0D121A' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillTertiary'; Component = 'Background'; Source = 'FF111722' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSenary'; Component = 'Background'; Source = 'FF101923' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'ControlSolidFillDefault'; Component = 'Background'; Source = 'FF101722' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'CardStrokeDefaultSolid'; Component = 'Background'; Source = 'FF293241' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'FocusStrokeOuter'; Component = 'Background'; Source = 'FFB6FF2E' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillAttention'; Component = 'Background'; Source = 'FF2ED9FF' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindowShelf'; Component = 'Background'; Source = 'FF0F151E' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindow'; Component = 'Background'; Source = 'FF070B11' },
    [pscustomobject]@{ Category = 'ShellInternal'; Color = 'EnvironmentLayeredBackground'; Component = 'Background'; Source = '4D19222C' },
    [pscustomobject]@{ Category = 'Text Editor Text Manager Items'; Color = 'Plain Text'; Component = 'Background'; Source = 'FF080B12' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Keyword'; Component = 'Foreground'; Source = 'FFFF4C96' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'String'; Component = 'Foreground'; Source = 'FFA7E36F' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Number'; Component = 'Foreground'; Source = 'FFFFC857' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Comment'; Component = 'Foreground'; Source = 'FF8593A5' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS Property Name'; Component = 'Foreground'; Source = 'FF2ED9FF' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'method name'; Component = 'Foreground'; Source = 'FFC9A7FF' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'class name'; Component = 'Foreground'; Source = 'FF63E6FF' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'local name'; Component = 'Foreground'; Source = 'FF71C4FF' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'Markup Node'; Component = 'Foreground'; Source = 'FFFF5CA8' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'HTML Comment'; Component = 'Foreground'; Source = 'FF8593A5' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS String Value'; Component = 'Foreground'; Source = 'FFA7E36F' }
)

$silverphaseAnchors = @(
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillPrimary'; Component = 'Background'; Source = 'FFE7EEF8' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillSecondary'; Component = 'Background'; Source = 'FFBCCBE0' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillTertiary'; Component = 'Background'; Source = 'FF91A6C4' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillDisabled'; Component = 'Background'; Source = 'FF60738E' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillDefault'; Component = 'Background'; Source = 'FF4DA6E6' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillSelectedTextBackground'; Component = 'Background'; Source = 'FF3A8FCD' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'HyperlinkFillPrimary'; Component = 'Background'; Source = 'FF7EE6F2' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextOnAccentFillPrimary'; Component = 'Background'; Source = 'FF0B0F16' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillBase'; Component = 'Background'; Source = 'FF0B0F16' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSecondary'; Component = 'Background'; Source = 'FF141A24' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillTertiary'; Component = 'Background'; Source = 'FF1D2633' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSenary'; Component = 'Background'; Source = 'FF2B405A' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'ControlSolidFillDefault'; Component = 'Background'; Source = 'FF323E53' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindowShelf'; Component = 'Background'; Source = 'FF19222D' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindow'; Component = 'Background'; Source = 'FF0A0E15' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Keyword'; Component = 'Foreground'; Source = 'FF978AF2' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'String'; Component = 'Foreground'; Source = 'FF7EE6F2' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS Property Name'; Component = 'Foreground'; Source = 'FFAFC8FF' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'method name'; Component = 'Foreground'; Source = 'FF9CCBF2' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'Markup Node'; Component = 'Foreground'; Source = 'FFB7A7F7' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'HTML Comment'; Component = 'Foreground'; Source = 'FF91A6C4' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS String Value'; Component = 'Foreground'; Source = 'FF7EE6F2' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'local name'; Component = 'Foreground'; Source = 'FF72B5FF' }
)

$hardlineAnchors = @(
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillPrimary'; Component = 'Background'; Source = 'FFFAFAF7' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillSecondary'; Component = 'Background'; Source = 'FFC3C7C5' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillTertiary'; Component = 'Background'; Source = 'FF929999' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextFillDisabled'; Component = 'Background'; Source = 'FF727979' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillDefault'; Component = 'Background'; Source = 'FFFFAA2B' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'AccentFillSelectedTextBackground'; Component = 'Background'; Source = 'FFD88700' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'HyperlinkFillPrimary'; Component = 'Background'; Source = 'FF89AABD' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'TextOnAccentFillPrimary'; Component = 'Background'; Source = 'FF080909' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillBase'; Component = 'Background'; Source = 'FF080909' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSecondary'; Component = 'Background'; Source = 'FF151718' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillTertiary'; Component = 'Background'; Source = 'FF292D2F' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SolidBackgroundFillSenary'; Component = 'Background'; Source = 'FF20384A' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'ControlSolidFillDefault'; Component = 'Background'; Source = 'FF34393C' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'CardStrokeDefaultSolid'; Component = 'Background'; Source = 'FF697277' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillAttention'; Component = 'Background'; Source = 'FF89AABD' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillCaution'; Component = 'Background'; Source = 'FFFFD34D' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillCritical'; Component = 'Background'; Source = 'FFFF625A' },
    [pscustomobject]@{ Category = 'Shell'; Color = 'SystemFillSuccess'; Component = 'Background'; Source = 'FF7FCB75' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindowShelf'; Component = 'Background'; Source = 'FF242829' },
    [pscustomobject]@{ Category = 'Cider'; Color = 'ToolWindow'; Component = 'Background'; Source = 'FF070808' },
    [pscustomobject]@{ Category = 'Text Editor Text Manager Items'; Color = 'Plain Text'; Component = 'Background'; Source = 'FF080909' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Keyword'; Component = 'Foreground'; Source = 'FFFFAA2B' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'String'; Component = 'Foreground'; Source = 'FFA7D7A9' },
    [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Number'; Component = 'Foreground'; Source = 'FFE6C785' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS Property Name'; Component = 'Foreground'; Source = 'FF89AABD' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'method name'; Component = 'Foreground'; Source = 'FFFFE066' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'Markup Node'; Component = 'Foreground'; Source = 'FF8EC8E5' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'HTML Comment'; Component = 'Foreground'; Source = 'FFB6A58E' },
    [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'CSS String Value'; Component = 'Foreground'; Source = 'FFA7D7A9' },
    [pscustomobject]@{ Category = 'Environment'; Color = 'PanelSeparator'; Component = 'Background'; Source = 'FF42484B' }
)

$documentLayerSources = @{
    'Amberroot' = '4D444639'
    'Aquatoxic' = '4D17555C'
    'Biolume' = '4D262C27'
    'Nullsector' = '4D19222C'
    'Cosmora' = '4D2D3445'
    'Cosmora Blueshift' = '4D1E2E4E'
    'Cosmora Redshift' = '4D442A22'
    'Cosmora Ultraviolet' = '4D3D2A3E'
    'Foundation' = '4D252528'
    'Hardline' = '4D33373B'
    'Nightglass' = '4D1F2A37'
    'Pinknoise' = '4D2E1E2E'
    'Silverphase' = '4D293344'
}

$cosmoraVariantAnchors = @{
    'Cosmora Ultraviolet' = @(
        [pscustomobject]@{ Color = 'TextFillPrimary'; Source = 'FFFFF0F8' },
        [pscustomobject]@{ Color = 'TextFillSecondary'; Source = 'FFE8C3D9' },
        [pscustomobject]@{ Color = 'TextFillTertiary'; Source = 'FFC998B4' },
        [pscustomobject]@{ Color = 'TextFillDisabled'; Source = 'FF956B83' },
        [pscustomobject]@{ Color = 'AccentFillDefault'; Source = 'FFA85FE4' },
        [pscustomobject]@{ Color = 'AccentFillSelectedTextBackground'; Source = 'FF9546CF' },
        [pscustomobject]@{ Color = 'HyperlinkFillPrimary'; Source = 'FFD5B7F1' },
        [pscustomobject]@{ Color = 'TextOnAccentFillPrimary'; Source = 'FF150C16' },
        [pscustomobject]@{ Color = 'SolidBackgroundFillBase'; Source = 'FF150C16' },
        [pscustomobject]@{ Color = 'SolidBackgroundFillSecondary'; Source = 'FF211522' },
        [pscustomobject]@{ Color = 'SolidBackgroundFillTertiary'; Source = 'FF291729' }
    )
    'Cosmora Redshift' = @(
        [pscustomobject]@{ Color = 'TextFillPrimary'; Source = 'FFFFF2E9' },
        [pscustomobject]@{ Color = 'TextFillSecondary'; Source = 'FFEBC7B0' },
        [pscustomobject]@{ Color = 'TextFillTertiary'; Source = 'FFCC9E7F' },
        [pscustomobject]@{ Color = 'TextFillDisabled'; Source = 'FF987166' },
        [pscustomobject]@{ Color = 'AccentFillDefault'; Source = 'FFE35F35' },
        [pscustomobject]@{ Color = 'AccentFillSelectedTextBackground'; Source = 'FFB74020' },
        [pscustomobject]@{ Color = 'HyperlinkFillPrimary'; Source = 'FFF3B69B' },
        [pscustomobject]@{ Color = 'TextOnAccentFillPrimary'; Source = 'FF190C08' },
        [pscustomobject]@{ Color = 'SolidBackgroundFillBase'; Source = 'FF190C08' },
        [pscustomobject]@{ Color = 'SolidBackgroundFillSecondary'; Source = 'FF261510' },
        [pscustomobject]@{ Color = 'SolidBackgroundFillTertiary'; Source = 'FF301710' }
    )
}

$resolvedDirectory = [IO.Path]::GetFullPath($ThemeDirectory)
if (-not (Test-Path -LiteralPath $resolvedDirectory -PathType Container)) {
    Write-Error "Theme directory does not exist: $resolvedDirectory"
    exit 1
}

$themeCatalog = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json
if ($themeCatalog.Count -ne 13) { throw 'Theme catalog must retain thirteen identities.' }
foreach ($catalogEntry in $themeCatalog) {
    if (-not $expectedThemes.Contains($catalogEntry.File) -or $expectedThemes[$catalogEntry.File] -cne $catalogEntry.Name) { throw 'Catalog differs from independent theme identity pins.' }
}

$themeFiles = @(Get-ChildItem -LiteralPath $resolvedDirectory -Filter '*.vstheme' -File | Sort-Object Name)
$actualNames = @($themeFiles.Name)
if (-not [string]::IsNullOrWhiteSpace($FocusThemeFile) -and $FocusThemeFile -notin $actualNames) {
    Add-Failure "Focused regression theme '$FocusThemeFile' was not found."
}
foreach ($name in $expectedFiles) {
    if ($name -notin $actualNames) {
        Add-Failure "Missing expected theme file '$name'."
    }
}
foreach ($name in $actualNames) {
    if ($name -notin $expectedFiles) {
        Add-Failure "Unexpected theme file '$name'; update the validator inventory intentionally."
    }
}

$themesByFile = @{}
$themeGuids = @{}
$baseSignature = $null
$focusedSignature = $null
foreach ($file in $themeFiles) {
    try {
        [xml] $xml = [IO.File]::ReadAllText($file.FullName)
    }
    catch {
        Add-Failure "[$($file.Name)] Invalid XML: $($_.Exception.Message)"
        continue
    }

    $rootNodes = @($xml.SelectNodes('/Themes'))
    if ($rootNodes.Count -ne 1 -or $xml.DocumentElement.LocalName -cne 'Themes') {
        Add-Failure "[$($file.Name)] Expected exactly one <Themes> document root; found $($rootNodes.Count)."
        continue
    }
    $themeNodes = @($xml.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element -and $_.LocalName -ceq 'Theme' })
    if ($themeNodes.Count -ne 1) {
        Add-Failure "[$($file.Name)] Expected exactly one <Theme> element; found $($themeNodes.Count)."
        continue
    }

    $themesByFile[$file.Name] = $xml
    $themeName = [string] $xml.Themes.Theme.Name
    if ($expectedThemes.Contains($file.Name) -and $themeName -cne $expectedThemes[$file.Name]) {
        Add-Failure "[$($file.Name)] Expected theme display name '$($expectedThemes[$file.Name])'; found '$themeName'."
    }
    $themeGuidValue = [string] $xml.Themes.Theme.GUID
    $themeGuid = $themeGuidValue.ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($themeGuid)) {
        Add-Failure "[$themeName] Theme GUID is missing."
    }
    elseif (-not (Test-CanonicalGuid $themeGuidValue)) {
        Add-Failure "[$themeName] Theme GUID '$themeGuidValue' is not in canonical brace form."
    }
    elseif ($themeGuids.ContainsKey($themeGuid)) {
        Add-Failure "[$themeName] Theme GUID '$themeGuid' duplicates '$($themeGuids[$themeGuid])'."
    }
    else {
        $themeGuids[$themeGuid] = $themeName
    }

    foreach ($attributeName in @('BaseGUID', 'FallbackId')) {
        $guidValue = [string] $xml.Themes.Theme.$attributeName
        if (-not (Test-CanonicalGuid $guidValue)) {
            Add-Failure "[$themeName] $attributeName '$guidValue' is not in canonical brace form."
        }
        elseif ($guidValue.ToUpperInvariant() -cne $expectedDarkGuid) {
            Add-Failure "[$themeName] $attributeName must be the Visual Studio Dark GUID '$expectedDarkGuid'; found '$guidValue'."
        }
    }

    if ([string]::IsNullOrWhiteSpace($FocusThemeFile)) {
        $signature = Get-StructureSignature $xml
        if ($null -eq $baseSignature) {
            $baseSignature = $signature
        }
        elseif ($signature -cne $baseSignature) {
            Add-Failure "[$themeName] Category/color/component structure differs from the first theme."
        }
    }
    elseif ($file.Name -ceq $FocusThemeFile) {
        $focusedSignature = Get-StructureSignature $xml
    }
    elseif ($null -eq $baseSignature) {
        $baseSignature = Get-StructureSignature $xml
    }

    if (-not [string]::IsNullOrWhiteSpace($FocusThemeFile) -and $file.Name -cne $FocusThemeFile) {
        continue
    }

    $script:CurrentXml = $xml
    $script:CurrentColorIndex = @{}
    foreach ($indexedCategory in $xml.Themes.Theme.Category) {
        foreach ($indexedColor in $indexedCategory.Color) {
            $indexKey = "$($indexedCategory.Name)`u{001F}$($indexedColor.Name)"
            if (-not $script:CurrentColorIndex.ContainsKey($indexKey)) {
                $script:CurrentColorIndex[$indexKey] = $indexedColor
            }
        }
    }

    try {
        foreach ($result in @(Test-ContextualRelationships -Theme $xml -Relationships $contextualRelationships)) {
            $contextualResults.Add($result)
            if ($result.Status -in @('failed','invalid')) { Add-Failure "[$themeName] Contextual $($result.Id): $($result.Detail)" }
        }
    }
    catch { Add-Failure "[$themeName] Contextual registry: $($_.Exception.Message)" }
    try {
        $surfaceSyntax = @($rolePolicy.EditorSyntaxFamilies) + @('Struct','Interface','Control','Directive' | ForEach-Object { $rolePolicy.CoreSyntaxFamilyRoles[$_] })
        $surfaceSyntax = @($surfaceSyntax | ForEach-Object { [pscustomobject]$_ } | Sort-Object Category,Role -Unique)
        foreach ($result in @(Test-EditorSurfaceContrast -Theme $xml -Policy $editorSurfacePolicy -SyntaxFamilies $surfaceSyntax)) {
            $editorSurfaceResults.Add($result)
            if ($result.Status -eq 'failed') { Add-Failure "[$themeName] Editor surface $($result.Role)/$($result.Component): $($result.Detail)" }
        }
    }
    catch { Add-Failure "[$themeName] Editor surface registry: $($_.Exception.Message)" }

    $categoryNames = @{}
    $categoryGuids = @{}
    foreach ($category in $xml.Themes.Theme.Category) {
        $categoryName = [string] $category.Name
        $categoryGuidValue = [string] $category.GUID
        if ([string]::IsNullOrWhiteSpace($categoryName)) {
            Add-Failure "[$themeName] A category has no name."
        }
        elseif ($categoryNames.ContainsKey($categoryName)) {
            Add-Failure "[$themeName] Category name '$categoryName' is duplicated."
        }
        else {
            $categoryNames[$categoryName] = $true
        }
        if (-not (Test-CanonicalGuid $categoryGuidValue)) {
            Add-Failure "[$themeName] Category '$categoryName' GUID '$categoryGuidValue' is not in canonical brace form."
        }
        else {
            $normalizedCategoryGuid = $categoryGuidValue.ToUpperInvariant()
            if ($categoryGuids.ContainsKey($normalizedCategoryGuid)) {
                Add-Failure "[$themeName] Category '$categoryName' GUID '$categoryGuidValue' duplicates category '$($categoryGuids[$normalizedCategoryGuid])'."
            }
            else {
                $categoryGuids[$normalizedCategoryGuid] = $categoryName
            }
        }

        $colorNames = @{}
        foreach ($color in $category.Color) {
            $colorName = [string] $color.Name
            if ([string]::IsNullOrWhiteSpace($colorName)) {
                Add-Failure "[$themeName] Category '$categoryName' contains a color with no name."
            }
            elseif ($colorNames.ContainsKey($colorName)) {
                Add-Failure "[$themeName] Color '$categoryName/$colorName' is duplicated."
            }
            else {
                $colorNames[$colorName] = $true
            }

            $components = @($color.SelectNodes('./Background | ./Foreground'))
            if ($components.Count -eq 0) {
                Add-Failure "[$themeName] Color '$categoryName/$colorName' must define at least one Background or Foreground component."
            }
            foreach ($componentName in @('Background', 'Foreground')) {
                $componentNodes = @($color.SelectNodes("./$componentName"))
                if ($componentNodes.Count -gt 1) {
                    Add-Failure "[$themeName] Color '$categoryName/$colorName' defines $($componentNodes.Count) $componentName components."
                }
            }
            foreach ($component in $components) {
                $componentKey = @($categoryName, $colorName, $component.LocalName) -join [char]31
                if (-not $componentClassifications.ContainsKey($componentKey)) {
                    Add-Failure "[$themeName] Unclassified new component '$categoryName/$colorName/$($component.LocalName)'. Register its semantic disposition."
                }
                $componentType = [string] $component.Type
                $componentSource = [string] $component.Source
                if (-not $supportedComponentTypes.ContainsKey($componentType)) {
                    Add-Failure "[$themeName] $categoryName/$colorName/$($component.LocalName) uses unsupported component type '$componentType'."
                }
                if (-not (Test-RawColor $componentSource)) {
                    Add-Failure "[$themeName] $categoryName/$colorName/$($component.LocalName) source '$componentSource' is not eight-digit hexadecimal ARGB."
                }
            }
        }
    }

    if (@($xml.Themes.Theme.Category).Count -ne 89) {
        Add-Failure "[$themeName] Expected 89 categories; found $(@($xml.Themes.Theme.Category).Count)."
    }
    if (@($xml.Themes.Theme.Category.Color).Count -ne 3114) {
        Add-Failure "[$themeName] Expected 3,114 colors; found $(@($xml.Themes.Theme.Category.Color).Count)."
    }

    $darkOnAccent = Get-ComponentSource $xml 'Shell' 'TextOnAccentFillPrimary'
    $primaryText = Get-ComponentSource $xml 'Shell' 'TextFillPrimary'
    $accentBackground = Get-ComponentSource $xml 'Shell' 'AccentFillSelectedTextBackground'
    $expectedActiveForeground = if ($themeName -like 'Cosmora*') { $primaryText } else { $darkOnAccent }
    foreach ($role in $activeRoles) {
        $node = Get-ColorNode -Xml $xml -Category $role[0] -Color $role[1]
        if ($null -eq $node) { continue }
        if ($node.Foreground.Type -ne 'CT_RAW' -or $node.Foreground.Source -cne $expectedActiveForeground) {
            Add-Failure "[$themeName] $($role[0])/$($role[1]) does not use the required active foreground '$expectedActiveForeground'."
        }
        if ($node.Background.Type -ne 'CT_RAW' -or $node.Background.Source -cne $accentBackground) {
            Add-Failure "[$themeName] $($role[0])/$($role[1]) does not use the selected-accent background '$accentBackground'."
        }
    }

    foreach ($key in $overlayRoles.Keys) {
        $segments = $key.Split('/', 2)
        $node = Get-ColorNode -Xml $xml -Category $segments[0] -Color $segments[1]
        if ($null -eq $node) { continue }
        if ($node.Foreground.Type -ne 'CT_INVALID' -or $node.Foreground.Source -cne '00000000') {
            Add-Failure "[$themeName] $key must preserve syntax with CT_INVALID/00000000 foreground."
        }
        if ($node.Background.Type -ne 'CT_RAW' -or
            -not (Test-RawColor ([string] $node.Background.Source)) -or
            -not ([string] $node.Background.Source).StartsWith('FF', [StringComparison]::Ordinal)) {
            Add-Failure "[$themeName] $key must use an opaque CT_RAW editor RGB background."
        }
    }

    foreach ($category in $xml.Themes.Theme.Category) {
        foreach ($color in $category.Color) {
            $foreground = $color.Foreground
            $background = $color.Background
            if ($null -eq $foreground -or $null -eq $background) { continue }
            if ($foreground.Type -ne 'CT_RAW' -or $background.Type -ne 'CT_RAW') { continue }
            $foregroundSource = [string] $foreground.Source
            $backgroundSource = [string] $background.Source
            if (-not (Test-RawColor $foregroundSource) -or -not (Test-RawColor $backgroundSource)) { continue }
            if (-not $backgroundSource.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) { continue }

            $key = "$($category.Name)/$($color.Name)"

            # Normal selection preserves syntax; its Foreground override is not
            # painted text. Dedicated composited syntax checks own these roles.
            if ($key -in @('Text Editor Text Manager Items/Selected Text','Text Editor Text Manager Items/Inactive Selected Text')) { continue }
            # Installed DifferenceBrushManager uses these foregrounds as pens
            # and repeated hatching. EditorSurfaceContrast validates them using
            # their actual consumers, separately from inherited syntax text.
            if ($key -in @('Text Editor MEF Items/deltadiff.add.word', 'Text Editor MEF Items/deltadiff.remove.word', 'Text Editor MEF Items/deltadiff.overview.color')) { continue }
            if ($disabledExemptions.ContainsKey($key)) {
                if ($foregroundSource -ceq $backgroundSource) {
                    Add-Failure "[$themeName] Disabled role '$key' has identical foreground and background '$foregroundSource'."
                }
                continue
            }
            if ($decorativeExemptions.ContainsKey($key)) { continue }
            $minimum = if ($glyphRoles.ContainsKey($key)) { 3.0 } else { 4.5 }
            $classification = if ($glyphRoles.ContainsKey($key)) {
                'meaningful glyph'
            }
            elseif ($normalTextRoles.ContainsKey($key)) {
                'normal text'
            }
            else {
                'unclassified enabled pair treated as normal text'
            }
            Test-Contrast -Theme $themeName -Role "$key [$classification]" -Foreground $foregroundSource -Background $backgroundSource -Minimum $minimum
        }
    }

    foreach ($key in $disabledExemptions.Keys) {
        $segments = $key.Split('/', 2)
        $node = Get-ColorNode -Xml $xml -Category $segments[0] -Color $segments[1]
        if ($null -eq $node -or $null -eq $node.Foreground -or $null -eq $node.Background) { continue }
        if ($node.Foreground.Type -eq 'CT_RAW' -and $node.Background.Type -eq 'CT_RAW' -and $node.Foreground.Source -ceq $node.Background.Source) {
            Add-Failure "[$themeName] Disabled role '$key' has identical raw foreground and background."
        }
    }

    foreach ($check in $contextChecks) {
        Test-ContextPair `
            -Xml $xml `
            -ForegroundCategory $check.ForegroundCategory `
            -ForegroundColor $check.ForegroundColor `
            -BackgroundCategory $check.BackgroundCategory `
            -BackgroundColor $check.BackgroundColor `
            -BackgroundBaseCategory $check.BackgroundBaseCategory `
            -BackgroundBaseColor $check.BackgroundBaseColor `
            -Minimum $check.Minimum `
            -Label "$($check.Label) [$($check.Classification)]"
    }

    foreach ($entry in $rolePolicy.OpaqueContent) {
        $source = Get-ComponentSource $xml 'Environment' $entry.Role
        $anchor = Get-ComponentSource $xml 'Shell' $entry.Anchor
        if ($null -eq $source -or $null -eq $anchor) { continue }
        if (-not $source.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "[$themeName] Environment/$($entry.Role) [$($entry.Classification)] must be opaque; found '$source'."
        }
        if ($source -cne $anchor) {
            Add-Failure "[$themeName] Environment/$($entry.Role) [$($entry.Classification)] must use Shell/$($entry.Anchor) '$anchor'; found '$source'."
        }

        $surface = Get-ComponentSource $xml $entry.SurfaceCategory $entry.SurfaceRole
        if ($null -eq $surface) { continue }
        if (-not $surface.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            if ([string]::IsNullOrWhiteSpace([string] $entry.SurfaceBase)) {
                Add-Failure "[$themeName] Environment/$($entry.Role) has translucent surface $($entry.SurfaceCategory)/$($entry.SurfaceRole) '$surface' without a policy SurfaceBase."
                continue
            }
            $surfaceBase = Get-ComponentSource $xml 'Shell' $entry.SurfaceBase
            if ($null -eq $surfaceBase) { continue }
            $surface = Get-CompositedSource -Foreground $surface -Background $surfaceBase
        }
        $script:SingleComponentPairCount++
        Test-Contrast -Theme $themeName -Role "Environment/$($entry.Role) [$($entry.Classification), single-component policy]" -Foreground $source -Background $surface -Minimum ([double] $entry.Minimum)
    }

    foreach ($entry in $rolePolicy.SurfaceRoles) {
        $source = Get-ComponentSource $xml 'Environment' $entry.Role
        $anchor = Get-ComponentSource $xml $entry.AnchorCategory $entry.Anchor
        if ($null -eq $source -or $null -eq $anchor) { continue }
        if (-not $source.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "[$themeName] Environment/$($entry.Role) [$($entry.Classification)] must be an opaque surface; found '$source'."
        }
        if ($source -cne $anchor) {
            Add-Failure "[$themeName] Environment/$($entry.Role) [$($entry.Classification)] must match $($entry.AnchorCategory)/$($entry.Anchor) '$anchor'; found '$source'."
        }
    }

    $legacyLinkAnchor = Get-ComponentSource $xml 'Shell' 'HyperlinkFillPrimary'
    $legacyLinkSurface = Get-ComponentSource $xml 'Shell' 'SolidBackgroundFillSecondary'
    foreach ($role in $rolePolicy.EnabledLinks) {
        $source = Get-ComponentSource $xml 'Environment' $role
        if ($null -eq $source -or $null -eq $legacyLinkAnchor -or $null -eq $legacyLinkSurface) { continue }
        if (-not $source.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "[$themeName] Environment/$role [enabled hyperlink] must be opaque; found '$source'."
        }
        if ($source -cne $legacyLinkAnchor) {
            Add-Failure "[$themeName] Environment/$role [enabled hyperlink] must use Shell/HyperlinkFillPrimary '$legacyLinkAnchor'; found '$source'."
        }
        $script:SingleComponentPairCount++
        Test-Contrast -Theme $themeName -Role "Environment/$role [enabled hyperlink, single-component policy]" -Foreground $source -Background $legacyLinkSurface -Minimum 4.5
    }

    foreach ($entry in $rolePolicy.SelectionLinks) {
        $node = Get-ColorNode -Xml $xml -Category 'Environment' -Color $entry.Role
        if ($null -eq $node -or $null -eq $node.Foreground) { continue }
        $foreground = [string] $node.Foreground.Source
        $expectedForeground = Get-ComponentSource $xml 'Shell' $entry.ForegroundAnchor
        if ($foreground -cne $expectedForeground) {
            Add-Failure "[$themeName] Environment/$($entry.Role) selected hyperlink foreground must use Shell/$($entry.ForegroundAnchor) '$expectedForeground'; found '$foreground'."
        }

        if ([string]::IsNullOrWhiteSpace([string] $entry.BackgroundAnchor)) {
            $background = Get-ComponentSource $xml 'Shell' 'AccentFillSelectedTextBackground'
        }
        else {
            $background = [string] $node.Background.Source
            $expectedBackground = Get-ComponentSource $xml 'Shell' $entry.BackgroundAnchor
            if ($background -cne $expectedBackground) {
                Add-Failure "[$themeName] Environment/$($entry.Role) selected hyperlink background must use Shell/$($entry.BackgroundAnchor) '$expectedBackground'; found '$background'."
            }
        }
        if ($null -eq $background) { continue }
        if (-not $background.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            $backgroundBase = Get-ComponentSource $xml 'Shell' $entry.BackgroundBase
            if ($null -eq $backgroundBase) { continue }
            $background = Get-CompositedSource -Foreground $background -Background $backgroundBase
        }
        $script:SingleComponentPairCount++
        Test-Contrast -Theme $themeName -Role "Environment/$($entry.Role) [selected hyperlink]" -Foreground $foreground -Background $background -Minimum ([double] $entry.Minimum)
    }

    $semanticBorderSurface = Get-ComponentSource $xml 'Shell' 'SolidBackgroundFillTertiary'
    foreach ($entry in $rolePolicy.SemanticBorders) {
        $source = Get-ComponentSource $xml 'Environment' $entry.Role
        $anchor = Get-ComponentSource $xml 'Shell' $entry.Anchor
        if ($null -eq $source -or $null -eq $anchor -or $null -eq $semanticBorderSurface) { continue }
        if ($source -cne $anchor) {
            Add-Failure "[$themeName] Environment/$($entry.Role) [$($entry.Classification)] must use Shell/$($entry.Anchor) '$anchor'; found '$source'."
        }
        $script:SingleComponentPairCount++
        Test-Contrast -Theme $themeName -Role "Environment/$($entry.Role) [$($entry.Classification)]" -Foreground $source -Background $semanticBorderSurface -Minimum 3.0
        if ($entry.Role -like 'CommandBar*') {
            $script:SelectedAccentRoleCount++
        }
    }

    foreach ($entry in $rolePolicy.StatePairs) {
        $active = Get-ComponentSource $xml 'Environment' $entry.Active
        $inactive = Get-ComponentSource $xml 'Environment' $entry.Inactive
        if ($null -ne $active -and $null -ne $inactive -and $active -ceq $inactive) {
            Add-Failure "[$themeName] Environment/$($entry.Active) and Environment/$($entry.Inactive) collapse to '$active'. $($entry.Reason)"
        }
    }

    foreach ($entry in $rolePolicy.DisabledRoles) {
        $node = Get-ColorNode -Xml $xml -Category 'Environment' -Color $entry.Role
        if ($null -eq $node -or $null -eq $node.($entry.Component)) { continue }
        $source = [string] $node.($entry.Component).Source
        $anchor = Get-ComponentSource $xml 'Shell' $entry.Anchor
        $expectedSource = $anchor
        $anchorLabel = "Shell/$($entry.Anchor)"
        if ($entry.ContainsKey('Alpha')) {
            $alpha = [string] $entry.Alpha
            if ($alpha -notmatch '^[0-9A-Fa-f]{2}$' -or -not (Test-RawColor $anchor)) {
                Add-Failure "[$themeName] Environment/$($entry.Role) has an invalid disabled-role alpha policy '$alpha' for anchor '$anchor'."
                continue
            }
            $expectedSource = $alpha.ToUpperInvariant() + $anchor.Substring(2)
            $anchorLabel = "0x$($alpha.ToUpperInvariant())-alpha Shell/$($entry.Anchor)"
        }
        if ($source -cne $expectedSource) {
            Add-Failure "[$themeName] Environment/$($entry.Role) disabled content must use $anchorLabel '$expectedSource'; found '$source'."
        }

        $background = $legacyLinkSurface
        if ($entry.Role -like '*SelectionActive') {
            $background = Get-ComponentSource $xml 'Shell' 'AccentFillSelectedTextBackground'
        }
        elseif ($entry.Role -like '*SelectionInactive') {
            $subtle = Get-ComponentSource $xml 'Shell' 'AccentFillSenary'
            $background = Get-CompositedSource -Foreground $subtle -Background $legacyLinkSurface
        }
        if ($null -ne $background -and (Test-RawColor $source) -and (Test-RawColor $background)) {
            $ratio = Get-ContrastRatio -Foreground $source -Background $background
            $advisoryMinimum = if ($entry.ContainsKey('AdvisoryMinimum')) { [double] $entry.AdvisoryMinimum } else { 1.5 }
            if (($ratio + 0.0001) -lt $advisoryMinimum) {
                $script:DisabledAdvisoryCount++
                Add-Advisory -Theme $themeName -Kind 'disabled discoverability' -Role "Environment/$($entry.Role)" -Message "$($entry.Reason) Estimated contrast is $([Math]::Round($ratio, 2)):1; advisory target is $advisoryMinimum`:1."
            }
        }
    }

    $accentSource = Get-ComponentSource $xml 'Shell' 'AccentFillDefault'
    foreach ($entry in $rolePolicy.NeutralModernTokens) {
        $source = Get-ComponentSource $xml 'Shell' $entry.Role
        $expectedSource = Get-PolicyExpectedSource -Xml $xml -Entry $entry
        if ($null -eq $source -or $null -eq $expectedSource) {
            Add-Failure "[$themeName] Neutral modern-token policy '$($entry.Role)' is malformed or unresolved."
            continue
        }
        if ($source -cne $expectedSource) {
            Add-Failure "[$themeName] Shell/$($entry.Role) [$($entry.Classification)] must use '$expectedSource'; found '$source'."
        }
        if ($null -ne $accentSource -and
            $source.Substring(2) -ceq $accentSource.Substring(2)) {
            Add-Failure "[$themeName] Shell/$($entry.Role) [$($entry.Classification)] must not reuse the primary accent RGB '$($accentSource.Substring(2))'."
        }
        if ($entry.Role -like '*Stroke*') {
            $script:GenericStrokeRoleCount++
        }
        else {
            $script:NeutralInteractionRoleCount++
        }
    }

    foreach ($group in $rolePolicy.NeutralInteractionGroups) {
        $requiredProperties = @('Name', 'Category', 'Component', 'Roles')
        $missingProperties = @($requiredProperties | Where-Object {
            -not $group.ContainsKey($_) -or
            ($group[$_] -is [string] -and [string]::IsNullOrWhiteSpace([string] $group[$_]))
        })
        if ($missingProperties.Count -gt 0 -or @($group.Roles).Count -eq 0) {
            Add-Failure "[$themeName] Neutral interaction group '$($group.Name)' is malformed or missing: $($missingProperties -join ', ')."
            continue
        }
        $expectedSource = Get-PolicyExpectedSource -Xml $xml -Entry $group
        if ($null -eq $expectedSource) {
            Add-Failure "[$themeName] Neutral interaction group '$($group.Name)' has no valid literal or Shell anchor."
            continue
        }
        foreach ($role in @($group.Roles)) {
            $source = Get-ComponentSource $xml $group.Category $role $group.Component
            if ($null -eq $source) { continue }
            if ($source -cne $expectedSource) {
                Add-Failure "[$themeName] $($group.Category)/$role [$($group.Name)] must use '$expectedSource'; found '$source'."
            }
            if ($null -ne $accentSource -and
                $source.Substring(2) -ceq $accentSource.Substring(2)) {
                Add-Failure "[$themeName] $($group.Category)/$role [$($group.Name)] must not reuse the primary accent RGB '$($accentSource.Substring(2))'."
            }
            if ($group.Name -like '*stroke*') {
                $script:GenericStrokeRoleCount++
            }
            else {
                $script:NeutralInteractionRoleCount++
            }
        }
    }

    foreach ($entry in $rolePolicy.StrongNeutralBorders) {
        $source = Get-ComponentSource $xml $entry.Category $entry.Role
        $anchor = Get-ComponentSource $xml 'Shell' $entry.Anchor
        if ($null -eq $source -or $null -eq $anchor) { continue }
        if ($source -cne $anchor) {
            Add-Failure "[$themeName] $($entry.Category)/$($entry.Role) [$($entry.Classification)] must use Shell/$($entry.Anchor) '$anchor'; found '$source'."
        }
        $surface = Get-ComponentSource $xml 'Shell' 'SolidBackgroundFillSecondary'
        if ($null -ne $surface) {
            $script:SingleComponentPairCount++
            Test-Contrast -Theme $themeName -Role "$($entry.Category)/$($entry.Role) [$($entry.Classification)]" -Foreground $source -Background $surface -Minimum 3.0
        }
        $script:GenericStrokeRoleCount++
    }

    foreach ($entry in $rolePolicy.FocusIndicators) {
        $source = Get-ComponentSource $xml $entry.Category $entry.Role
        $anchor = Get-ComponentSource $xml 'Shell' $entry.Anchor
        if ($null -eq $source -or $null -eq $anchor) { continue }
        if ($source -cne $anchor) {
            Add-Failure "[$themeName] $($entry.Category)/$($entry.Role) [$($entry.Classification)] must use Shell/$($entry.Anchor) '$anchor'; found '$source'."
        }
        $surface = Get-ComponentSource $xml $entry.SurfaceCategory $entry.SurfaceRole
        if ($null -eq $surface) { continue }
        if (-not $surface.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            $surfaceBase = Get-ComponentSource $xml 'Shell' $entry.SurfaceBase
            if ($null -eq $surfaceBase) { continue }
            $surface = Get-CompositedSource -Foreground $surface -Background $surfaceBase
        }
        $script:SingleComponentPairCount++
        Test-Contrast -Theme $themeName -Role "$($entry.Category)/$($entry.Role) [$($entry.Classification)]" -Foreground $source -Background $surface -Minimum 3.0
        $script:FocusIndicatorRoleCount++
    }

    foreach ($entry in $rolePolicy.InteractionStatePairs) {
        $requiredProperties = @(
            'Name',
            'SurfaceBase',
            'HoverSurface',
            'PressedSurface',
            'HoverBorder',
            'PressedBorder',
            'HoverSurfaceAnchor',
            'HoverSurfaceAlpha',
            'PressedSurfaceLiteral',
            'HoverBorderAnchor',
            'HoverBorderAlpha',
            'PressedBorderAnchor',
            'RequireSurfaceDifference',
            'RequireBorderDifference'
        )
        $missingProperties = @($requiredProperties | Where-Object { -not $entry.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string] $entry[$_]) })
        if ($missingProperties.Count -gt 0) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' is missing: $($missingProperties -join ', ')."
            continue
        }

        $surfaceBase = Get-ComponentSource $xml 'Environment' $entry.SurfaceBase
        $hoverSurface = Get-ComponentSource $xml 'Environment' $entry.HoverSurface
        $pressedSurface = Get-ComponentSource $xml 'Environment' $entry.PressedSurface
        $hoverBorder = Get-ComponentSource $xml 'Environment' $entry.HoverBorder
        $pressedBorder = Get-ComponentSource $xml 'Environment' $entry.PressedBorder
        if ($null -eq $surfaceBase -or $null -eq $hoverSurface -or $null -eq $pressedSurface -or
            $null -eq $hoverBorder -or $null -eq $pressedBorder) {
            continue
        }
        if (-not $surfaceBase.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' requires an opaque Environment/$($entry.SurfaceBase) base; found '$surfaceBase'."
            continue
        }

        $hoverSurfaceAnchor = Get-ComponentSource $xml 'Shell' $entry.HoverSurfaceAnchor
        $hoverBorderAnchor = Get-ComponentSource $xml 'Shell' $entry.HoverBorderAnchor
        $pressedBorderAnchor = Get-ComponentSource $xml 'Shell' $entry.PressedBorderAnchor
        if ($null -eq $hoverSurfaceAnchor -or $null -eq $hoverBorderAnchor -or
            $null -eq $pressedBorderAnchor) {
            continue
        }
        if ($entry.HoverSurfaceAlpha -notmatch '^[0-9A-Fa-f]{2}$' -or
            $entry.HoverBorderAlpha -notmatch '^[0-9A-Fa-f]{2}$' -or
            -not (Test-RawColor ([string] $entry.PressedSurfaceLiteral))) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' has an invalid neutral state source."
            continue
        }

        $expectedHoverSurface = ([string] $entry.HoverSurfaceAlpha).ToUpperInvariant() + $hoverSurfaceAnchor.Substring(2)
        $expectedPressedSurface = ([string] $entry.PressedSurfaceLiteral).ToUpperInvariant()
        $expectedHoverBorder = ([string] $entry.HoverBorderAlpha).ToUpperInvariant() + $hoverBorderAnchor.Substring(2)
        $expectedPressedBorder = $pressedBorderAnchor
        if ($hoverSurface -cne $expectedHoverSurface) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' requires Environment/$($entry.HoverSurface) to use neutral hover source '$expectedHoverSurface'; found '$hoverSurface'."
        }
        if ($pressedSurface -cne $expectedPressedSurface) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' requires Environment/$($entry.PressedSurface) to use neutral pressed source '$expectedPressedSurface'; found '$pressedSurface'."
        }
        if ($hoverBorder -cne $expectedHoverBorder) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' requires Environment/$($entry.HoverBorder) to use neutral hover stroke '$expectedHoverBorder'; found '$hoverBorder'."
        }
        if ($pressedBorder -cne $expectedPressedBorder) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' requires Environment/$($entry.PressedBorder) to use Shell/$($entry.PressedBorderAnchor) '$expectedPressedBorder'; found '$pressedBorder'."
        }

        $effectiveHover = Get-CompositedSource -Foreground $hoverSurface -Background $surfaceBase
        $effectivePressed = Get-CompositedSource -Foreground $pressedSurface -Background $surfaceBase
        if ($entry.RequireSurfaceDifference -eq $true -and $effectiveHover -ceq $effectivePressed) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' requires distinct hover and pressed surfaces; both composite to '$effectiveHover'."
        }
        if ($entry.RequireBorderDifference -eq $true -and $hoverBorder -ceq $pressedBorder) {
            Add-Failure "[$themeName] Interaction-state policy '$($entry.Name)' requires distinct hover and pressed borders; both use '$hoverBorder'."
        }

        $script:SingleComponentPairCount++
        Test-Contrast -Theme $themeName -Role "Environment/$($entry.PressedBorder) [pressed-state border]" -Foreground $pressedBorder -Background $surfaceBase -Minimum 3.0
        $script:NeutralInteractionRoleCount += 2
        $script:GenericStrokeRoleCount += 2
    }

    foreach ($entry in $rolePolicy.SeparatorAdvisories) {
        $separator = Get-ComponentSource $xml 'Environment' $entry.Role
        $surface = Get-ComponentSource $xml $entry.SurfaceCategory $entry.SurfaceRole
        if ($null -eq $separator -or $null -eq $surface) { continue }
        if (-not $surface.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "[$themeName] Separator advisory Environment/$($entry.Role) requires an opaque $($entry.SurfaceCategory)/$($entry.SurfaceRole) surface; found '$surface'."
            continue
        }
        $ratio = Get-ContrastRatio -Foreground $separator -Background $surface
        $script:SeparatorAdvisoryCount++
        Add-Advisory -Theme $themeName -Kind 'separator strength' -Role "Environment/$($entry.Role)" -Message "Estimated adjacent contrast is $([Math]::Round($ratio, 2)):1 versus the official Dark reference of $($entry.ReferenceRatio):1. $($entry.Reason)"
    }

    foreach ($anchor in $razorHtmlAnchors) {
        $targetSource = Get-ComponentSource $xml $anchor.TargetCategory $anchor.TargetColor 'Foreground'
        $anchorSource = Get-ComponentSource $xml $anchor.AnchorCategory $anchor.AnchorColor 'Foreground'
        # Nullsector punctuation intentionally retains its original foreground
        # independently of the brighter comment family. Keep exact validation.
        if ($themeName -ceq 'Nullsector' -and $anchor.TargetCategory -ceq 'Text Editor MEF Items' -and $anchor.TargetColor -cin @('HTML Operator','HTML Tag Delimiter')) { $anchorSource = 'FF8693A2' }
        if ($null -ne $targetSource -and $null -ne $anchorSource -and $targetSource -cne $anchorSource) {
            Add-Failure "[$themeName] Razor/HTML semantic role $($anchor.TargetCategory)/$($anchor.TargetColor) must match $($anchor.AnchorCategory)/$($anchor.AnchorColor) '$anchorSource'; found '$targetSource'."
        }
    }
    $razorHtmlSources = @{}
    foreach ($role in $razorHtmlDistinctRoles) {
        $source = Get-ComponentSource $xml 'Text Editor MEF Items' $role 'Foreground'
        if ($null -ne $source) {
            if (-not $razorHtmlSources.ContainsKey($source)) {
                $razorHtmlSources[$source] = New-Object System.Collections.Generic.List[string]
            }
            $razorHtmlSources[$source].Add($role)
        }
    }
    foreach ($source in $razorHtmlSources.Keys) {
        if ($razorHtmlSources[$source].Count -gt 1) {
            Add-Failure "[$themeName] Razor/HTML hierarchy collapses distinct roles to '$source': $($razorHtmlSources[$source] -join ', ')."
        }
    }

    $cssPropertyValue = Get-ComponentSource $xml 'Text Editor MEF Items' 'CSS Property Value' 'Foreground'
    $editorText = Get-ComponentSource $xml 'Text Editor Language Service Items' 'Text' 'Foreground'
    if ($null -ne $cssPropertyValue -and $null -ne $editorText -and $cssPropertyValue -cne $editorText) {
        Add-Failure "[$themeName] CSS semantic role Text Editor MEF Items/CSS Property Value must match Text Editor Language Service Items/Text '$editorText'; found '$cssPropertyValue'."
    }

    $cssSources = @{}
    foreach ($role in $cssDistinctRoles) {
        $source = Get-ComponentSource $xml 'Text Editor MEF Items' $role 'Foreground'
        if ($null -ne $source) {
            if (-not $cssSources.ContainsKey($source)) {
                $cssSources[$source] = New-Object System.Collections.Generic.List[string]
            }
            $cssSources[$source].Add($role)
        }
    }
    foreach ($source in $cssSources.Keys) {
        if ($cssSources[$source].Count -gt 1) {
            Add-Failure "[$themeName] CSS hierarchy collapses distinct roles to '$source': $($cssSources[$source] -join ', ')."
        }
    }

    $cssPropertyName = Get-ComponentSource $xml 'Text Editor MEF Items' 'CSS Property Name' 'Foreground'
    if ($null -ne $cssPropertyName -and $null -ne $cssPropertyValue -and
        (Test-RawColor $cssPropertyName) -and (Test-RawColor $cssPropertyValue)) {
        $cssNameValueDistance = Get-OkLabDistance -First $cssPropertyName -Second $cssPropertyValue
        if (($cssNameValueDistance + 0.000001) -lt 0.08) {
            Add-Failure "[$themeName] CSS property-name/value OKLab distance is $([Math]::Round($cssNameValueDistance, 5)); minimum is 0.08 ('$cssPropertyName' to '$cssPropertyValue')."
        }
    }

    $editorBackground = Get-ComponentSource $xml 'Text Editor Text Manager Items' 'Plain Text' 'Background'
    $editorForeground = Get-ComponentSource $xml 'Text Editor Text Manager Items' 'Plain Text' 'Foreground'
    foreach ($result in Test-DebuggerHighlightContrast -Theme $xml -Policy $rolePolicy) {
        $debuggerHighlightResults.Add($result)
        if ($result.Status -ne 'passed') { Add-Failure "[$themeName] Debugger highlight $($result.Role): $($result.Status); foreground=$($result.ForegroundContrast), syntax=$($result.MinimumSyntaxContrast), surface=$($result.SurfaceContrast). $($result.Detail)" }
    }
    foreach ($result in Test-PriorityThemeRefinements -Theme $xml -Policy $rolePolicy) {
        $priorityRefinementResults.Add($result)
        if ($result.Enforced -and $result.Status -ne 'passed') {
            Add-Failure "[$themeName] Priority refinement $($result.Check): $($result.Component) [$($result.State)] $($result.Detail)"
        }
    }
    $editorSelectionBackground = Get-ComponentSource $xml 'Text Editor Text Manager Items' 'Selected Text' 'Background'
    $editorSelectionForeground = Get-ComponentSource $xml 'Text Editor Text Manager Items' 'Selected Text' 'Foreground'
    $editorInactiveSelectionBackground = Get-ComponentSource $xml 'Text Editor Text Manager Items' 'Inactive Selected Text' 'Background'
    $solidBackgroundSenary = Get-ComponentSource $xml 'Shell' 'SolidBackgroundFillSenary' 'Background'
    $expectedActiveSelection = $solidBackgroundSenary
    if ($rolePolicy.ActiveSelectionAnchors.ContainsKey($themeName)) {
        $expectedActiveSelection = [string] $rolePolicy.ActiveSelectionAnchors[$themeName]
    }
    if ($null -ne $editorSelectionBackground -and $null -ne $expectedActiveSelection -and
        $editorSelectionBackground -cne $expectedActiveSelection) {
        Add-Failure "[$themeName] Active editor selection Text Editor Text Manager Items/Selected Text/Background must use approved source '$expectedActiveSelection'; found '$editorSelectionBackground'."
    }

    $effectiveInactiveSelection = $null
    if ($null -eq $editorInactiveSelectionBackground -or $null -eq $editorBackground -or
        -not (Test-RawColor $editorInactiveSelectionBackground) -or -not (Test-RawColor $editorBackground)) {
        Add-Failure "[$themeName] Inactive editor selection requires valid eight-digit background sources for the selection overlay and editor surface."
    }
    elseif (-not $editorBackground.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure "[$themeName] Inactive editor selection requires an opaque editor background; found '$editorBackground'."
    }
    elseif (-not $editorInactiveSelectionBackground.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure "[$themeName] Inactive editor selection must use an opaque baked RGB fill; found '$editorInactiveSelectionBackground'."
    }
    else {
        try { $effectiveInactiveSelection = Get-NormalSelectionBackground -Source $editorInactiveSelectionBackground -Underlay $editorBackground } catch { Add-Failure "[$themeName] Selection model: $($_.Exception.Message)" }
    }

    if ($rolePolicy.InactiveSelectionAnchors.ContainsKey($themeName)) {
        $expectedInactiveSelection = [string] $rolePolicy.InactiveSelectionAnchors[$themeName]
        if ($editorInactiveSelectionBackground -cne $expectedInactiveSelection) {
            Add-Failure "[$themeName] Inactive editor selection must use the approved overlay '$expectedInactiveSelection'; found '$editorInactiveSelectionBackground'."
        }
    }

    if ($null -ne $effectiveInactiveSelection) {
        foreach ($entry in $rolePolicy.EditorSyntaxFamilies) {
            if ([string]::IsNullOrWhiteSpace([string] $entry.Category) -or
                [string]::IsNullOrWhiteSpace([string] $entry.Role) -or
                [string]::IsNullOrWhiteSpace([string] $entry.Classification)) {
                Add-Failure "[$themeName] Editor-syntax inactive-selection policy contains an incomplete entry."
                continue
            }

            $node = Get-ColorNode -Xml $xml -Category ([string] $entry.Category) -Color ([string] $entry.Role)
            if ($null -eq $node) { continue }
            if ([string] $node.Foreground.Type -ne 'CT_RAW') { continue }

            $foregroundSource = [string] $node.Foreground.Source
            if (-not (Test-RawColor $foregroundSource) -or
                -not $foregroundSource.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
                Add-Failure "[$themeName] $($entry.Category)/$($entry.Role) [$($entry.Classification)] must use an opaque raw foreground for inactive-selection validation; found '$foregroundSource'."
                continue
            }

            $script:InactiveSelectionPairCount++
            Test-Contrast -Theme $themeName -Role "$($entry.Category)/$($entry.Role) inside inactive selection [$($entry.Classification)]" -Foreground $foregroundSource -Background $effectiveInactiveSelection -Minimum 4.5
        }
    }

    $findHighlightNode = Get-ColorNode -Xml $xml -Category 'Text Editor MEF Items' -Color 'MarkerFormatDefinition/FindHighlight'
    $referenceHighlightNode = Get-ColorNode -Xml $xml -Category 'Text Editor MEF Items' -Color 'MarkerFormatDefinition/HighlightedReference'
    $effectiveFindHighlight = $null
    $effectiveReferenceHighlight = $null
    $markerHighlightSurfaces = New-Object System.Collections.Generic.List[object]
    if (-not $rolePolicy.FindHighlightAnchors.ContainsKey($themeName) -or
        -not $rolePolicy.MarkerHighlightAnchors.ContainsKey($themeName)) {
        Add-Failure "[$themeName] Find/marker highlight policy is incomplete."
    }
    elseif ($null -ne $findHighlightNode -and $null -ne $referenceHighlightNode) {
        $findHighlight = [string] $findHighlightNode.Background.Source
        $referenceHighlight = [string] $referenceHighlightNode.Background.Source
        $expectedFindHighlight = [string] $rolePolicy.FindHighlightAnchors[$themeName]
        $markerPolicy = $rolePolicy.MarkerHighlightAnchors[$themeName]
        $expectedReferenceHighlight = [string] $markerPolicy.ReferenceFill
        if ($findHighlight -cne $expectedFindHighlight) {
            Add-Failure "[$themeName] Find highlight must use approved source '$expectedFindHighlight'; found '$findHighlight'."
        }
        if ([string] $findHighlightNode.Background.Type -cne 'CT_RAW' -or -not (Test-RawColor $findHighlight)) {
            Add-Failure "[$themeName] Find highlight must use an eight-digit CT_RAW background; found '$([string] $findHighlightNode.Background.Type)/$findHighlight'."
        }
        if ([string] $findHighlightNode.Foreground.Type -cne 'CT_RAW' -or
            [string] $findHighlightNode.Foreground.Source -cne [string] $markerPolicy.FindBorder) {
            Add-Failure "[$themeName] Find highlight must use marker outline '$($markerPolicy.FindBorder)'; found '$([string] $findHighlightNode.Foreground.Type)/$([string] $findHighlightNode.Foreground.Source)'."
        }
        if ($referenceHighlight -cne $expectedReferenceHighlight) {
            Add-Failure "[$themeName] Reference highlight must use approved source '$expectedReferenceHighlight'; found '$referenceHighlight'."
        }

        $markerGroups = @(
            @{ Name = 'definition'; Roles = @($rolePolicy.MarkerHighlightRoles.Definition); Fill = [string] $markerPolicy.DefinitionFill; Border = [string] $markerPolicy.DefinitionBorder; Bordered = $true }
            @{ Name = 'reference'; Roles = @($rolePolicy.MarkerHighlightRoles.Reference); Fill = [string] $markerPolicy.ReferenceFill; Border = [string] $markerPolicy.ReferenceBorder; Bordered = $true }
            @{ Name = 'matched selection'; Roles = @($rolePolicy.MarkerHighlightRoles.Matched); Fill = [string] $markerPolicy.MatchedFill; Border = '00000000'; Bordered = $false }
            @{ Name = 'scope'; Roles = @($rolePolicy.MarkerHighlightRoles.Scope); Fill = [string] $markerPolicy.ScopeFill; Border = '00000000'; Bordered = $false }
            @{ Name = 'expression hover'; Roles = @($rolePolicy.MarkerHighlightRoles.Expression); Fill = [string] $markerPolicy.ExpressionFill; Border = [string] $markerPolicy.ExpressionBorder; Bordered = $true }
        )
        foreach ($group in $markerGroups) {
            foreach ($role in $group.Roles) {
                $node = Get-ColorNode -Xml $xml -Category 'Text Editor MEF Items' -Color ([string] $role)
                if ($null -eq $node) { continue }
                $roleBackground = [string] $node.Background.Source
                if ([string] $node.Background.Type -cne 'CT_RAW' -or -not (Test-RawColor $roleBackground)) {
                    Add-Failure "[$themeName] $($group.Name) marker Text Editor MEF Items/$role must use an eight-digit CT_RAW fill; found '$([string] $node.Background.Type)/$roleBackground'."
                    continue
                }
                if ($roleBackground -cne [string] $group.Fill) {
                    Add-Failure "[$themeName] $($group.Name) marker Text Editor MEF Items/$role must use fill '$($group.Fill)'; found '$roleBackground'."
                }
                if ($group.Bordered) {
                    if ([string] $node.Foreground.Type -cne 'CT_RAW' -or
                        [string] $node.Foreground.Source -cne [string] $group.Border) {
                        Add-Failure "[$themeName] $($group.Name) marker Text Editor MEF Items/$role must use outline '$($group.Border)'; found '$([string] $node.Foreground.Type)/$([string] $node.Foreground.Source)'."
                    }
                    elseif ((Test-RawColor $editorBackground) -and
                        $editorBackground.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
                        $effectiveRoleBackground = Get-CompositedSource -Foreground $roleBackground -Background $editorBackground
                        $script:MarkerOutlineRoleCount++
                        Test-Contrast -Theme $themeName -Role "Text Editor MEF Items/$role marker outline against editor" -Foreground ([string] $group.Border) -Background $editorBackground -Minimum 3.0
                        Test-Contrast -Theme $themeName -Role "Text Editor MEF Items/$role marker outline against fill" -Foreground ([string] $group.Border) -Background $effectiveRoleBackground -Minimum 3.0
                    }
                }
                elseif ([string] $node.Foreground.Type -cne 'CT_INVALID' -or
                    [string] $node.Foreground.Source -cne '00000000') {
                    Add-Failure "[$themeName] $($group.Name) marker Text Editor MEF Items/$role must remain borderless with CT_INVALID/00000000."
                }
                if ((Test-RawColor $editorBackground) -and
                    $editorBackground.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
                    $markerHighlightSurfaces.Add([pscustomobject]@{
                        Name = "$($group.Name) marker/$role"
                        Source = Get-CompositedSource -Foreground $roleBackground -Background $editorBackground
                    })
                }
            }
        }
        $script:MarkerSemanticThemeCount++

        if ([string] $markerPolicy.DefinitionFill -ceq [string] $markerPolicy.ReferenceFill -or
            [string] $markerPolicy.MatchedFill -ceq [string] $markerPolicy.ReferenceFill -or
            [string] $markerPolicy.ScopeFill -ceq [string] $markerPolicy.ReferenceFill -or
            [string] $markerPolicy.ExpressionFill -ceq [string] $markerPolicy.ReferenceFill) {
            Add-Failure "[$themeName] Definition, reference, matched-selection, scope, and expression-hover marker fills must remain semantically distinct."
        }

        if ((Test-RawColor $findHighlight) -and (Test-RawColor $referenceHighlight) -and
            (Test-RawColor $editorBackground) -and
            $editorBackground.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            $effectiveFindHighlight = Get-CompositedSource -Foreground $findHighlight -Background $editorBackground
            $effectiveReferenceHighlight = Get-CompositedSource -Foreground $referenceHighlight -Background $editorBackground
            $script:MarkerOutlineRoleCount++
            Test-Contrast -Theme $themeName -Role 'Text Editor MEF Items/MarkerFormatDefinition/FindHighlight marker outline against editor' -Foreground ([string] $markerPolicy.FindBorder) -Background $editorBackground -Minimum 3.0
            Test-Contrast -Theme $themeName -Role 'Text Editor MEF Items/MarkerFormatDefinition/FindHighlight marker outline against fill' -Foreground ([string] $markerPolicy.FindBorder) -Background $effectiveFindHighlight -Minimum 3.0
            $findDistance = Get-OkLabDistance -First $editorBackground -Second $effectiveFindHighlight
            $referenceDistance = Get-OkLabDistance -First $editorBackground -Second $effectiveReferenceHighlight
            if (($findDistance + 0.000001) -lt 0.06) {
                Add-Failure "[$themeName] Effective outlined Find fill OKLab distance is $([Math]::Round($findDistance, 5)); minimum is 0.06."
            }
            if (($referenceDistance + 0.000001) -lt 0.04) {
                Add-Failure "[$themeName] Effective outlined reference fill OKLab distance is $([Math]::Round($referenceDistance, 5)); minimum is 0.04."
            }
            if ((($findDistance - $referenceDistance) + 0.000001) -lt 0.01) {
                Add-Failure "[$themeName] Outlined Find fill must be at least 0.01 stronger than outlined reference fill; measured delta is $([Math]::Round($findDistance - $referenceDistance, 5))."
            }
        }
    }

    $currentLineNode = Get-ColorNode -Xml $xml -Category 'Text Editor MEF Items' -Color 'CurrentLineActiveFormat'
    $currentLineBackground = if ($null -ne $currentLineNode) { [string] $currentLineNode.Background.Source } else { $null }
    $effectiveCurrentLine = $null
    if ($rolePolicy.CurrentLineAnchors.ContainsKey($themeName) -and
        $currentLineBackground -cne [string] $rolePolicy.CurrentLineAnchors[$themeName]) {
        Add-Failure "[$themeName] Current line must use approved source '$($rolePolicy.CurrentLineAnchors[$themeName])'; found '$currentLineBackground'."
    }
    if ($null -ne $currentLineBackground -and (Test-RawColor $currentLineBackground) -and
        (Test-RawColor $editorBackground) -and $editorBackground.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        $effectiveCurrentLine = if ($currentLineBackground.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            $currentLineBackground
        }
        else {
            Get-CompositedSource -Foreground $currentLineBackground -Background $editorBackground
        }
        $currentLineDistance = Get-OkLabDistance -First $editorBackground -Second $effectiveCurrentLine
        if (($currentLineDistance + 0.000001) -lt 0.06) {
            Add-Failure "[$themeName] Current-line OKLab distance is $([Math]::Round($currentLineDistance, 5)); minimum is 0.06."
        }
        if ($null -ne $effectiveInactiveSelection) {
            $inactiveSelectionDistance = Get-OkLabDistance -First $editorBackground -Second $effectiveInactiveSelection
            if ($themeName -cne 'Amberroot' -and ($currentLineDistance - 0.000001) -gt $inactiveSelectionDistance) {
                Add-Failure "[$themeName] Current line must not be stronger than inactive selection; measured $([Math]::Round($currentLineDistance, 5)) versus $([Math]::Round($inactiveSelectionDistance, 5))."
            }
        }
    }

    $effectiveActiveSelection = $null
    if ($null -ne $editorSelectionBackground -and (Test-RawColor $editorSelectionBackground) -and
        (Test-RawColor $editorBackground) -and $editorBackground.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        try { $effectiveActiveSelection = Get-NormalSelectionBackground -Source $editorSelectionBackground -Underlay $editorBackground }
        catch { Add-Failure "[$themeName] Selection model: $($_.Exception.Message)" }
    }
    # Selected Text.Foreground is not painted by this consumer. Former raw-fill
    # foreground and Nullsector prominence checks are retained in the selection
    # diagnostics; rendered per-theme bounds replace their enforcement.

    $syntaxSurfaces = @(
        [pscustomobject]@{ Name = 'Find highlight'; Source = $effectiveFindHighlight },
        [pscustomobject]@{ Name = 'current line'; Source = $effectiveCurrentLine }
    )
    foreach ($markerSurface in $markerHighlightSurfaces) {
        $syntaxSurfaces += $markerSurface
    }
    foreach ($entry in $rolePolicy.EditorSyntaxFamilies) {
        $node = Get-ColorNode -Xml $xml -Category ([string] $entry.Category) -Color ([string] $entry.Role)
        if ($null -eq $node -or [string] $node.Foreground.Type -cne 'CT_RAW') { continue }
        $foregroundSource = [string] $node.Foreground.Source
        if (-not (Test-RawColor $foregroundSource) -or
            -not $foregroundSource.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        foreach ($surface in $syntaxSurfaces) {
            if ([string]::IsNullOrWhiteSpace([string] $surface.Source)) { continue }
            if ($surface.Name -ceq 'current line') {
                $script:CurrentLineSyntaxPairCount++
            }
            else {
                $script:HighlightSyntaxPairCount++
            }
            Test-Contrast -Theme $themeName -Role "$($entry.Category)/$($entry.Role) inside $($surface.Name) [$($entry.Classification)]" -Foreground $foregroundSource -Background ([string] $surface.Source) -Minimum 4.5
        }
    }

    foreach ($entry in @($rolePolicy.ContextualEditorOverlays | Where-Object Theme -ceq $themeName)) {
        $node = Get-ColorNode -Xml $xml -Category 'Text Editor MEF Items' -Color ([string] $entry.Role)
        if ($null -eq $node) { continue }

        $foregroundSource = [string] $node.Foreground.Source
        $backgroundSource = [string] $node.Background.Source
        if ([string] $node.Foreground.Type -cne 'CT_RAW' -or
            -not (Test-RawColor $foregroundSource) -or
            -not $foregroundSource.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "[$themeName] Contextual editor overlay $($entry.Role) requires an opaque CT_RAW foreground; found '$([string] $node.Foreground.Type)/$foregroundSource'."
            continue
        }
        if ([string] $node.Background.Type -cne 'CT_RAW' -or $backgroundSource -cne [string] $entry.Background) {
            Add-Failure "[$themeName] Contextual editor overlay $($entry.Role) must use approved background '$($entry.Background)'; found '$([string] $node.Background.Type)/$backgroundSource'."
            continue
        }

        $effectiveOverlay = Get-CompositedSource -Foreground $backgroundSource -Background $editorBackground
        $script:ContextualEditorOverlayPairCount++
        Test-Contrast -Theme $themeName -Role "Contextual editor overlay/$($entry.Role) [normal text]" -Foreground $foregroundSource -Background $effectiveOverlay -Minimum ([double] $entry.Minimum)
    }

    if (-not $rolePolicy.CoreSyntaxThemeAnchors.ContainsKey($themeName)) {
        Add-Failure "[$themeName] No core semantic-syntax palette is registered."
    }
    else {
        $themeSyntaxAnchors = $rolePolicy.CoreSyntaxThemeAnchors[$themeName]
        $observedSyntaxAnchors = @{}
        foreach ($familyName in @($rolePolicy.CoreSyntaxFamilyRoles.Keys | Sort-Object)) {
            if (-not $themeSyntaxAnchors.ContainsKey($familyName)) {
                Add-Failure "[$themeName] Core semantic-syntax family '$familyName' has no declared theme anchor."
                continue
            }
            $expectedSource = ([string] $themeSyntaxAnchors[$familyName]).ToUpperInvariant()
            if (-not (Test-RawColor $expectedSource) -or
                -not $expectedSource.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
                Add-Failure "[$themeName] Core semantic-syntax family '$familyName' has invalid opaque anchor '$expectedSource'."
                continue
            }
            $observedSyntaxAnchors[$familyName] = $expectedSource

            foreach ($entry in @($rolePolicy.CoreSyntaxFamilyRoles[$familyName])) {
                if ([string]::IsNullOrWhiteSpace([string] $entry.Category) -or
                    [string]::IsNullOrWhiteSpace([string] $entry.Role)) {
                    Add-Failure "[$themeName] Core semantic-syntax family '$familyName' contains a malformed role registry entry."
                    continue
                }
                $node = Get-ColorNode -Xml $xml -Category ([string] $entry.Category) -Color ([string] $entry.Role)
                if ($null -eq $node) { continue }
                $source = ([string] $node.Foreground.Source).ToUpperInvariant()
                $type = [string] $node.Foreground.Type
                if ($type -cne 'CT_RAW' -or $source -cne $expectedSource) {
                    Add-Failure "[$themeName] Core semantic-syntax $familyName role $($entry.Category)/$($entry.Role) must use opaque anchor '$expectedSource'; found '$type/$source'."
                }
                $script:CoreSyntaxRoleCount++
            }

            $coreSurfaces = @(
                [pscustomobject]@{ Name = 'editor'; Source = $editorBackground },
                [pscustomobject]@{ Name = 'inactive selection'; Source = $effectiveInactiveSelection }
            ) + $syntaxSurfaces
            if ($familyName -in @('Struct','Interface','Control','Directive')) {
                # The new all-theme foregrounds must also preserve syntax in
                # active selections. Other deferred-theme remediation remains scoped.
                $activeSurface = Get-ColorNode -Xml $xml -Category 'Text Editor Text Manager Items' -Color 'Selected Text'
                $coreSurfaces += [pscustomobject]@{ Name='active selection'; Source=$effectiveActiveSelection }
            }
            foreach ($surface in $coreSurfaces) {
                if ([string]::IsNullOrWhiteSpace([string] $surface.Source)) { continue }
                $script:CoreSyntaxSurfacePairCount++
                Test-Contrast -Theme $themeName -Role "Core semantic-syntax/$familyName inside $($surface.Name)" -Foreground $expectedSource -Background ([string] $surface.Source) -Minimum 4.5
            }
        }

        if (@($rolePolicy.CoreSyntaxTypeCoupledMarkupThemes) -ccontains $themeName) {
            $expectedTypeSource = ([string] $themeSyntaxAnchors.Type).ToUpperInvariant()
            foreach ($entry in @($rolePolicy.CoreSyntaxTypeCoupledMarkupRoles)) {
                $node = Get-ColorNode -Xml $xml -Category ([string] $entry.Category) -Color ([string] $entry.Role)
                if ($null -eq $node) { continue }
                $source = ([string] $node.Foreground.Source).ToUpperInvariant()
                $type = [string] $node.Foreground.Type
                if ($type -cne 'CT_RAW' -or $source -cne $expectedTypeSource) {
                    Add-Failure "[$themeName] Type-coupled markup role $($entry.Category)/$($entry.Role) must use opaque type anchor '$expectedTypeSource'; found '$type/$source'."
                }
            }
        }

        $familyNames = @($observedSyntaxAnchors.Keys | Sort-Object)
        for ($firstIndex = 0; $firstIndex -lt $familyNames.Count; $firstIndex++) {
            for ($secondIndex = $firstIndex + 1; $secondIndex -lt $familyNames.Count; $secondIndex++) {
                $firstName = [string] $familyNames[$firstIndex]
                $secondName = [string] $familyNames[$secondIndex]
                $firstSource = [string] $observedSyntaxAnchors[$firstName]
                $secondSource = [string] $observedSyntaxAnchors[$secondName]
                $distance = Get-OkLabDistance -First $firstSource -Second $secondSource
                $allowExactAlias = $false
                foreach ($allowed in @($rolePolicy.CoreSyntaxExactAliasAllowlist)) {
                    if (([string] $allowed.First -ceq $firstName -and [string] $allowed.Second -ceq $secondName) -or
                        ([string] $allowed.First -ceq $secondName -and [string] $allowed.Second -ceq $firstName)) {
                        $allowExactAlias = $true
                        break
                    }
                }
                $script:CoreSyntaxDistancePairCount++
                if ($allowExactAlias) { continue }
                if ($distance -lt 0.000001) {
                    Add-Failure "[$themeName] Core semantic-syntax families '$firstName' and '$secondName' collide exactly at '$firstSource'."
                    continue
                }
                if (($distance + 0.000001) -lt [double] $rolePolicy.CoreSyntaxDistanceMinimum) {
                    Add-Failure "[$themeName] Core semantic-syntax '$firstName'-to-'$secondName' OKLab distance is $([Math]::Round($distance, 5)); minimum is $($rolePolicy.CoreSyntaxDistanceMinimum) ('$firstSource' to '$secondSource')."
                }
                elseif (($distance + 0.000001) -lt [double] $rolePolicy.CoreSyntaxDistanceAdvisory) {
                    $script:CoreSyntaxAdvisoryCount++
                    Add-Advisory -Theme $themeName -Kind 'semantic syntax proximity' -Role "$firstName/$secondName" -Message "OKLab distance $([Math]::Round($distance, 5)) passes the 0.06 floor but is below the 0.08 advisory target."
                }
            }
        }
    }

    if ($themeName -ceq 'Hardline') {
        foreach ($role in $rolePolicy.HardlineNeutralSeparators) {
            $source = Get-ComponentSource $xml 'Environment' ([string] $role)
            if ($source -cne 'FF42484B') {
                Add-Failure "[$themeName] Neutral separator Environment/$role must use quiet steel 'FF42484B'; found '$source'."
            }
            $script:NeutralSeparatorRoleCount++
        }
        foreach ($role in $rolePolicy.HardlineStrongNeutralBorders) {
            $source = Get-ComponentSource $xml 'Environment' ([string] $role)
            if ($source -cne 'FF697277') {
                Add-Failure "[$themeName] Meaningful border Environment/$role must retain strong steel 'FF697277'; found '$source'."
            }
        }

        $debuggingStatus = Get-ComponentSource $xml 'ShellInternal' 'StatusBarBackgroundFillDebugging'
        if ($debuggingStatus -cne 'FF6B62D9') {
            Add-Failure "[$themeName] Debugging status must retain the intentional functional purple 'FF6B62D9'; found '$debuggingStatus'."
        }
    }

    $variableSource = $null
    $observedVariableSource = $null
    if (-not $semanticVariableAnchors.Contains($themeName)) {
        Add-Failure "[$themeName] No semantic-variable palette anchor is registered."
    }
    else {
        $variableSource = [string] $semanticVariableAnchors[$themeName]
        $script:SemanticVariableThemeCount++
        foreach ($role in $semanticVariableRoles) {
            $node = Get-ColorNode -Xml $xml -Category 'Text Editor MEF Items' -Color $role
            if ($null -eq $node) { continue }

            $foregroundType = [string] $node.Foreground.Type
            $foregroundSource = [string] $node.Foreground.Source
            if ($null -eq $observedVariableSource -and (Test-RawColor $foregroundSource)) {
                $observedVariableSource = $foregroundSource
            }
            if ($foregroundType -cne 'CT_RAW') {
                Add-Failure "[$themeName] Semantic variable Text Editor MEF Items/$role/Foreground must use CT_RAW; found '$foregroundType'."
            }
            if ($foregroundSource -cne $variableSource) {
                Add-Failure "[$themeName] Semantic variable Text Editor MEF Items/$role/Foreground must use theme anchor '$variableSource'; found '$foregroundSource'."
            }
            if (-not $foregroundSource.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
                Add-Failure "[$themeName] Semantic variable Text Editor MEF Items/$role/Foreground must be opaque; found '$foregroundSource'."
            }
            if ([string] $node.Background.Type -cne 'CT_INVALID' -or [string] $node.Background.Source -cne '00000000') {
                Add-Failure "[$themeName] Semantic variable Text Editor MEF Items/$role must inherit its background with CT_INVALID/00000000."
            }
        }

        foreach ($role in $inheritedMemberRoles) {
            $node = Get-ColorNode -Xml $xml -Category 'Text Editor MEF Items' -Color $role
            if ($null -ne $node -and [string] $node.Foreground.Type -cne 'CT_INVALID') {
                Add-Failure "[$themeName] Semantic member Text Editor MEF Items/$role must retain inherited neutral foreground semantics with CT_INVALID; found '$([string] $node.Foreground.Type)'."
            }
        }

        $variableEvaluationSource = if ($null -ne $observedVariableSource) {
            $observedVariableSource
        }
        else {
            $variableSource
        }

        if ($null -ne $editorBackground) {
            Test-Contrast -Theme $themeName -Role 'Semantic variables/editor background [normal text]' -Foreground $variableEvaluationSource -Background $editorBackground -Minimum 4.5
        }
        if ($null -ne $editorSelectionBackground) {
            Test-Contrast -Theme $themeName -Role 'Semantic variables/active selection [normal text]' -Foreground $variableEvaluationSource -Background $effectiveActiveSelection -Minimum 4.5
        }
        if ($null -ne $effectiveInactiveSelection) {
            Test-Contrast -Theme $themeName -Role 'Semantic variables/inactive selection [normal text]' -Foreground $variableEvaluationSource -Background $effectiveInactiveSelection -Minimum 4.5
        }

        if ($null -ne $editorForeground -and (Test-RawColor $editorForeground)) {
            $plainDistance = Get-OkLabDistance -First $variableEvaluationSource -Second $editorForeground
            if (($plainDistance + 0.000001) -lt 0.08) {
                Add-Failure "[$themeName] Semantic-variable-to-plain-text OKLab distance is $([Math]::Round($plainDistance, 5)); minimum is 0.08 ('$variableEvaluationSource' to '$editorForeground')."
            }
        }

        foreach ($comparison in @(
            [pscustomobject]@{ Category = 'Text Editor Language Service Items'; Color = 'Keyword'; Label = 'keyword' },
            [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'method name'; Label = 'method' },
            [pscustomobject]@{ Category = 'Text Editor MEF Items'; Color = 'class name'; Label = 'type' }
        )) {
            $comparisonSource = Get-ComponentSource $xml $comparison.Category $comparison.Color 'Foreground'
            if ($null -ne $comparisonSource -and (Test-RawColor $comparisonSource)) {
                $semanticDistance = Get-OkLabDistance -First $variableEvaluationSource -Second $comparisonSource
                if (($semanticDistance + 0.000001) -lt 0.06) {
                    Add-Failure "[$themeName] Semantic-variable-to-$($comparison.Label) OKLab distance is $([Math]::Round($semanticDistance, 5)); minimum is 0.06 ('$variableEvaluationSource' to '$comparisonSource')."
                }
            }
        }
    }

    foreach ($role in $cssDistinctRoles) {
        $source = Get-ComponentSource $xml 'Text Editor MEF Items' $role 'Foreground'
        if ($null -ne $source -and $null -ne $editorBackground) {
            Test-Contrast -Theme $themeName -Role "CSS/$role [normal text]" -Foreground $source -Background $editorBackground -Minimum 4.5
        }
    }

    $panelTitleBar = Get-ComponentSource $xml 'Environment' 'PanelTitleBar'
    $solidBackgroundTertiary = Get-ComponentSource $xml 'Shell' 'SolidBackgroundFillTertiary'
    if ($null -ne $panelTitleBar -and $null -ne $solidBackgroundTertiary -and $panelTitleBar -cne $solidBackgroundTertiary) {
        Add-Failure "[$themeName] Environment/PanelTitleBar must match Shell/SolidBackgroundFillTertiary '$solidBackgroundTertiary'; found '$panelTitleBar'."
    }

    $legacyToolWindowHeaderRoles = @(
        'TitleBarActive',
        'TitleBarActiveBorder',
        'TitleBarActiveGradientBegin',
        'TitleBarActiveGradientEnd',
        'TitleBarActiveGradientMiddle1',
        'TitleBarActiveGradientMiddle2',
        'TitleBarInactive',
        'TitleBarInactiveGradientBegin',
        'TitleBarInactiveGradientEnd'
    )
    foreach ($role in $legacyToolWindowHeaderRoles) {
        $source = Get-ComponentSource $xml 'Environment' $role
        if ($null -ne $source -and $null -ne $panelTitleBar -and $source -cne $panelTitleBar) {
            Add-Failure "[$themeName] Environment/$role must match Environment/PanelTitleBar '$panelTitleBar'; found '$source'."
        }
    }

    foreach ($role in @('EnvironmentHeader', 'EnvironmentHeaderInactive')) {
        $source = Get-ComponentSource $xml 'ShellInternal' $role
        if ($null -ne $source -and $null -ne $solidBackgroundTertiary -and $source -cne $solidBackgroundTertiary) {
            Add-Failure "[$themeName] ShellInternal/$role must match Shell/SolidBackgroundFillTertiary '$solidBackgroundTertiary'; found '$source'."
        }
    }

    $solidBackgroundBase = Get-ComponentSource $xml 'Shell' 'SolidBackgroundFillBase'
    foreach ($role in @('EnvironmentBackground', 'EnvironmentBody')) {
        $source = Get-ComponentSource $xml 'ShellInternal' $role
        if ($null -ne $source -and $null -ne $solidBackgroundBase -and $source -cne $solidBackgroundBase) {
            Add-Failure "[$themeName] ShellInternal/$role must match Shell/SolidBackgroundFillBase '$solidBackgroundBase'; found '$source'."
        }
    }

    foreach ($role in @(
        'EnvironmentBackground',
        'EnvironmentBackgroundGradientBegin',
        'EnvironmentBackgroundGradientEnd',
        'EnvironmentBackgroundGradientMiddle1',
        'EnvironmentBackgroundGradientMiddle2',
        'EnvironmentBackgroundTexture1',
        'EnvironmentBackgroundTexture2'
    )) {
        $source = Get-ComponentSource $xml 'Environment' $role
        if ($null -ne $source -and $null -ne $solidBackgroundBase -and $source -cne $solidBackgroundBase) {
            Add-Failure "[$themeName] Environment/$role must match Shell/SolidBackgroundFillBase '$solidBackgroundBase'; found '$source'."
        }
    }

    $secondaryText = Get-ComponentSource $xml 'Shell' 'TextFillSecondary'
    $solutionNameActiveBackground = Get-ComponentSource $xml 'Environment' 'MainWindowSolutionNameActiveBackground'
    $solutionNameInactiveBackground = Get-ComponentSource $xml 'Environment' 'MainWindowSolutionNameInactiveBackground'
    $solutionNameActiveText = Get-ComponentSource $xml 'Environment' 'MainWindowSolutionNameActiveText'
    $solutionNameInactiveText = Get-ComponentSource $xml 'Environment' 'MainWindowSolutionNameInactiveText'
    $expectedSolutionNameActive = if ($null -ne $primaryText -and (Test-RawColor $primaryText)) {
        '0F' + $primaryText.Substring(2)
    }
    else {
        $null
    }
    if ($null -ne $expectedSolutionNameActive -and $solutionNameActiveBackground -cne $expectedSolutionNameActive) {
        Add-Failure "[$themeName] Active solution-name background must use the 0x0F primary-text neutral lift '$expectedSolutionNameActive'; found '$solutionNameActiveBackground'."
    }
    if ($null -ne $solidBackgroundBase -and $solutionNameInactiveBackground -cne $solidBackgroundBase) {
        Add-Failure "[$themeName] Inactive solution-name background must match Shell/SolidBackgroundFillBase '$solidBackgroundBase'; found '$solutionNameInactiveBackground'."
    }
    if ($null -ne $primaryText -and $solutionNameActiveText -cne $primaryText) {
        Add-Failure "[$themeName] Active solution-name text must retain Shell/TextFillPrimary '$primaryText'; found '$solutionNameActiveText'."
    }
    if ($null -ne $secondaryText -and $solutionNameInactiveText -cne $secondaryText) {
        Add-Failure "[$themeName] Inactive solution-name text must retain Shell/TextFillSecondary '$secondaryText'; found '$solutionNameInactiveText'."
    }
    if ($null -ne $solutionNameActiveBackground -and $null -ne $solidBackgroundBase -and
        (Test-RawColor $solutionNameActiveBackground) -and (Test-RawColor $solidBackgroundBase) -and
        $solidBackgroundBase.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        if (-not $solutionNameActiveBackground.StartsWith('0F', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "[$themeName] Active solution-name background must remain a low-alpha neutral lift; found '$solutionNameActiveBackground'."
        }
        $effectiveSolutionNameActive = Get-CompositedSource -Foreground $solutionNameActiveBackground -Background $solidBackgroundBase
        Test-Contrast -Theme $themeName -Role 'Environment/MainWindowSolutionNameActiveText [normal text]' -Foreground $solutionNameActiveText -Background $effectiveSolutionNameActive -Minimum 4.5
        Test-Contrast -Theme $themeName -Role 'Environment/MainWindowSolutionNameInactiveText [inactive text]' -Foreground $solutionNameInactiveText -Background $solidBackgroundBase -Minimum 4.5
        $script:SolutionTitleThemeCount++
    }

    $solidBackgroundSecondary = Get-ComponentSource $xml 'Shell' 'SolidBackgroundFillSecondary'
    $environmentTab = Get-ComponentSource $xml 'ShellInternal' 'EnvironmentTab'
    $layeredNode = Get-ColorNode -Xml $xml -Category 'ShellInternal' -Color 'EnvironmentLayeredBackground'
    $layeredBackground = if ($null -ne $layeredNode -and $null -ne $layeredNode.Background) {
        [string] $layeredNode.Background.Source
    }
    else {
        $null
    }
    if ($null -ne $layeredNode -and $null -ne $layeredNode.Background -and
        [string] $layeredNode.Background.Type -cne 'CT_RAW') {
        Add-Failure "[$themeName] ShellInternal/EnvironmentLayeredBackground must use CT_RAW; found '$($layeredNode.Background.Type)'."
    }
    if ($null -ne $layeredBackground -and -not $layeredBackground.StartsWith('4D', [StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure "[$themeName] ShellInternal/EnvironmentLayeredBackground must use a 30% translucent layered surface with 0x4D alpha; found '$layeredBackground'."
    }
    if ($documentLayerSources.ContainsKey($themeName) -and
        $null -ne $layeredBackground -and
        $layeredBackground -cne $documentLayerSources[$themeName]) {
        Add-Failure "[$themeName] ShellInternal/EnvironmentLayeredBackground must use the palette-derived source '$($documentLayerSources[$themeName])'; found '$layeredBackground'."
    }
    if ($null -ne $layeredBackground -and $null -ne $solidBackgroundBase -and
        $null -ne $solidBackgroundSecondary -and $null -ne $environmentTab -and
        (Test-RawColor $layeredBackground) -and (Test-RawColor $solidBackgroundBase) -and
        $solidBackgroundBase.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        $effectiveDocumentLayer = Get-CompositedSource -Foreground $layeredBackground -Background $solidBackgroundBase
        if ($effectiveDocumentLayer -cne $solidBackgroundSecondary) {
            Add-Failure "[$themeName] Composited ShellInternal/EnvironmentLayeredBackground '$effectiveDocumentLayer' must match Shell/SolidBackgroundFillSecondary '$solidBackgroundSecondary'."
        }
        if ($effectiveDocumentLayer -cne $environmentTab) {
            Add-Failure "[$themeName] Composited ShellInternal/EnvironmentLayeredBackground '$effectiveDocumentLayer' must match ShellInternal/EnvironmentTab '$environmentTab'."
        }

        $baseLab = ConvertTo-OkLab $solidBackgroundBase
        $layerLab = ConvertTo-OkLab $effectiveDocumentLayer
        if (($layerLab[0] - $baseLab[0]) -le 0.000001) {
            Add-Failure "[$themeName] The effective document-tab layer '$effectiveDocumentLayer' must be perceptually lighter than the shell base '$solidBackgroundBase'."
        }
        $layerDistance = Get-OkLabDistance -First $solidBackgroundBase -Second $effectiveDocumentLayer
        if (($layerDistance + 0.000001) -lt 0.02) {
            Add-Failure "[$themeName] Document-tab layer OKLab distance is $([Math]::Round($layerDistance, 5)); minimum is 0.02 ('$solidBackgroundBase' to '$effectiveDocumentLayer')."
        }
        $script:DocumentLayerThemeCount++
    }

    # VS 2026 SolutionInfoControl uses EnvironmentBadge, not the legacy
    # MainWindowSolutionName* backgrounds. VsToolBar uses EnvironmentLayeredBackground;
    # both installed templates use EnvironmentLayeredBorder for the frame.
    $badgeNode = Get-ColorNode -Xml $xml -Category 'ShellInternal' -Color 'EnvironmentBadge'
    $badgeBackground = Get-ComponentSource $xml 'ShellInternal' 'EnvironmentBadge'
    $badgeBorderNode = Get-ColorNode -Xml $xml -Category 'ShellInternal' -Color 'EnvironmentLayeredBorder'
    if ($null -eq $badgeNode -or $null -eq $badgeNode.Background -or
        [string] $badgeNode.Background.Type -cne 'CT_RAW') {
        Add-Failure "[$themeName] Modern solution-name badge must use an explicit CT_RAW background."
    }
    if ($null -eq $badgeBorderNode -or $null -eq $badgeBorderNode.Background -or
        [string] $badgeBorderNode.Background.Type -cne 'CT_RAW') {
        Add-Failure "[$themeName] Shared solution-name/toolbar border must use explicit CT_RAW."
    }
    if ($null -eq $badgeBackground -or $badgeBackground -cne $layeredBackground) {
        Add-Failure "[$themeName] Modern solution-name badge must match the toolbar layered background '$layeredBackground'; found '$badgeBackground'."
    }
    if ((Test-RawColor $badgeBackground) -and (Test-RawColor $solidBackgroundBase) -and
        $solidBackgroundBase.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        $effectiveBadge = Get-CompositedSource -Foreground $badgeBackground -Background $solidBackgroundBase
        Test-Contrast -Theme $themeName -Role 'ShellInternal/EnvironmentBadge [solution-name text]' -Foreground $primaryText -Background $effectiveBadge -Minimum 4.5
        $script:ModernSolutionTitleThemeCount++
    }

    $statusBarRest = Get-ComponentSource $xml 'ShellInternal' 'StatusBarBackgroundFillRest'
    if ($null -ne $statusBarRest -and $statusBarRest -cne '4D000000') {
        Add-Failure "[$themeName] ShellInternal/StatusBarBackgroundFillRest must use the 30% black overlay '4D000000'; found '$statusBarRest'."
    }
    if ($null -ne $statusBarRest -and $null -ne $solidBackgroundBase -and
        (Test-RawColor $statusBarRest) -and (Test-RawColor $solidBackgroundBase) -and
        $solidBackgroundBase.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
        $effectiveStatusBarRest = Get-CompositedSource -Foreground $statusBarRest -Background $solidBackgroundBase
        $bodyLab = ConvertTo-OkLab $solidBackgroundBase
        $statusLab = ConvertTo-OkLab $effectiveStatusBarRest
        if (($bodyLab[0] - $statusLab[0]) -le 0.000001) {
            Add-Failure "[$themeName] The effective resting status bar '$effectiveStatusBarRest' must be perceptually darker than the shell body '$solidBackgroundBase'."
        }
    }

    $outputWindowBackground = Get-ComponentSource $xml 'Output Window' 'Plain Text'
    if ($null -ne $outputWindowBackground -and $null -ne $solidBackgroundTertiary -and
        $outputWindowBackground -cne $solidBackgroundTertiary) {
        Add-Failure "[$themeName] Output Window/Plain Text must match Shell/SolidBackgroundFillTertiary '$solidBackgroundTertiary'; found '$outputWindowBackground'."
    }

    if (-not $rolePolicy.ScrollbarStateAnchors.ContainsKey($themeName)) {
        Add-Failure "[$themeName] Scrollbar state policy is missing."
    }
    else {
        $scrollbarAnchors = $rolePolicy.ScrollbarStateAnchors[$themeName]
        $scrollbarTrack = Get-ComponentSource $xml 'Environment' 'ScrollBarBackground'
        $scrollbarRest = Get-ComponentSource $xml 'Environment' 'ScrollBarThumbBackground'
        $scrollbarHover = Get-ComponentSource $xml 'Environment' 'ScrollBarThumbMouseOverBackground'
        $scrollbarPressed = Get-ComponentSource $xml 'Environment' 'ScrollBarThumbPressedBackground'
        $scrollbarGlyph = Get-ComponentSource $xml 'Environment' 'ScrollBarThumbGlyph'
        foreach ($entry in @(
            [pscustomobject]@{ Role = 'ScrollBarBackground'; Actual = $scrollbarTrack; Expected = [string] $scrollbarAnchors.Track },
            [pscustomobject]@{ Role = 'ScrollBarThumbBackground'; Actual = $scrollbarRest; Expected = [string] $scrollbarAnchors.Rest },
            [pscustomobject]@{ Role = 'ScrollBarThumbMouseOverBackground'; Actual = $scrollbarHover; Expected = [string] $scrollbarAnchors.Hover },
            [pscustomobject]@{ Role = 'ScrollBarThumbPressedBackground'; Actual = $scrollbarPressed; Expected = [string] $scrollbarAnchors.Pressed },
            [pscustomobject]@{ Role = 'ScrollBarThumbGlyph'; Actual = $scrollbarGlyph; Expected = [string] $scrollbarAnchors.Glyph }
        )) {
            if ($entry.Actual -cne $entry.Expected) {
                Add-Failure "[$themeName] Environment/$($entry.Role) must use approved scrollbar source '$($entry.Expected)'; found '$($entry.Actual)'."
            }
            if (-not (Test-RawColor $entry.Actual) -or
                -not ([string] $entry.Actual).StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
                Add-Failure "[$themeName] Environment/$($entry.Role) must use an opaque eight-digit source; found '$($entry.Actual)'."
            }
        }

        if ((Test-RawColor $scrollbarTrack) -and (Test-RawColor $scrollbarRest) -and
            (Test-RawColor $scrollbarHover) -and (Test-RawColor $scrollbarPressed) -and
            $scrollbarTrack.StartsWith('FF', [StringComparison]::OrdinalIgnoreCase)) {
            $restRatio = Get-ContrastRatio -Foreground $scrollbarRest -Background $scrollbarTrack
            $hoverRatio = Get-ContrastRatio -Foreground $scrollbarHover -Background $scrollbarTrack
            $pressedRatio = Get-ContrastRatio -Foreground $scrollbarPressed -Background $scrollbarTrack
            $script:PairCount += 3
            if (($restRatio + 0.0001) -lt 3.0) {
                Add-Failure "[$themeName] Resting scrollbar thumb is $([Math]::Round($restRatio, 2)):1 against its track; required 3:1."
            }
            if (($hoverRatio + 0.0001) -lt 3.5) {
                Add-Failure "[$themeName] Hovered scrollbar thumb is $([Math]::Round($hoverRatio, 2)):1 against its track; required 3.5:1."
            }
            if (($pressedRatio + 0.0001) -lt 4.5) {
                Add-Failure "[$themeName] Pressed scrollbar thumb is $([Math]::Round($pressedRatio, 2)):1 against its track; required 4.5:1."
            }
            if (($hoverRatio - $restRatio) -le 0.0001 -or ($pressedRatio - $hoverRatio) -le 0.0001) {
                Add-Failure "[$themeName] Scrollbar contrast ordering must increase from rest to hover to pressed; measured $([Math]::Round($restRatio, 2)), $([Math]::Round($hoverRatio, 2)), and $([Math]::Round($pressedRatio, 2))."
            }
            $restHoverDistance = Get-OkLabDistance -First $scrollbarRest -Second $scrollbarHover
            $hoverPressedDistance = Get-OkLabDistance -First $scrollbarHover -Second $scrollbarPressed
            if (($restHoverDistance + 0.000001) -lt 0.03 -or
                ($hoverPressedDistance + 0.000001) -lt 0.03) {
                Add-Failure "[$themeName] Scrollbar states must remain perceptibly distinct; rest/hover is $([Math]::Round($restHoverDistance, 5)) and hover/pressed is $([Math]::Round($hoverPressedDistance, 5))."
            }
            Test-Contrast -Theme $themeName -Role 'Environment/ScrollBarThumbGlyph [meaningful glyph]' -Foreground $scrollbarGlyph -Background $scrollbarRest -Minimum 3.0
        }

        $scrollBarArrowBackground = Get-ComponentSource $xml 'Environment' 'ScrollBarArrowBackground'
        $scrollBarArrowDisabledBackground = Get-ComponentSource $xml 'Environment' 'ScrollBarArrowDisabledBackground'
        if ($null -ne $scrollBarArrowBackground -and $null -ne $scrollBarArrowDisabledBackground -and
            $scrollBarArrowDisabledBackground -cne $scrollBarArrowBackground) {
            Add-Failure "[$themeName] Environment/ScrollBarArrowDisabledBackground must match Environment/ScrollBarArrowBackground '$scrollBarArrowBackground'; found '$scrollBarArrowDisabledBackground'."
        }

        foreach ($state in @(
            [pscustomobject]@{ Glyph = 'ScrollBarArrowGlyph'; Background = 'ScrollBarArrowBackground'; Expected = [string] $scrollbarAnchors.ArrowRest; Label = 'normal'; Composite = $false },
            [pscustomobject]@{ Glyph = 'ScrollBarArrowGlyphMouseOver'; Background = 'ScrollBarArrowMouseOverBackground'; Expected = [string] $scrollbarAnchors.ArrowHover; Label = 'hover'; Composite = $true },
            [pscustomobject]@{ Glyph = 'ScrollBarArrowGlyphPressed'; Background = 'ScrollBarArrowPressedBackground'; Expected = [string] $scrollbarAnchors.ArrowPressed; Label = 'pressed'; Composite = $true }
        )) {
            $glyphSource = Get-ComponentSource $xml 'Environment' $state.Glyph
            $backgroundSource = Get-ComponentSource $xml 'Environment' $state.Background
            if ($glyphSource -cne $state.Expected) {
                Add-Failure "[$themeName] Environment/$($state.Glyph) must use approved scrollbar glyph source '$($state.Expected)'; found '$glyphSource'."
            }
            if ($null -eq $glyphSource -or $null -eq $backgroundSource) { continue }
            $effectiveArrowBackground = if ($state.Composite) {
                Get-CompositedSource -Foreground $backgroundSource -Background $scrollBarArrowBackground
            }
            else {
                $backgroundSource
            }
            Test-Contrast -Theme $themeName -Role "Environment/$($state.Glyph) [$($state.Label) meaningful glyph]" -Foreground $glyphSource -Background $effectiveArrowBackground -Minimum 3.0
        }

        $disabledArrowGlyph = Get-ComponentSource $xml 'Environment' 'ScrollBarArrowGlyphDisabled'
        if ($null -ne $disabledArrowGlyph -and $null -ne $scrollBarArrowDisabledBackground) {
            Test-Contrast -Theme $themeName -Role 'Environment/ScrollBarArrowGlyphDisabled [disabled meaningful glyph]' -Foreground $disabledArrowGlyph -Background $scrollBarArrowDisabledBackground -Minimum 3.0
        }
        $script:ScrollbarStateThemeCount++
    }

    $leftShelf = Get-ComponentSource $xml 'Cider' 'ToolWindowShelf'
    $leftListBackground = Get-ComponentSource $xml 'Cider' 'ListBackground'
    $leftListItem = Get-ComponentSource $xml 'Cider' 'ListItemTier2'
    $leftPage = Get-ComponentSource $xml 'CommonDocument' 'Page'
    if ($null -ne $leftShelf -and $null -ne $leftListBackground -and $leftShelf -cne $leftListBackground) {
        Add-Failure "[$themeName] Extension Manager left shelf roles Cider/ToolWindowShelf and Cider/ListBackground must match; found '$leftShelf' and '$leftListBackground'."
    }
    foreach ($anchor in @(
        [pscustomobject]@{ Category = 'Cider'; Color = 'ListItemTier2'; Source = $leftListItem },
        [pscustomobject]@{ Category = 'CommonDocument'; Color = 'Page'; Source = $leftPage }
    )) {
        if ($null -ne $anchor.Source -and $null -ne $solidBackgroundTertiary -and $anchor.Source -cne $solidBackgroundTertiary) {
            Add-Failure "[$themeName] Extension Manager left list anchor $($anchor.Category)/$($anchor.Color) must match Shell/SolidBackgroundFillTertiary '$solidBackgroundTertiary'; found '$($anchor.Source)'."
        }
    }
    if ($null -ne $leftShelf -and $null -ne $solidBackgroundTertiary -and
        (Test-RawColor $leftShelf) -and (Test-RawColor $solidBackgroundTertiary)) {
        $leftDistance = Get-OkLabDistance -First $leftShelf -Second $solidBackgroundTertiary
        $leftMaximum = if ($themeName -in @('Cosmora Blueshift', 'Cosmora Redshift', 'Cosmora Ultraviolet')) { 0.025 } else { 0.021 }
        if (($leftDistance - 0.000001) -gt $leftMaximum) {
            Add-Failure "[$themeName] Extension Manager left shelf-to-list OKLab distance is $([Math]::Round($leftDistance, 5)); maximum is $leftMaximum ('$leftShelf' to '$solidBackgroundTertiary')."
        }
    }

    $rightSummary = Get-ComponentSource $xml 'Cider' 'ToolWindow'
    $rightPageBackground = Get-ComponentSource $xml 'CommonDocument' 'PageBackground'
    $rightDetail = Get-ComponentSource $xml 'Shell' 'SolidBackgroundFillBase'
    if ($null -ne $rightSummary -and $null -ne $rightPageBackground -and $rightSummary -cne $rightPageBackground) {
        Add-Failure "[$themeName] Extension Manager right summary roles Cider/ToolWindow and CommonDocument/PageBackground must match; found '$rightSummary' and '$rightPageBackground'."
    }
    if ($null -ne $rightSummary -and $null -ne $rightDetail -and
        (Test-RawColor $rightSummary) -and (Test-RawColor $rightDetail)) {
        $rightDistance = Get-OkLabDistance -First $rightSummary -Second $rightDetail
        if (($rightDistance - 0.000001) -gt 0.0055) {
            Add-Failure "[$themeName] Extension Manager right summary-to-detail OKLab distance is $([Math]::Round($rightDistance, 5)); maximum is 0.0055 ('$rightSummary' to '$rightDetail')."
        }

        $rightSummaryLab = ConvertTo-OkLab $rightSummary
        $rightDetailLab = ConvertTo-OkLab $rightDetail
        if (($rightSummaryLab[0] - $rightDetailLab[0]) -gt 0.000001) {
            Add-Failure "[$themeName] Extension Manager right summary must not be lighter than its detail base ('$rightSummary' versus '$rightDetail')."
        }
    }

    if ($themeName -ceq 'Aquatoxic') {
        foreach ($anchor in $aquatoxicAnchors) {
            $source = Get-ComponentSource $xml $anchor.Category $anchor.Color $anchor.Component
            if ($null -ne $source -and $source -cne $anchor.Source) {
                Add-Failure "[$themeName] Aquatoxic palette anchor $($anchor.Category)/$($anchor.Color)/$($anchor.Component) must be '$($anchor.Source)'; found '$source'."
            }
        }
    }

    if ($themeName -ceq 'Amberroot') {
        foreach ($anchor in $amberrootAnchors) {
            $source = Get-ComponentSource $xml $anchor.Category $anchor.Color $anchor.Component
            if ($null -ne $source -and $source -cne $anchor.Source) {
                Add-Failure "[$themeName] Amberroot palette anchor $($anchor.Category)/$($anchor.Color)/$($anchor.Component) must be '$($anchor.Source)'; found '$source'."
            }
        }
    }

    if ($themeName -ceq 'Pinknoise') {
        foreach ($anchor in $pinknoiseAnchors) {
            $source = Get-ComponentSource $xml $anchor.Category $anchor.Color $anchor.Component
            if ($null -ne $source -and $source -cne $anchor.Source) {
                Add-Failure "[$themeName] Pinknoise palette anchor $($anchor.Category)/$($anchor.Color)/$($anchor.Component) must be '$($anchor.Source)'; found '$source'."
            }
        }
    }

    if ($themeName -ceq 'Nullsector') {
        foreach ($anchor in $nullsectorAnchors) {
            $source = Get-ComponentSource $xml $anchor.Category $anchor.Color $anchor.Component
            if ($null -ne $source -and $source -cne $anchor.Source) {
                Add-Failure "[$themeName] Nullsector palette anchor $($anchor.Category)/$($anchor.Color)/$($anchor.Component) must be '$($anchor.Source)'; found '$source'."
            }
        }
    }

    if ($themeName -ceq 'Silverphase') {
        foreach ($anchor in $silverphaseAnchors) {
            $source = Get-ComponentSource $xml $anchor.Category $anchor.Color $anchor.Component
            if ($null -ne $source -and $source -cne $anchor.Source) {
                Add-Failure "[$themeName] Silverphase palette anchor $($anchor.Category)/$($anchor.Color)/$($anchor.Component) must be '$($anchor.Source)'; found '$source'."
            }
        }
    }

    if ($themeName -ceq 'Hardline') {
        foreach ($anchor in $hardlineAnchors) {
            $source = Get-ComponentSource $xml $anchor.Category $anchor.Color $anchor.Component
            if ($null -ne $source -and $source -cne $anchor.Source) {
                Add-Failure "[$themeName] Hardline palette anchor $($anchor.Category)/$($anchor.Color)/$($anchor.Component) must be '$($anchor.Source)'; found '$source'."
            }
        }
    }

    if ($cosmoraVariantAnchors.ContainsKey($themeName)) {
        foreach ($anchor in $cosmoraVariantAnchors[$themeName]) {
            $source = Get-ComponentSource $xml 'Shell' $anchor.Color 'Background'
            if ($null -ne $source -and $source -cne $anchor.Source) {
                Add-Failure "[$themeName] Palette anchor Shell/$($anchor.Color)/Background must be '$($anchor.Source)'; found '$source'."
            }
        }
    }

    foreach ($linkRole in @('urlformat', 'NavigableSymbolFormat')) {
        $linkNode = Get-ColorNode -Xml $xml -Category 'Text Editor MEF Items' -Color $linkRole
        if ($null -ne $linkNode -and $linkNode.Foreground.Type -eq 'CT_RAW') {
            Test-Contrast -Theme $themeName -Role "Editor/$linkRole" -Foreground ([string] $linkNode.Foreground.Source) -Background $editorBackground -Minimum 4.5
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($FocusThemeFile) -and
    $null -ne $baseSignature -and $null -ne $focusedSignature -and
    $focusedSignature -cne $baseSignature) {
    Add-Failure "[$FocusThemeFile] Category/color/component structure differs from the untouched fixture themes."
}

$requiresCosmoraMapping = [string]::IsNullOrWhiteSpace($FocusThemeFile) -or $FocusThemeFile -like 'Cosmora*.vstheme'
if ($requiresCosmoraMapping -and $themesByFile.ContainsKey('Cosmora.vstheme')) {
    foreach ($shiftFile in @('CosmoraBlueshift.vstheme', 'CosmoraRedshift.vstheme', 'CosmoraUltraviolet.vstheme')) {
        if ($themesByFile.ContainsKey($shiftFile)) {
            Test-CosmoraMapping -Base $themesByFile['Cosmora.vstheme'] -Shift $themesByFile[$shiftFile]
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($AdvisoryReportPath)) {
    $reportDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($AdvisoryReportPath))
    if (-not (Test-Path -LiteralPath $reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    $script:Advisories |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $AdvisoryReportPath -Encoding UTF8
}

if (-not [string]::IsNullOrWhiteSpace($CoverageReportPath)) {
    $coverageDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($CoverageReportPath))
    [void][IO.Directory]::CreateDirectory($coverageDirectory)
    $renderingEvidence = $null
    if ($null -ne $renderingContext -and $renderingMetadataErrors.Count -eq 0) {
        $renderingEvidence = Get-RenderingEvidenceReport -Context $renderingContext -Inventory $componentInventory
    }
    [ordered]@{
        SchemaVersion = 2
        Scope = 'Legacy source measurements plus separate rendering evidence; specialized checks are additional. Neither source passes nor registry coverage imply runtime acceptance.'
        LegacyStatusMeaning = 'Existing collection/status names are retained. Normal editor selection uses the pinned composited model and records raw diagnostics separately; other consumers retain their calculations. Consult RenderingEvidence for confidence.'
        Relationships = @($contextualResults.ToArray()); EditorSurfaces = @($editorSurfaceResults.ToArray()); ComponentInventory = $componentInventory
        RenderingMetadataErrors = $renderingMetadataErrors; RenderingEvidence = $renderingEvidence
        PriorityRefinements = @($priorityRefinementResults.ToArray())
        DebuggerHighlights = @($debuggerHighlightResults.ToArray())
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $CoverageReportPath -Encoding UTF8
}

if ($script:Failures.Count -gt 0) {
    Write-Host "Theme contrast validation failed with $($script:Failures.Count) issue(s):" -ForegroundColor Red
    foreach ($failure in $script:Failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Theme contrast validation passed." -ForegroundColor Green
Write-Host "  Themes: $($themesByFile.Count)"
Write-Host "  Tested contrast pairs: $script:PairCount"
Write-Host "  Debugger highlights: $($debuggerHighlightResults.Count) source checks; runtime acceptance pending"
Write-Host "  Editor RGB surfaces: $($editorSurfaceResults.Count) fill/border/texture components validated with opaque rendering, syntax contrast, and brightness limits"
Write-Host "  Legacy contextual source checks: $(@($contextualResults | Where-Object Status -eq 'validated').Count) passed; $(@($contextualResults | Where-Object Status -eq 'unresolved').Count) unresolved measurements; these statuses do not establish rendering confidence"
if ($null -ne $renderingContext -and $renderingMetadataErrors.Count -eq 0) {
    $renderingRelationshipContracts = @($renderingContext.Registry.Contracts | Where-Object { $_.PSObject.Properties.Name -contains 'RelationshipId' })
    Write-Host "  Contextual rendering evidence: $(@($renderingRelationshipContracts | Where-Object Assessment -eq 'supported').Count) supported; $(@($renderingRelationshipContracts | Where-Object Assessment -eq 'mismatch').Count) mismatches; $(@($renderingRelationshipContracts | Where-Object Assessment -eq 'unresolved').Count) unresolved relationships; runtime acceptance remains pending"
    Write-Host "  Rendering metadata: $($renderingContext.Registry.Contracts.Count) contracts; $($renderingContext.Registry.RuleCoverage.Count) audit rules reconciled; explicit policy owns enforcement and pending requirements remain non-enforcing"
}
Write-Host "  Refinements: $(@($priorityRefinementResults | Where-Object Enforced).Count) source checks enforced; $(@($priorityRefinementResults | Where-Object { -not $_.Enforced -and $_.Status -ne 'passed' }).Count) non-enforcing historical diagnostics/investigations; runtime acceptance remains pending"
Write-Host "  Single-component policy pairs: $script:SingleComponentPairCount"
Write-Host "  Structure: 89 categories and 3,114 colors per theme"
Write-Host "  Editor hierarchy: Razor/HTML and CSS semantic roles remain distinct"
Write-Host "  Semantic variables: $script:SemanticVariableThemeCount theme palette(s), five synchronized C#/VB/C++ roles, contextual contrast, and OKLab separation validated"
Write-Host "  Editor selection: active/inactive separation and approved anchors validated; $script:InactiveSelectionPairCount enabled syntax pair(s) pass on composited normal-selection RGB (pinned 18.10 model; runtime pending)"
Write-Host "  Editor highlights: $script:HighlightSyntaxPairCount syntax/highlight pair(s) preserve 4.5:1 through Find, definition, reference, matched-selection, scope, and expression-hover surfaces"
Write-Host "  Marker semantics: $script:MarkerSemanticThemeCount theme family/families retain distinct, restrained outline-led fills; $script:MarkerOutlineRoleCount meaningful marker outline role(s) pass 3:1 against editor and fill"
Write-Host "  Current line: $script:CurrentLineSyntaxPairCount syntax/current-line pair(s) preserve 4.5:1 with bounded perceptual prominence"
Write-Host "  Legacy overlay source checks: $script:ContextualEditorOverlayPairCount statement/code-analysis pair(s) pass the existing alpha model; consumer semantics remain unresolved"
Write-Host "  Core semantic syntax: $script:CoreSyntaxRoleCount registered role(s), $script:CoreSyntaxSurfacePairCount composited surface pair(s), and $script:CoreSyntaxDistancePairCount unrelated family-distance relationship(s) validated; $script:CoreSyntaxAdvisoryCount proximity advisory finding(s)"
Write-Host "  Legacy content: enabled text, hyperlinks, glyphs, caption surfaces, and semantic borders follow the shared role policy"
Write-Host "  State policy: active/inactive content remains distinct; selected hyperlinks use explicit contextual surfaces"
Write-Host "  Disabled discoverability: $script:DisabledAdvisoryCount role(s) below their advisory target; disabled roles remain threshold-exempt"
Write-Host "  Neutral interactions: $script:NeutralInteractionRoleCount generic fill/state role(s) use palette-neutral rest, hover, and pressed sources"
Write-Host "  Generic strokes: $script:GenericStrokeRoleCount quiet, hover, surface, and strong-input stroke role(s) follow the neutral policy"
Write-Host "  Focus indicators: $script:FocusIndicatorRoleCount registered focus role(s) retain theme-specific high-contrast focus anchors"
Write-Host "  Selected accents: $script:SelectedAccentRoleCount registered command border role(s) retain selected/engaged accent meaning"
Write-Host "  Interaction states: neutral hover/pressed hierarchy and border semantics follow the shared policy; $script:InteractionStateAdvisoryCount advisory finding(s)"
Write-Host "  Separator measurements: $script:SeparatorAdvisoryCount runtime advisory measurement(s) recorded against the official Dark reference"
Write-Host "  Hardline dividers: $script:NeutralSeparatorRoleCount neutral separator role(s) use quiet steel while meaningful borders retain strong steel"
Write-Host "  Runtime surfaces: main shell aliases align with the base surface; $script:DocumentLayerThemeCount document-tab channel(s) use palette-derived 30% layers; resting status uses a composited 30% black overlay; tool-window and Output backgrounds align with tertiary panels; Extension Manager gaps are bounded"
Write-Host "  Scrollbars: $script:ScrollbarStateThemeCount theme ladder(s) meet 3:1/3.5:1/4.5:1 state ordering; thumb and arrow glyphs meet 3:1"
Write-Host "  Solution title: $script:ModernSolutionTitleThemeCount modern badge(s) match toolbar layered fills and retain the shared border; $script:SolutionTitleThemeCount legacy title(s) retain their separate neutral policy"
Write-Host "  Cosmora variants: Blueshift, Redshift, and Ultraviolet one-to-one mappings preserved"
exit 0

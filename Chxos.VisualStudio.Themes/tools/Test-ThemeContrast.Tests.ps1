[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$themeDirectory = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'Test-ThemeContrast.ps1'
$windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$tempDirectory = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempDirectory ('cosmora-theme-validator-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$semanticVariableRoles = @(
    'local name',
    'parameter name',
    'CppGlobalVariableSemanticTokenFormat',
    'CppLocalVariableSemanticTokenFormat',
    'CppParameterSemanticTokenFormat'
)

function New-TestCase {
    param([string] $Name)
    $path = Join-Path $testRoot $Name
    [void] (New-Item -ItemType Directory -Path $path)
    Copy-Item -Path (Join-Path $themeDirectory '*.vstheme') -Destination $path
    return $path
}

function Set-TestFileContent {
    param(
        [string] $Path,
        [string] $Content
    )
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Set-SemanticVariableSource {
    param(
        [string] $Text,
        [string] $Source,
        [string[]] $Roles = $semanticVariableRoles
    )

    foreach ($role in $Roles) {
        $pattern = '(?s)(<Color Name="' + [Regex]::Escape($role) + '">.*?<Foreground Type="CT_RAW" Source=")[^"]+'
        $changed = [Regex]::Replace($Text, $pattern, ('${1}' + $Source), 1)
        if ($changed -ceq $Text) {
            throw "Semantic-variable fixture role '$role' was not found."
        }
        $Text = $changed
    }
    return $Text
}

function Set-RoleComponentSource {
    param(
        [string] $Text,
        [string] $Role,
        [ValidateSet('Foreground', 'Background')]
        [string] $Component,
        [string] $OldSource,
        [string] $NewSource
    )

    $pattern = '(?s)(<Color Name="' + [Regex]::Escape($Role) + '">(?:(?!</Color>).)*?<' +
        $Component + '[^>]*?Source=")' + [Regex]::Escape($OldSource)
    $changed = [Regex]::Replace($Text, $pattern, ('${1}' + $NewSource), 1)
    if ($changed -ceq $Text) {
        throw "Fixture role '$Role/$Component' with source '$OldSource' was not found."
    }
    return $changed
}

function Invoke-ValidatorCase {
    param(
        [string] $Name,
        [string] $CaseDirectory,
        [int] $ExpectedExitCode,
        [string] $ExpectedDiagnostic,
        [string] $PolicyPath,
        [string] $AliasReportPath,
        [string] $FocusThemeFile
    )

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $validator, '-ThemeDirectory', $CaseDirectory)
    if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) {
        $arguments += @('-PolicyPath', $PolicyPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($AliasReportPath)) {
        $arguments += @('-AliasReportPath', $AliasReportPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($FocusThemeFile)) {
        $arguments += @('-FocusThemeFile', $FocusThemeFile)
    }
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $windowsPowerShell @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{
        Case = $Name
        ExitCode = $exitCode
        ExpectedExitCode = $ExpectedExitCode
        Diagnostic = $output -match [Regex]::Escape($ExpectedDiagnostic)
        Output = $output.Trim()
    }
}

function Invoke-NegativeCase {
    param(
        [string] $Name,
        [string] $ThemePath,
        [scriptblock] $Mutation,
        [string] $ExpectedDiagnostic
    )

    $content = [IO.File]::ReadAllText($ThemePath)
    $changed = & $Mutation $content
    if ($changed -ceq $content) {
        throw "Test '$Name' did not mutate its fixture."
    }
    Set-TestFileContent -Path $ThemePath -Content $changed
    return Invoke-ValidatorCase `
        -Name $Name `
        -CaseDirectory (Split-Path -Parent $ThemePath) `
        -ExpectedExitCode 1 `
        -ExpectedDiagnostic $ExpectedDiagnostic `
        -FocusThemeFile ([IO.Path]::GetFileName($ThemePath))
}

[void] (New-Item -ItemType Directory -Path $testRoot)
$results = New-Object System.Collections.Generic.List[object]
try {
    $case = New-TestCase 'clean'
    $results.Add((Invoke-ValidatorCase -Name 'Clean baseline' -CaseDirectory $case -ExpectedExitCode 0 -ExpectedDiagnostic 'Theme contrast validation passed.'))

    foreach ($spec in @(
        @{ Name='Struct and class collapse'; Role='struct name'; Family='Struct'; Before='FF9BCCBA'; After='FF7DD3FC' },
        @{ Name='Interface and struct collapse'; Role='interface name'; Family='Interface'; Before='FFCDD6AA'; After='FF9BCCBA' },
        @{ Name='Control and ordinary keyword collapse'; Role='keyword - control'; Family='Control'; Before='FFD3A1C2'; After='FF2DD4BF' },
        @{ Name='Razor directive and keyword collapse'; Role='RazorDirective'; Family='Directive'; Before='FFAEA0DC'; After='FF2DD4BF' }
    )) {
        $case = New-TestCase ('semantic-'+$spec.Family)
        $results.Add((Invoke-NegativeCase -Name $spec.Name -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic ("Core semantic-syntax "+$spec.Family+" role Text Editor MEF Items/"+$spec.Role+" must use opaque anchor") -Mutation {
            param($text)
            Set-RoleComponentSource -Text $text -Role $spec.Role -Component Foreground -OldSource $spec.Before -NewSource $spec.After
        }))
    }

    $case = New-TestCase 'low-contrast-text'
    $results.Add((Invoke-NegativeCase -Name 'Low-contrast text' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'ReportHeaderActive' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ReportHeaderActive">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FF14B8A6', 1)
    }))

    $case = New-TestCase 'low-contrast-glyph'
    $results.Add((Invoke-NegativeCase -Name 'Low-contrast glyph' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'TreeArrowChecked [meaningful glyph]' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="TreeArrowChecked">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FFBAC8BF', 1)
    }))

    $case = New-TestCase 'duplicate-guid'
    [xml] $biolume = [IO.File]::ReadAllText((Join-Path $case 'Biolume.vstheme'))
    $duplicateGuid = [string] $biolume.Themes.Theme.GUID
    $results.Add((Invoke-NegativeCase -Name 'Duplicate theme GUID' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'duplicates' -Mutation {
        param($text)
        [Regex]::Replace($text, '(<Theme Name="Nightglass" GUID=")[^"]+', ('${1}' + $duplicateGuid), 1)
    }))

    $case = New-TestCase 'malformed-guid'
    $results.Add((Invoke-NegativeCase -Name 'Malformed theme GUID' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'not in canonical brace form' -Mutation {
        param($text)
        $text.Replace('{74ebffcf-0561-49d5-b63e-6c0a26536b32}', '74ebffcf-0561-49d5-b63e-6c0a26536b32')
    }))

    $case = New-TestCase 'wrong-base-guid'
    $results.Add((Invoke-NegativeCase -Name 'Wrong base GUID' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'BaseGUID must be the Visual Studio Dark GUID' -Mutation {
        param($text)
        [Regex]::Replace($text, '(BaseGUID=")[^"]+', '${1}{00000000-0000-0000-0000-000000000001}', 1)
    }))

    $case = New-TestCase 'wrong-fallback-guid'
    $results.Add((Invoke-NegativeCase -Name 'Wrong fallback GUID' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'FallbackId must be the Visual Studio Dark GUID' -Mutation {
        param($text)
        [Regex]::Replace($text, '(FallbackId=")[^"]+', '${1}{00000000-0000-0000-0000-000000000001}', 1)
    }))

    $case = New-TestCase 'wrong-root'
    $results.Add((Invoke-NegativeCase -Name 'Wrong document root' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic '<Themes> document root' -Mutation {
        param($text)
        $text.Replace('<Themes>', '<ThemeSet>').Replace('</Themes>', '</ThemeSet>')
    }))

    $case = New-TestCase 'structure'
    $results.Add((Invoke-NegativeCase -Name 'Structural mismatch' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'structure differs' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)\r?\n      <Color Name="StatusBannerSuccess">.*?</Color>', '', 1)
    }))

    $case = New-TestCase 'duplicate-category'
    $results.Add((Invoke-NegativeCase -Name 'Duplicate category name' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "Category name 'Environment' is duplicated" -Mutation {
        param($text)
        $text.Replace('<Category Name="Cider"', '<Category Name="Environment"')
    }))

    $case = New-TestCase 'duplicate-color'
    $results.Add((Invoke-NegativeCase -Name 'Duplicate color name' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "Color 'Cider/BreadcrumbButtonSelected' is duplicated" -Mutation {
        param($text)
        $text.Replace('<Color Name="BreadcrumbButtonSelectedOnHover">', '<Color Name="BreadcrumbButtonSelected">')
    }))

    $case = New-TestCase 'missing-component'
    $results.Add((Invoke-NegativeCase -Name 'Missing color component' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'must define at least one Background or Foreground component' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ReportHeaderActive">).*?(</Color>)', '${1}`r`n      ${2}', 1)
    }))

    $case = New-TestCase 'invalid-type'
    $results.Add((Invoke-NegativeCase -Name 'Invalid component type' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "unsupported component type 'CT_UNKNOWN'" -Mutation {
        param($text)
        [Regex]::Replace($text, 'Type="CT_RAW"', 'Type="CT_UNKNOWN"', 1)
    }))

    $case = New-TestCase 'invalid-source'
    $results.Add((Invoke-NegativeCase -Name 'Invalid component source' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'is not eight-digit hexadecimal ARGB' -Mutation {
        param($text)
        (New-Object Regex '(Source=")[^"]+').Replace($text, '${1}NOT-A-COLOR', 1)
    }))

    $case = New-TestCase 'opaque-overlay'
    $results.Add((Invoke-NegativeCase -Name 'Unsupported editor source alpha' -ThemePath (Join-Path $case 'Cosmora.vstheme') -ExpectedDiagnostic 'opaque CT_RAW editor RGB' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="Call Return">.*?<Background Type="CT_RAW" Source=")FF', '${1}38', 1)
    }))

    $case = New-TestCase 'legacy-tool-window-header-mismatch'
    $results.Add((Invoke-NegativeCase -Name 'Legacy tool-window header mismatch' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'must match Environment/PanelTitleBar' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="TitleBarActiveGradientBegin">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}662DD4BF', 1)
    }))

    $case = New-TestCase 'modern-tool-window-header-mismatch'
    $results.Add((Invoke-NegativeCase -Name 'Modern tool-window header mismatch' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'must match Shell/SolidBackgroundFillTertiary' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="EnvironmentHeader">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
    }))

    $case = New-TestCase 'modern-shell-body-mismatch'
    $results.Add((Invoke-NegativeCase -Name 'Modern shell body mismatch' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'ShellInternal/EnvironmentBody must match Shell/SolidBackgroundFillBase' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="EnvironmentBody">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
    }))

    $case = New-TestCase 'legacy-shell-background-mismatch'
    $results.Add((Invoke-NegativeCase -Name 'Legacy shell background mismatch' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'Environment/EnvironmentBackgroundGradientMiddle1 must match Shell/SolidBackgroundFillBase' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="EnvironmentBackgroundGradientMiddle1">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
    }))

    $case = New-TestCase 'document-layer-opacity'
    $results.Add((Invoke-NegativeCase -Name 'Opaque document-tab layer' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'EnvironmentLayeredBackground must use a 30% translucent layered surface with 0x4D alpha' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="EnvironmentLayeredBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF262C27', 1)
    }))

    $case = New-TestCase 'document-layer-composition'
    $results.Add((Invoke-NegativeCase -Name 'Incorrect document-tab layer composition' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "Composited ShellInternal/EnvironmentLayeredBackground 'FF111513' must match Shell/SolidBackgroundFillSecondary 'FF111512'" -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="EnvironmentLayeredBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}4D262C2B', 1)
    }))

    $case = New-TestCase 'document-layer-collapse'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed document-tab layer' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'effective document-tab layer' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="EnvironmentLayeredBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}4D080B09', 1)
    }))

    $case = New-TestCase 'document-layer-tab-mismatch'
    $results.Add((Invoke-NegativeCase -Name 'Document-tab state mismatch' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "must match ShellInternal/EnvironmentTab 'FF1C1E23'" -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="EnvironmentTab">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF1C1E23', 1)
    }))

    $case = New-TestCase 'cosmora-shifted-document-layer'
    $results.Add((Invoke-NegativeCase -Name 'Cosmora shifted document-tab layer' -ThemePath (Join-Path $case 'CosmoraBlueshift.vstheme') -ExpectedDiagnostic "EnvironmentLayeredBackground must use the palette-derived source '4D1E2E4E'" -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="EnvironmentLayeredBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}4D1E2E4F', 1)
    }))

    $case = New-TestCase 'resting-status-overlay'
    $results.Add((Invoke-NegativeCase -Name 'Resting status overlay mismatch' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "StatusBarBackgroundFillRest must use the 30% black overlay '4D000000'" -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="StatusBarBackgroundFillRest">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF080B09', 1)
    }))

    $case = New-TestCase 'resting-status-contrast'
    $results.Add((Invoke-NegativeCase -Name 'Resting status composited contrast' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'Resting status [normal text]' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="StatusBarTextFillRest">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF000000', 1)
    }))

    $case = New-TestCase 'output-window-surface-mismatch'
    $results.Add((Invoke-NegativeCase -Name 'Output window surface mismatch' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'Output Window/Plain Text must match Shell/SolidBackgroundFillTertiary' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Category Name="Output Window".*?<Color Name="Plain Text">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
    }))

    $case = New-TestCase 'disabled-scrollbar-arrow-glyph'
    $results.Add((Invoke-NegativeCase -Name 'Disabled scrollbar arrow glyph' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'ScrollBarArrowGlyphDisabled [disabled meaningful glyph]' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ScrollBarArrowGlyphDisabled">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
    }))

    $case = New-TestCase 'hover-scrollbar-arrow-glyph'
    $results.Add((Invoke-NegativeCase -Name 'Hover scrollbar arrow glyph' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "Environment/ScrollBarArrowGlyphMouseOver must use approved scrollbar glyph source 'FFEDF5EF'" -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ScrollBarArrowGlyphMouseOver">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}662DD4BF', 1)
    }))

    $case = New-TestCase 'extension-manager-left-gap'
    $results.Add((Invoke-NegativeCase -Name 'Extension Manager left surface gap' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'left shelf-to-list OKLab distance' -Mutation {
        param($text)
        $text = [Regex]::Replace($text, '(?s)(<Color Name="ListBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
        [Regex]::Replace($text, '(?s)(<Color Name="ToolWindowShelf">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
    }))

    $case = New-TestCase 'extension-manager-right-gap'
    $results.Add((Invoke-NegativeCase -Name 'Extension Manager right surface gap' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic 'right summary-to-detail OKLab distance' -Mutation {
        param($text)
        $text = [Regex]::Replace($text, '(?s)(<Color Name="ToolWindow">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
        [Regex]::Replace($text, '(?s)(<Color Name="PageBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111512', 1)
    }))

    $case = New-TestCase 'aquatoxic-accent-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Aquatoxic accent anchor' -ThemePath (Join-Path $case 'Aquatoxic.vstheme') -ExpectedDiagnostic 'Aquatoxic palette anchor Shell/AccentFillDefault/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="AccentFillDefault">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF43CFE0', 1)
    }))

    $case = New-TestCase 'aquatoxic-surface-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Aquatoxic surface anchor' -ThemePath (Join-Path $case 'Aquatoxic.vstheme') -ExpectedDiagnostic 'Aquatoxic palette anchor Shell/SolidBackgroundFillBase/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillBase">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF072E32', 1)
    }))

    $case = New-TestCase 'aquatoxic-syntax-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Aquatoxic syntax anchor' -ThemePath (Join-Path $case 'Aquatoxic.vstheme') -ExpectedDiagnostic 'Aquatoxic palette anchor Text Editor MEF Items/CSS Property Name/Foreground' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="CSS Property Name">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FF43CFE0', 1)
    }))

    $case = New-TestCase 'pinknoise-surface-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Pinknoise surface anchor' -ThemePath (Join-Path $case 'Pinknoise.vstheme') -ExpectedDiagnostic 'Pinknoise palette anchor Shell/SolidBackgroundFillBase/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillBase">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF171019', 1)
    }))

    $case = New-TestCase 'pinknoise-accent-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Pinknoise accent anchor' -ThemePath (Join-Path $case 'Pinknoise.vstheme') -ExpectedDiagnostic 'Pinknoise palette anchor Shell/AccentFillDefault/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="AccentFillDefault">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF56D8D0', 1)
    }))

    $case = New-TestCase 'pinknoise-selection-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Pinknoise selection anchor' -ThemePath (Join-Path $case 'Pinknoise.vstheme') -ExpectedDiagnostic 'Pinknoise palette anchor Shell/SolidBackgroundFillSenary/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillSenary">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FFD65B91', 1)
    }))

    $case = New-TestCase 'pinknoise-syntax-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Pinknoise syntax anchor' -ThemePath (Join-Path $case 'Pinknoise.vstheme') -ExpectedDiagnostic 'Pinknoise palette anchor Text Editor MEF Items/CSS Property Name/Foreground' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="CSS Property Name">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FFF27CAF', 1)
    }))

    $case = New-TestCase 'nullsector-surface-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Nullsector surface anchor' -ThemePath (Join-Path $case 'Nullsector.vstheme') -ExpectedDiagnostic 'Nullsector palette anchor Shell/SolidBackgroundFillBase/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillBase">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF141823', 1)
    }))

    $case = New-TestCase 'nullsector-accent-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Nullsector accent anchor' -ThemePath (Join-Path $case 'Nullsector.vstheme') -ExpectedDiagnostic 'Nullsector palette anchor Shell/AccentFillDefault/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="AccentFillDefault">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF40CFFF', 1)
    }))

    $case = New-TestCase 'nullsector-selection-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Nullsector selection anchor' -ThemePath (Join-Path $case 'Nullsector.vstheme') -ExpectedDiagnostic 'Nullsector palette anchor Shell/SolidBackgroundFillSenary/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillSenary">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF26406B', 1)
    }))

    $case = New-TestCase 'nullsector-syntax-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Nullsector syntax anchor' -ThemePath (Join-Path $case 'Nullsector.vstheme') -ExpectedDiagnostic 'Nullsector palette anchor Text Editor Language Service Items/Keyword/Foreground' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Category Name="Text Editor Language Service Items".*?<Color Name="Keyword">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FF40CFFF', 1)
    }))

    $case = New-TestCase 'silverphase-surface-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Silverphase surface anchor' -ThemePath (Join-Path $case 'Silverphase.vstheme') -ExpectedDiagnostic 'Silverphase palette anchor Shell/SolidBackgroundFillBase/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillBase">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF141A24', 1)
    }))

    $case = New-TestCase 'silverphase-accent-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Silverphase accent anchor' -ThemePath (Join-Path $case 'Silverphase.vstheme') -ExpectedDiagnostic 'Silverphase palette anchor Shell/AccentFillDefault/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="AccentFillDefault">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF8A7CF1', 1)
    }))

    $case = New-TestCase 'silverphase-selection-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Silverphase selection anchor' -ThemePath (Join-Path $case 'Silverphase.vstheme') -ExpectedDiagnostic 'Silverphase palette anchor Shell/SolidBackgroundFillSenary/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillSenary">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF3A8FCD', 1)
    }))

    $case = New-TestCase 'silverphase-syntax-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Silverphase syntax anchor' -ThemePath (Join-Path $case 'Silverphase.vstheme') -ExpectedDiagnostic 'Silverphase palette anchor Text Editor Language Service Items/Keyword/Foreground' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Category Name="Text Editor Language Service Items".*?<Color Name="Keyword">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FF4DA6E6', 1)
    }))

    $case = New-TestCase 'amberroot-surface-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot surface anchor' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic 'Amberroot palette anchor Shell/SolidBackgroundFillBase/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillBase">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF36382D', 1)
    }))

    $case = New-TestCase 'amberroot-accent-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot accent anchor' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic 'Amberroot palette anchor Shell/AccentFillDefault/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="AccentFillDefault">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF9CAF7F', 1)
    }))

    $case = New-TestCase 'amberroot-selection-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot selection anchor' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic 'Amberroot palette anchor Shell/SolidBackgroundFillSenary/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillSenary">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FFD8AB52', 1)
    }))

    $case = New-TestCase 'amberroot-syntax-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot syntax anchor' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic 'Amberroot palette anchor Text Editor Language Service Items/Keyword/Foreground' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Category Name="Text Editor Language Service Items".*?<Color Name="Keyword">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FFAFC58F', 1)
    }))

    $case = New-TestCase 'hardline-surface-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Hardline surface anchor' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic 'Hardline palette anchor Shell/SolidBackgroundFillBase/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillBase">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF151718', 1)
    }))

    $case = New-TestCase 'hardline-accent-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Hardline accent anchor' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic 'Hardline palette anchor Shell/AccentFillDefault/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="AccentFillDefault">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF89AABD', 1)
    }))

    $case = New-TestCase 'hardline-selection-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Hardline selection anchor' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic 'Hardline palette anchor Shell/SolidBackgroundFillSenary/Background' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="SolidBackgroundFillSenary">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FFFFAA2B', 1)
    }))

    $case = New-TestCase 'hardline-syntax-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Hardline syntax anchor' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic 'Hardline palette anchor Text Editor Language Service Items/Keyword/Foreground' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Category Name="Text Editor Language Service Items".*?<Color Name="Keyword">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FF89AABD', 1)
    }))

    foreach ($selectionCase in @(
        @{ Directory = 'silverphase-inactive-selection'; Name = 'Silverphase inactive selection overlay'; File = 'Silverphase.vstheme'; Old = 'FF374551'; New = '3D4DA6E6'; Diagnostic = "Inactive editor selection must use the approved overlay 'FF374551'" },
        @{ Directory = 'amberroot-inactive-selection'; Name = 'Amberroot inactive selection overlay'; File = 'Amberroot.vstheme'; Old = 'FF5A5440'; New = '3DD8AB52'; Diagnostic = "Inactive editor selection must use the approved overlay 'FF5A5440'" },
        @{ Directory = 'nightglass-inactive-selection'; Name = 'Nightglass inactive selection overlay'; File = 'Nightglass.vstheme'; Old = 'FF37495B'; New = '3D38BDF8'; Diagnostic = "Inactive editor selection must use the approved overlay 'FF37495B'" },
        @{ Directory = 'pinknoise-inactive-selection'; Name = 'Pinknoise inactive selection overlay'; File = 'Pinknoise.vstheme'; Old = 'FF4E3E49'; New = '3DF27CAF'; Diagnostic = "Inactive editor selection must use the approved overlay 'FF4E3E49'" }
    )) {
        $case = New-TestCase $selectionCase.Directory
        $oldSource = $selectionCase.Old
        $newSource = $selectionCase.New
        $results.Add((Invoke-NegativeCase -Name $selectionCase.Name -ThemePath (Join-Path $case $selectionCase.File) -ExpectedDiagnostic $selectionCase.Diagnostic -Mutation {
            param($text)
            Set-RoleComponentSource -Text $text -Role 'Inactive Selected Text' -Component Background -OldSource $oldSource -NewSource $newSource
        }))
    }

    $case = New-TestCase 'amberroot-contextual-overlay'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot contextual editor overlay' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic "Contextual editor overlay Current Statement must use approved background 'FF453D26'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'Current Statement' -Component Background -OldSource 'FF453D26' -NewSource '66D8AB52'
    }))

    $case = New-TestCase 'silverphase-variable-string-distance'
    $results.Add((Invoke-NegativeCase -Name 'Silverphase variable string collapse' -ThemePath (Join-Path $case 'Silverphase.vstheme') -ExpectedDiagnostic 'Core semantic-syntax String role Text Editor Language Service Items/String must use opaque anchor' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'String' -Component Foreground -OldSource 'FF7EE6F2' -NewSource 'FF72B5FF'
    }))

    $case = New-TestCase 'amberroot-keyword-number-distance'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot keyword number collapse' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic 'Core semantic-syntax Number role Text Editor Language Service Items/Number must use opaque anchor' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'Number' -Component Foreground -OldSource 'FFF9A05B' -NewSource 'FFE0B862'
    }))

    $case = New-TestCase 'amberroot-string-type-distance'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot string type collapse' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic 'Core semantic-syntax Type role Text Editor MEF Items/class name must use opaque anchor' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'class name' -Component Foreground -OldSource 'FFCBDDB5' -NewSource 'FFAFC58F'
    }))

    $case = New-TestCase 'hardline-method-plain-distance'
    $results.Add((Invoke-NegativeCase -Name 'Hardline method plain-text collapse' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic 'Core semantic-syntax Method role Text Editor MEF Items/method name must use opaque anchor' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'method name' -Component Foreground -OldSource 'FFFFE066' -NewSource 'FFFAFAF7'
    }))

    $case = New-TestCase 'hardline-comment-variable-distance'
    $results.Add((Invoke-NegativeCase -Name 'Hardline comment variable collapse' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic 'Core semantic-syntax Comment role Text Editor Language Service Items/Comment must use opaque anchor' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'Comment' -Component Foreground -OldSource 'FFB6A58E' -NewSource 'FF89AABD'
    }))

    $case = New-TestCase 'hardline-neutral-separator'
    $results.Add((Invoke-NegativeCase -Name 'Hardline neutral separator strength' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic "Neutral separator Environment/PanelSeparator must use quiet steel 'FF42484B'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'PanelSeparator' -Component Background -OldSource 'FF42484B' -NewSource 'FF697277'
    }))

    $case = New-TestCase 'hardline-meaningful-border'
    $results.Add((Invoke-NegativeCase -Name 'Hardline meaningful border strength' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic "Meaningful border Environment/ComboBoxBorder must retain strong steel 'FF697277'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'ComboBoxBorder' -Component Background -OldSource 'FF697277' -NewSource 'FF42484B'
    }))

    $case = New-TestCase 'cosmora-ultraviolet-palette-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Cosmora Ultraviolet palette anchor' -ThemePath (Join-Path $case 'CosmoraUltraviolet.vstheme') -ExpectedDiagnostic "Palette anchor Shell/AccentFillDefault/Background must be 'FFA85FE4'" -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="AccentFillDefault">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FFE35F35', 1)
    }))

    $case = New-TestCase 'cosmora-redshift-palette-anchor'
    $results.Add((Invoke-NegativeCase -Name 'Cosmora Redshift palette anchor' -ThemePath (Join-Path $case 'CosmoraRedshift.vstheme') -ExpectedDiagnostic "Palette anchor Shell/AccentFillDefault/Background must be 'FFE35F35'" -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="AccentFillDefault">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FFA85FE4', 1)
    }))

    $case = New-TestCase 'razor-html-hierarchy'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed Razor HTML hierarchy' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic 'Razor/HTML semantic role Text Editor MEF Items/HTML Element Name' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="HTML Element Name">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FF5EEAD4', 1)
    }))

    $case = New-TestCase 'css-hierarchy'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed CSS property hierarchy' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic 'CSS semantic role Text Editor MEF Items/CSS Property Value' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="CSS Property Value">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FF5EEAD4', 1)
    }))

    $case = New-TestCase 'editor-selection-supporting-surface'
    $results.Add((Invoke-NegativeCase -Name 'Editor selection dedicated surface' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic "Active editor selection Text Editor Text Manager Items/Selected Text/Background must use approved source 'FF566273'" -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Category Name="Text Editor Text Manager Items".*?<Color Name="Selected Text">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF3E3E40', 1)
    }))

    $case = New-TestCase 'semantic-variable-plain-collapse'
    $results.Add((Invoke-NegativeCase -Name 'Semantic variable collapsed to plain text' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic 'Semantic-variable-to-plain-text OKLab distance' -Mutation {
        param($text)
        Set-SemanticVariableSource -Text $text -Source 'FFE7E7E7'
    }))

    $case = New-TestCase 'semantic-variable-cpp-divergence'
    $results.Add((Invoke-NegativeCase -Name 'C++ semantic variable divergence' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'CppLocalVariableSemanticTokenFormat/Foreground must use theme anchor' -Mutation {
        param($text)
        Set-SemanticVariableSource -Text $text -Source 'FFE7E7E7' -Roles @('CppLocalVariableSemanticTokenFormat')
    }))

    $case = New-TestCase 'semantic-variable-distance'
    $results.Add((Invoke-NegativeCase -Name 'Semantic variable too close to method' -ThemePath (Join-Path $case 'CosmoraRedshift.vstheme') -ExpectedDiagnostic 'Semantic-variable-to-method OKLab distance' -Mutation {
        param($text)
        Set-SemanticVariableSource -Text $text -Source 'FFEE8B65'
    }))

    $case = New-TestCase 'semantic-variable-selection-contrast'
    $results.Add((Invoke-NegativeCase -Name 'Semantic variable active-selection contrast' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic 'Semantic variables/active selection [normal text]' -Mutation {
        param($text)
        Set-SemanticVariableSource -Text $text -Source 'FF6080A0'
    }))

    $case = New-TestCase 'translucent-enabled-text'
    $results.Add((Invoke-NegativeCase -Name 'Translucent enabled legacy text' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'ComboBoxFocusedText [normal text] must be opaque' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ComboBoxFocusedText">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}66E7E7E7', 1)
    }))

    $case = New-TestCase 'translucent-enabled-link'
    $results.Add((Invoke-NegativeCase -Name 'Translucent enabled legacy hyperlink' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'PanelHyperlink [enabled hyperlink] must be opaque' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="PanelHyperlink">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}66A5B4FC', 1)
    }))

    $case = New-TestCase 'translucent-enabled-glyph'
    $results.Add((Invoke-NegativeCase -Name 'Translucent enabled legacy glyph' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'ComboBoxFocusedGlyph [meaningful glyph] must be opaque' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ComboBoxFocusedGlyph">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}66E7E7E7', 1)
    }))

    $case = New-TestCase 'caption-surface-classification'
    $results.Add((Invoke-NegativeCase -Name 'Incorrect caption surface classification' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'ActiveCaption [active caption surface] must be an opaque surface' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ActiveCaption">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}66192137', 1)
    }))

    $case = New-TestCase 'low-contrast-legacy-link'
    $results.Add((Invoke-NegativeCase -Name 'Low-contrast legacy hyperlink' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'PanelHyperlink [enabled hyperlink] must use Shell/HyperlinkFillPrimary' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="PanelHyperlink">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF5F6F8C', 1)
    }))

    $case = New-TestCase 'selected-legacy-link'
    $results.Add((Invoke-NegativeCase -Name 'Invalid selected hyperlink pairing' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'PanelHyperlinkInsideSelectionActive selected hyperlink foreground must use' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="PanelHyperlinkInsideSelectionActive">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FFA5B4FC', 1)
    }))

    $case = New-TestCase 'legacy-state-collapse'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed active inactive legacy state' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'TitleBarActiveText and Environment/TitleBarInactiveText collapse' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="TitleBarInactiveText">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FFE7E7E7', 1)
    }))

    $case = New-TestCase 'legacy-tooltip-hint'
    $results.Add((Invoke-NegativeCase -Name 'Invisible legacy tooltip hint' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'ToolTipHintText [secondary text] must use Shell/TextFillSecondary' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ToolTipHintText">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF070B16', 1)
    }))

    $case = New-TestCase 'legacy-commandbar-content'
    $results.Add((Invoke-NegativeCase -Name 'Translucent legacy command-bar content' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'CommandBarTextHover [normal text] must be opaque' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="CommandBarTextHover">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}6638BDF8', 1)
    }))

    $case = New-TestCase 'legacy-start-page-content'
    $results.Add((Invoke-NegativeCase -Name 'Invisible legacy Start Page content' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'StartPageTextBody [normal text] must use Shell/TextFillPrimary' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="StartPageTextBody">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111827', 1)
    }))

    $case = New-TestCase 'legacy-tab-surface'
    $results.Add((Invoke-NegativeCase -Name 'Inverted legacy selected-tab surface' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'FileTabSelectedBackground [selected document tab surface] must match Shell/SolidBackgroundFillSenary' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="FileTabSelectedBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FFD8E3F1', 1)
    }))

    $case = New-TestCase 'legacy-tab-text'
    $results.Add((Invoke-NegativeCase -Name 'Inverted legacy selected-tab text' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'FileTabSelectedText [normal text] must use Shell/TextFillPrimary' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="FileTabSelectedText">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF000000', 1)
    }))

    $case = New-TestCase 'legacy-docking-outline'
    $results.Add((Invoke-NegativeCase -Name 'Low-contrast docking outline' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'DockTargetGlyphBorder [meaningful docking outline] must use Shell/TextFillSecondary' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="DockTargetGlyphBorder">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF263149', 1)
    }))

    foreach ($borderCase in @(
        @{ Name = 'validation-border'; Role = 'ToolWindowValidationErrorBorder'; Diagnostic = 'critical validation indicator' },
        @{ Name = 'screentip-border'; Role = 'ScreenTipBorder'; Diagnostic = 'caution emphasis indicator' },
        @{ Name = 'smarttag-border'; Role = 'SmartTagBorder'; Diagnostic = 'caution emphasis indicator' },
        @{ Name = 'pressed-command-border'; Role = 'CommandBarMouseDownBorder'; Diagnostic = 'pressed command indicator' }
    )) {
        $case = New-TestCase $borderCase.Name
        $role = $borderCase.Role
        $diagnostic = $borderCase.Diagnostic
        $results.Add((Invoke-NegativeCase -Name "Semantic border $role" -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic $diagnostic -Mutation {
            param($text)
            [Regex]::Replace($text, ('(?s)(<Color Name="' + [Regex]::Escape($role) + '">.*?<Background Type="CT_RAW" Source=")[^"]+'), '${1}FF263149', 1)
        }))
    }

    $case = New-TestCase 'malformed-role-policy'
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1'))
    $policyText = [Regex]::Replace($policyText, "; SurfaceBase = 'SolidBackgroundFillSecondary'", '', 1)
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Malformed single-component surface registry' -CaseDirectory $case -PolicyPath $policyCopy -ExpectedExitCode 1 -ExpectedDiagnostic 'without a policy SurfaceBase'))

    $case = New-TestCase 'malformed-interaction-policy'
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1'))
    $policyText = $policyText.Replace("PressedBorder = 'ComboBoxMouseDownBorder'", "PressedBorder = ''")
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Malformed interaction-state registry' -CaseDirectory $case -PolicyPath $policyCopy -ExpectedExitCode 1 -ExpectedDiagnostic "Interaction-state policy 'combo-box hover/pressed' is missing: PressedBorder"))

    $case = New-TestCase 'advisory-report'
    $advisoryReport = Join-Path $case 'advisory-report.json'
    $advisoryResult = Invoke-ValidatorCase -Name 'Interaction and separator advisory report' -CaseDirectory $case -AliasReportPath $advisoryReport -ExpectedExitCode 0 -ExpectedDiagnostic 'Interaction states: neutral hover/pressed hierarchy and border semantics follow the shared policy; 0 advisory finding(s)'
    if (-not (Test-Path -LiteralPath $advisoryReport -PathType Leaf)) {
        $advisoryResult.Diagnostic = $false
        $advisoryResult.Output += "`nAdvisory report was not created."
    }
    else {
        $parsedAdvisories = [IO.File]::ReadAllText($advisoryReport) | ConvertFrom-Json
        $advisories = @()
        foreach ($advisory in $parsedAdvisories) {
            $advisories += $advisory
        }
        $interactionAdvisories = @($advisories | Where-Object Kind -eq 'interaction state collapse')
        $separatorAdvisories = @($advisories | Where-Object Kind -eq 'separator strength')
        $obsoleteAliasAdvisories = @($advisories | Where-Object Kind -eq 'alias collapse')
        if ($interactionAdvisories.Count -ne 0 -or $separatorAdvisories.Count -ne 13 -or $obsoleteAliasAdvisories.Count -ne 0) {
            $advisoryResult.Diagnostic = $false
            $advisoryResult.Output += "`nExpected no interaction-state advisories, 13 separator measurements, and no obsolete alias-collapse advisories."
        }
    }
    $results.Add($advisoryResult)

    $case = New-TestCase 'combo-pressed-surface'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed combo-box pressed surface' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'requires Environment/ComboBoxMouseDownBackground to use neutral pressed source' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ComboBoxMouseDownBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}6638BDF8', 1)
    }))

    $case = New-TestCase 'combo-pressed-border'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed combo-box pressed border' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'requires Environment/ComboBoxMouseDownBorder to use Shell/ControlStrongStrokeDefault' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ComboBoxMouseDownBorder">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF263149', 1)
    }))

    $case = New-TestCase 'dropdown-pressed-border'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed drop-down pressed border' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'requires Environment/DropDownMouseDownBorder to use Shell/ControlStrongStrokeDefault' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="DropDownMouseDownBorder">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF263149', 1)
    }))

    foreach ($modernCase in @(
        @{ Name = 'accent-generic-control-fill'; Role = 'ControlFillSecondary'; Source = '1538BDF8'; Diagnostic = 'secondary neutral control fill' },
        @{ Name = 'accent-subtle-hover-fill'; Role = 'SubtleFillSecondary'; Source = '1838BDF8'; Diagnostic = 'subtle neutral hover fill' },
        @{ Name = 'accent-generic-control-stroke'; Role = 'ControlStrokeDefault'; Source = '1238BDF8'; Diagnostic = 'quiet neutral control stroke' },
        @{ Name = 'accent-generic-surface-stroke'; Role = 'SurfaceStrokeDefault'; Source = '6638BDF8'; Diagnostic = 'strong neutral surface stroke' }
    )) {
        $case = New-TestCase $modernCase.Name
        $role = $modernCase.Role
        $source = $modernCase.Source
        $diagnostic = $modernCase.Diagnostic
        $results.Add((Invoke-NegativeCase -Name "Accent leak $role" -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic $diagnostic -Mutation {
            param($text)
            [Regex]::Replace($text, ('(?s)(<Color Name="' + [Regex]::Escape($role) + '">.*?<Background Type="CT_RAW" Source=")[^"]+'), ('${1}' + $source), 1)
        }))
    }

    $case = New-TestCase 'collapsed-rest-hover'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed resting and hover surfaces' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'requires Environment/ComboBoxMouseOverBackgroundBegin to use neutral hover source' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ComboBoxMouseOverBackgroundBegin">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111827', 1)
    }))

    $case = New-TestCase 'collapsed-hover-pressed'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed hover and pressed surfaces' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'requires Environment/ComboBoxMouseDownBackground to use neutral pressed source' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ComboBoxMouseDownBackground">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}18E7E7E7', 1)
    }))

    $case = New-TestCase 'combo-pressed-accent'
    $results.Add((Invoke-NegativeCase -Name 'Accent combo-box pressed border' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'pressed combo-box input border' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ComboBoxMouseDownBorder">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF38BDF8', 1)
    }))

    $case = New-TestCase 'dropdown-pressed-accent'
    $results.Add((Invoke-NegativeCase -Name 'Accent drop-down pressed border' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'pressed drop-down input border' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="DropDownMouseDownBorder">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF38BDF8', 1)
    }))

    $case = New-TestCase 'selected-command-neutral'
    $results.Add((Invoke-NegativeCase -Name 'Neutralized selected command border' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'selected command indicator' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="CommandBarSelectedBorder">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF43516D', 1)
    }))

    $case = New-TestCase 'weak-focus-indicator'
    $results.Add((Invoke-NegativeCase -Name 'Weak keyboard focus indicator' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'focused button border' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ButtonBorderFocused">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF111827', 1)
    }))

    $case = New-TestCase 'weak-hover-outline'
    $results.Add((Invoke-NegativeCase -Name 'Weak ordinary hover outline' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'environment neutral hover strokes' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ComboBoxMouseOverBorder">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}12111827', 1)
    }))

    $case = New-TestCase 'default-action-neutralized'
    $results.Add((Invoke-NegativeCase -Name 'Neutralized default-action border' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic 'pressed command indicator' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="CommandBarMouseDownBorder">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}FF43516D', 1)
    }))

    $case = New-TestCase 'interaction-mapping-split'
    $results.Add((Invoke-NegativeCase -Name 'Neutral interaction mapping split' -ThemePath (Join-Path $case 'CosmoraBlueshift.vstheme') -ExpectedDiagnostic 'maps to 2 shifted values' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="ControlFillSecondary">.*?<Background Type="CT_RAW" Source=")[^"]+', '${1}15FFFFFF', 1)
    }))

    $case = New-TestCase 'scrollbar-track-thumb-collapse'
    $results.Add((Invoke-NegativeCase -Name 'Identical scrollbar track and thumb' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "ScrollBarThumbBackground must use approved scrollbar source 'FF5B645E'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'ScrollBarThumbBackground' -Component Background -OldSource 'FF5B645E' -NewSource 'FF111512'
    }))

    $case = New-TestCase 'scrollbar-state-ordering'
    $results.Add((Invoke-NegativeCase -Name 'Weak scrollbar hover and pressed ordering' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "ScrollBarThumbMouseOverBackground must use approved scrollbar source 'FF656F68'" -Mutation {
        param($text)
        $text = Set-RoleComponentSource -Text $text -Role 'ScrollBarThumbMouseOverBackground' -Component Background -OldSource 'FF656F68' -NewSource 'FF5B645E'
        Set-RoleComponentSource -Text $text -Role 'ScrollBarThumbPressedBackground' -Component Background -OldSource 'FF768079' -NewSource 'FF656F68'
    }))

    $case = New-TestCase 'scrollbar-invisible-glyph'
    $results.Add((Invoke-NegativeCase -Name 'Invisible scrollbar thumb glyph' -ThemePath (Join-Path $case 'Biolume.vstheme') -ExpectedDiagnostic "ScrollBarThumbGlyph must use approved scrollbar source 'FFEDF5EF'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'ScrollBarThumbGlyph' -Component Background -OldSource 'FFEDF5EF' -NewSource 'FF5B645E'
    }))

    $case = New-TestCase 'find-low-contrast'
    $themePath = Join-Path $case 'Nightglass.vstheme'
    $text = [IO.File]::ReadAllText($themePath)
    $text = Set-RoleComponentSource -Text $text -Role 'MarkerFormatDefinition/FindHighlight' -Component Background -OldSource 'FF2B1A1B' -NewSource '7AFACC15'
    Set-TestFileContent -Path $themePath -Content $text
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')).Replace("Nightglass = 'FF2B1A1B'", "Nightglass = '7AFACC15'")
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Low-contrast Find overlay' -CaseDirectory $case -PolicyPath $policyCopy -FocusThemeFile 'Nightglass.vstheme' -ExpectedExitCode 1 -ExpectedDiagnostic 'inside Find highlight'))

    $case = New-TestCase 'find-weaker-than-reference'
    $themePath = Join-Path $case 'Foundation.vstheme'
    $text = [IO.File]::ReadAllText($themePath)
    $text = Set-RoleComponentSource -Text $text -Role 'MarkerFormatDefinition/FindHighlight' -Component Background -OldSource 'FF2B1D0F' -NewSource 'FF171F2B'
    Set-TestFileContent -Path $themePath -Content $text
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')).Replace("Foundation = 'FF2B1D0F'", "Foundation = 'FF171F2B'")
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Find weaker than reference' -CaseDirectory $case -PolicyPath $policyCopy -FocusThemeFile 'Foundation.vstheme' -ExpectedExitCode 1 -ExpectedDiagnostic 'Outlined Find fill must be at least 0.01 stronger'))

    $case = New-TestCase 'reference-outline-missing'
    $results.Add((Invoke-NegativeCase -Name 'Missing reference marker outline' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic "reference marker Text Editor MEF Items/MarkerFormatDefinition/HighlightedReference must use outline 'FFA5B4FC'" -Mutation {
        param($text)
        [Regex]::Replace(
            $text,
            '(?s)(<Color Name="MarkerFormatDefinition/HighlightedReference">(?:(?!</Color>).)*?<Foreground )Type="CT_RAW" Source="FFA5B4FC"',
            '${1}Type="CT_INVALID" Source="00000000"',
            1)
    }))

    $case = New-TestCase 'definition-marker-collapsed'
    $results.Add((Invoke-NegativeCase -Name 'Collapsed definition marker family' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic "definition marker Text Editor MEF Items/MarkerFormatDefinition/HighlightedDefinition must use fill 'FF0E1E29'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'MarkerFormatDefinition/HighlightedDefinition' -Component Background -OldSource 'FF0E1E29' -NewSource '3038BDF8'
    }))

    $case = New-TestCase 'nullsector-active-selection-collapse'
    $themePath = Join-Path $case 'Nullsector.vstheme'
    $text = [IO.File]::ReadAllText($themePath)
    $text = Set-RoleComponentSource -Text $text -Role 'Selected Text' -Component Background -OldSource 'FF475861' -NewSource 'FF080B12'
    Set-TestFileContent -Path $themePath -Content $text
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')).Replace("Nullsector = 'FF132934'", "Nullsector = 'FF080B12'")
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Collapsed Nullsector active selection' -CaseDirectory $case -PolicyPath $policyCopy -FocusThemeFile 'Nullsector.vstheme' -ExpectedExitCode 1 -ExpectedDiagnostic 'Priority refinement selection-visibility'))

    $case = New-TestCase 'nullsector-relative-selection-prominence'
    $themePath=Join-Path $case 'Nullsector.vstheme'
    $text=Set-RoleComponentSource -Text ([IO.File]::ReadAllText($themePath)) -Role 'Selected Text' -Component Background -OldSource 'FF475861' -NewSource 'FF0E1B24'
    Set-TestFileContent -Path $themePath -Content $text
    $results.Add((Invoke-ValidatorCase -Name 'Nullsector relative selection prominence' -CaseDirectory $case -FocusThemeFile 'Nullsector.vstheme' -ExpectedExitCode 1 -ExpectedDiagnostic 'Priority refinement selection-order'))

    $case = New-TestCase 'refinement-scope-with-established-failure'
    $themePath=Join-Path $case 'Aquatoxic.vstheme'
    [xml]$themeXml=[IO.File]::ReadAllText($themePath)
    $plain=$themeXml.SelectSingleNode('//Category[@Name="Text Editor Text Manager Items"]/Color[@Name="Plain Text"]/Background').Source
    $text=Set-RoleComponentSource -Text ([IO.File]::ReadAllText($themePath)) -Role 'Inactive Selected Text' -Component Background -OldSource 'FF385837' -NewSource $plain
    Set-TestFileContent -Path $themePath -Content $text
    $policyCopy=Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')).Replace("'Aquatoxic' = 'enforced'","'Aquatoxic' = 'invalid'")
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $scopeResult=Invoke-ValidatorCase -Name 'Invalid scope retains established hierarchy failure' -CaseDirectory $case -PolicyPath $policyCopy -FocusThemeFile 'Aquatoxic.vstheme' -ExpectedExitCode 1 -ExpectedDiagnostic 'Current line must not be stronger than inactive selection'
    $scopeResult.Diagnostic=$scopeResult.Diagnostic -and $scopeResult.Output.Contains('Invalid refinement enforcement state for Aquatoxic')
    $results.Add($scopeResult)

    $case = New-TestCase 'current-line-collapse'
    $themePath = Join-Path $case 'Foundation.vstheme'
    $text = [IO.File]::ReadAllText($themePath)
    $text = Set-RoleComponentSource -Text $text -Role 'CurrentLineActiveFormat' -Component Background -OldSource 'FF1C1C1F' -NewSource 'FF0E0E11'
    Set-TestFileContent -Path $themePath -Content $text
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')).Replace("Foundation = 'FF1C1C1F'", "Foundation = 'FF0E0E11'")
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Collapsed current line' -CaseDirectory $case -PolicyPath $policyCopy -FocusThemeFile 'Foundation.vstheme' -ExpectedExitCode 1 -ExpectedDiagnostic 'Current-line OKLab distance'))

    $case = New-TestCase 'solution-title-accent-opacity'
    $results.Add((Invoke-NegativeCase -Name 'Accent and opaque solution-title regression' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic 'Active solution-name background must use the 0x0F primary-text neutral lift' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'MainWindowSolutionNameActiveBackground' -Component Background -OldSource '0FE7E7E7' -NewSource 'FF5EEAD4'
    }))

    $case = New-TestCase 'modern-solution-title-accent'
    $results.Add((Invoke-NegativeCase -Name 'Modern solution-title accent regression' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic 'Modern solution-name badge must match the toolbar layered background' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'EnvironmentBadge' -Component Background -OldSource '4D252528' -NewSource '3360A5FA'
    }))

    $case = New-TestCase 'modern-solution-title-alpha'
    $results.Add((Invoke-NegativeCase -Name 'Modern solution-title opacity regression' -ThemePath (Join-Path $case 'Aquatoxic.vstheme') -ExpectedDiagnostic 'Modern solution-name badge must match the toolbar layered background' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'EnvironmentBadge' -Component Background -OldSource '4D17555C' -NewSource 'FF17555C'
    }))

    $case = New-TestCase 'inactive-selection-anchor-churn'
    $results.Add((Invoke-NegativeCase -Name 'Inactive-selection anchor churn' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic "Inactive editor selection must use the approved overlay 'FF3D4958'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'Inactive Selected Text' -Component Background -OldSource 'FF3D4958' -NewSource '3D60A5FB'
    }))

    $case = New-TestCase 'runtime-highlight-mapping-split'
    $themePath = Join-Path $case 'CosmoraBlueshift.vstheme'
    $text = [IO.File]::ReadAllText($themePath)
    $text = Set-RoleComponentSource -Text $text -Role 'ScrollBarThumbGlyph' -Component Background -OldSource 'FFEDF4FF' -NewSource 'FFEDF4FE'
    Set-TestFileContent -Path $themePath -Content $text
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')).Replace("Glyph = 'FFEDF4FF'", "Glyph = 'FFEDF4FE'")
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Runtime highlight mapping split' -CaseDirectory $case -PolicyPath $policyCopy -FocusThemeFile 'CosmoraBlueshift.vstheme' -ExpectedExitCode 1 -ExpectedDiagnostic 'maps to 2 shifted values'))

    $case = New-TestCase 'core-syntax-amberroot-neutral-collision'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot comment and operator collision' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic "Core semantic-syntax Comment role Text Editor Language Service Items/Comment must use opaque anchor 'FFB7AB93'" -Mutation {
        param($text)
        $text = Set-RoleComponentSource -Text $text -Role 'Comment' -Component Foreground -OldSource 'FFB7AB93' -NewSource 'FFB0AC98'
        Set-RoleComponentSource -Text $text -Role 'Operator' -Component Foreground -OldSource 'FFC9C3AF' -NewSource 'FFB0AC98'
    }))

    $case = New-TestCase 'core-syntax-amberroot-method-collision'
    $results.Add((Invoke-NegativeCase -Name 'Amberroot keyword and method collision' -ThemePath (Join-Path $case 'Amberroot.vstheme') -ExpectedDiagnostic "Core semantic-syntax Method role Text Editor MEF Items/method name must use opaque anchor 'FFF1D18E'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'method name' -Component Foreground -OldSource 'FFF1D18E' -NewSource 'FFE0B862'
    }))

    $case = New-TestCase 'core-syntax-aquatoxic-collisions'
    $results.Add((Invoke-NegativeCase -Name 'Aquatoxic type and comment collisions' -ThemePath (Join-Path $case 'Aquatoxic.vstheme') -ExpectedDiagnostic "Core semantic-syntax Comment role Text Editor Language Service Items/Comment must use opaque anchor 'FFACB6B7'" -Mutation {
        param($text)
        $text = Set-RoleComponentSource -Text $text -Role 'Comment' -Component Foreground -OldSource 'FFACB6B7' -NewSource 'FF86E6EC'
        Set-RoleComponentSource -Text $text -Role 'class name' -Component Foreground -OldSource 'FFC4B5FD' -NewSource 'FFF4FBFD'
    }))

    $case = New-TestCase 'core-syntax-cosmora-method-mapping'
    $results.Add((Invoke-NegativeCase -Name 'Broken Cosmora method mapping' -ThemePath (Join-Path $case 'CosmoraBlueshift.vstheme') -ExpectedDiagnostic 'maps to 2 shifted values' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'method name' -Component Foreground -OldSource 'FF8299ED' -NewSource 'FF8299EE'
    }))

    $case = New-TestCase 'core-syntax-foundation-method-collapse'
    $results.Add((Invoke-NegativeCase -Name 'Foundation method and type collapse' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic "Core semantic-syntax Method role Text Editor MEF Items/method name must use opaque anchor 'FFC4B5FD'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'method name' -Component Foreground -OldSource 'FFC4B5FD' -NewSource 'FF7DD3FC'
    }))

    foreach ($hardlineCase in @(
        @{ Directory = 'core-syntax-hardline-method'; Name = 'Hardline method lane collapse'; Role = 'method name'; Old = 'FFFFE066'; New = 'FFFFAA2B'; Family = 'Method' },
        @{ Directory = 'core-syntax-hardline-type'; Name = 'Hardline type lane collapse'; Role = 'class name'; Old = 'FF8EC8E5'; New = 'FF89AABD'; Family = 'Type' },
        @{ Directory = 'core-syntax-hardline-comment'; Name = 'Hardline comment lane collapse'; Role = 'Comment'; Old = 'FFB6A58E'; New = 'FFC3C7C5'; Family = 'Comment' }
    )) {
        $case = New-TestCase $hardlineCase.Directory
        $fixture = $hardlineCase
        $results.Add((Invoke-NegativeCase -Name $fixture.Name -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic "Core semantic-syntax $($fixture.Family) role" -Mutation {
            param($text)
            Set-RoleComponentSource -Text $text -Role $fixture.Role -Component Foreground -OldSource $fixture.Old -NewSource $fixture.New
        }))
    }

    $case = New-TestCase 'core-syntax-nightglass-method-collapse'
    $results.Add((Invoke-NegativeCase -Name 'Nightglass method and type collapse' -ThemePath (Join-Path $case 'Nightglass.vstheme') -ExpectedDiagnostic "Core semantic-syntax Method role Text Editor MEF Items/method name must use opaque anchor 'FFDCA8FF'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'method name' -Component Foreground -OldSource 'FFDCA8FF' -NewSource 'FF67E8F9'
    }))

    $case = New-TestCase 'core-syntax-nullsector-operator-collapse'
    $results.Add((Invoke-NegativeCase -Name 'Nullsector comment and operator collapse' -ThemePath (Join-Path $case 'Nullsector.vstheme') -ExpectedDiagnostic "Core semantic-syntax Operator role Text Editor MEF Items/Operator must use opaque anchor 'FF9AA7B7'" -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'Operator' -Component Foreground -OldSource 'FF9AA7B7' -NewSource 'FF8593A5'
    }))

    foreach ($pinknoiseCase in @(
        @{ Directory = 'core-syntax-pinknoise-number'; Name = 'Pinknoise keyword and number collapse'; Role = 'Number'; Old = 'FFF3A56F'; New = 'FFF27CAF'; Family = 'Number' },
        @{ Directory = 'core-syntax-pinknoise-operator'; Name = 'Pinknoise comment and operator collapse'; Role = 'Operator'; Old = 'FFC9B1BE'; New = 'FFA78E9B'; Family = 'Operator' }
    )) {
        $case = New-TestCase $pinknoiseCase.Directory
        $fixture = $pinknoiseCase
        $results.Add((Invoke-NegativeCase -Name $fixture.Name -ThemePath (Join-Path $case 'Pinknoise.vstheme') -ExpectedDiagnostic "Core semantic-syntax $($fixture.Family) role" -Mutation {
            param($text)
            Set-RoleComponentSource -Text $text -Role $fixture.Role -Component Foreground -OldSource $fixture.Old -NewSource $fixture.New
        }))
    }

    foreach ($silverphaseCase in @(
        @{ Directory = 'core-syntax-silverphase-type'; Name = 'Silverphase type and variable collapse'; Role = 'class name'; Old = 'FFB7A7F7'; New = 'FF72B5FF'; Family = 'Type' },
        @{ Directory = 'core-syntax-silverphase-operator'; Name = 'Silverphase method and operator collapse'; Role = 'Operator'; Old = 'FFD4DCE8'; New = 'FF9CCBF2'; Family = 'Operator' }
    )) {
        $case = New-TestCase $silverphaseCase.Directory
        $fixture = $silverphaseCase
        $results.Add((Invoke-NegativeCase -Name $fixture.Name -ThemePath (Join-Path $case 'Silverphase.vstheme') -ExpectedDiagnostic "Core semantic-syntax $($fixture.Family) role" -Mutation {
            param($text)
            Set-RoleComponentSource -Text $text -Role $fixture.Role -Component Foreground -OldSource $fixture.Old -NewSource $fixture.New
        }))
    }

    $case = New-TestCase 'core-syntax-family-desynchronization'
    $results.Add((Invoke-NegativeCase -Name 'Roslyn and C++ method desynchronization' -ThemePath (Join-Path $case 'Hardline.vstheme') -ExpectedDiagnostic 'CppFunctionSemanticTokenFormat must use opaque anchor' -Mutation {
        param($text)
        Set-RoleComponentSource -Text $text -Role 'CppFunctionSemanticTokenFormat' -Component Foreground -OldSource 'FFFFE066' -NewSource 'FFD8E3E8'
    }))

    $case = New-TestCase 'core-syntax-explicit-member-color'
    $results.Add((Invoke-NegativeCase -Name 'Explicit C# field coloring' -ThemePath (Join-Path $case 'Foundation.vstheme') -ExpectedDiagnostic 'field name must retain inherited neutral foreground semantics with CT_INVALID' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="field name">(?:(?!</Color>).)*?<Foreground )Type="CT_INVALID" Source="[^\"]+"', '${1}Type="CT_RAW" Source="FFE7E7E7"', 1)
    }))

    $case = New-TestCase 'malformed-core-syntax-policy'
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1'))
    $policyText = $policyText.Replace("@{ Category = 'Text Editor MEF Items'; Role = 'method name' }", "@{ Category = 'Text Editor MEF Items'; Role = '' }")
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Malformed semantic syntax policy' -CaseDirectory $case -PolicyPath $policyCopy -FocusThemeFile 'Hardline.vstheme' -ExpectedExitCode 1 -ExpectedDiagnostic "Core semantic-syntax family 'Method' contains a malformed role registry entry."))

    $case = New-TestCase 'disabled-clean'
    $results.Add((Invoke-ValidatorCase -Name 'Disabled on-accent discoverability passes' -CaseDirectory $case -ExpectedExitCode 0 -ExpectedDiagnostic 'Disabled discoverability: 0 role(s) below their advisory target'))

    $case = New-TestCase 'disabled-advisory'
    $policyCopy = Join-Path $case 'ThemeRolePolicy.psd1'
    $policyText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1'))
    $policyText = [Regex]::Replace(
        $policyText,
        "(PanelDisabledHyperlinkInsideSelectionActive'.*?AdvisoryMinimum = )1\.5",
        '${1}3.0',
        [Text.RegularExpressions.RegexOptions]::Singleline)
    Set-TestFileContent -Path $policyCopy -Content $policyText
    $results.Add((Invoke-ValidatorCase -Name 'Disabled discoverability remains advisory' -CaseDirectory $case -PolicyPath $policyCopy -ExpectedExitCode 0 -ExpectedDiagnostic 'Disabled discoverability: 12 role(s) below their advisory target'))

    $case = New-TestCase 'mapping-split'
    $results.Add((Invoke-NegativeCase -Name 'Shift mapping split' -ThemePath (Join-Path $case 'CosmoraBlueshift.vstheme') -ExpectedDiagnostic 'maps to 2 shifted values' -Mutation {
        param($text)
        [Regex]::Replace($text, '(?s)(<Color Name="urlformat">.*?<Foreground Type="CT_RAW" Source=")[^"]+', '${1}FFFFFFFF', 1)
    }))

    $case = New-TestCase 'mapping-merge'
    $results.Add((Invoke-NegativeCase -Name 'Shift mapping merge' -ThemePath (Join-Path $case 'CosmoraBlueshift.vstheme') -ExpectedDiagnostic 'merges 2 Cosmora source values' -Mutation {
        param($text)
        $text.Replace('FFAEC5F5', 'FFEDF4FF')
    }))

    $results | Select-Object Case, ExitCode, ExpectedExitCode, Diagnostic | Format-Table -AutoSize
    $failedCases = @($results | Where-Object { $_.ExitCode -ne $_.ExpectedExitCode -or -not $_.Diagnostic })
    if ($failedCases.Count -gt 0) {
        foreach ($failedCase in $failedCases) {
            Write-Host "Unexpected result for '$($failedCase.Case)':`n$($failedCase.Output)" -ForegroundColor Red
        }
        throw "$($failedCases.Count) validator regression test(s) failed."
    }

    Write-Host "All $($results.Count) validator regression tests passed." -ForegroundColor Green
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $safePrefix = Join-Path $tempDirectory 'cosmora-theme-validator-'
    if ($resolvedTestRoot.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTestRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

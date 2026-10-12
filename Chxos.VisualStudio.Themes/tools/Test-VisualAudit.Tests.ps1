[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'VisualAudit.Common.psm1'
Import-Module $module -Force
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempBase ('cosmora-visual-audit-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function New-TestBitmap {
    param(
        [string] $Path,
        [int] $Width = 120,
        [int] $Height = 80,
        [Drawing.Color] $Background = [Drawing.Color]::FromArgb(20, 24, 36),
        [Drawing.Color] $Line = [Drawing.Color]::FromArgb(220, 225, 240),
        [int] $LineSpacing = 12
    )
    $bitmap = New-Object Drawing.Bitmap $Width, $Height
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear($Background)
        $pen = New-Object Drawing.Pen $Line, 2
        try {
            for ($x = $LineSpacing; $x -lt $Width; $x += $LineSpacing) {
                $graphics.DrawLine($pen, $x, 0, $x, $Height)
            }
        }
        finally {
            $pen.Dispose()
        }
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function New-ShellHierarchyBitmap {
    param(
        [string] $Path,
        [Drawing.Color] $Top = [Drawing.Color]::FromArgb(16, 24, 32),
        [Drawing.Color] $Workspace = [Drawing.Color]::FromArgb(16, 24, 32),
        [Drawing.Color] $Status = [Drawing.Color]::FromArgb(8, 12, 16)
    )

    $bitmap = New-Object Drawing.Bitmap 160, 100
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear($Workspace)
        $topBrush = New-Object Drawing.SolidBrush $Top
        $statusBrush = New-Object Drawing.SolidBrush $Status
        $controlBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(48, 56, 64))
        try {
            $graphics.FillRectangle($topBrush, 0, 0, 160, 10)
            $graphics.FillRectangle($controlBrush, 8, 2, 18, 4)
            $graphics.FillRectangle($statusBrush, 0, 95, 160, 5)
        }
        finally {
            $topBrush.Dispose()
            $statusBrush.Dispose()
            $controlBrush.Dispose()
        }
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function New-DocumentTabBitmap {
    param(
        [string] $Path,
        [Drawing.Color] $Shell = [Drawing.Color]::FromArgb(16, 24, 32),
        [Drawing.Color] $Channel = [Drawing.Color]::FromArgb(26, 38, 48)
    )

    $bitmap = New-Object Drawing.Bitmap 160, 100
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(10, 14, 20))
        $shellBrush = New-Object Drawing.SolidBrush $Shell
        $channelBrush = New-Object Drawing.SolidBrush $Channel
        $activeTabBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(38, 50, 62))
        try {
            $graphics.FillRectangle($shellBrush, 0, 0, 160, 6)
            $graphics.FillRectangle($channelBrush, 0, 7, 160, 5)
            $graphics.FillRectangle($activeTabBrush, 0, 7, 65, 5)
        }
        finally {
            $shellBrush.Dispose()
            $channelBrush.Dispose()
            $activeTabBrush.Dispose()
        }
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check {
    param([string] $Name, [bool] $Passed, [string] $Detail)
    $checks.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail })
}

try {
    $hashFixturePath = Join-Path $testRoot 'hash-fixture.txt'
    [IO.File]::WriteAllText($hashFixturePath, 'visual-audit-hash-fixture', (New-Object Text.UTF8Encoding($false)))
    $hash = Get-VisualAuditFileHash -Path $hashFixturePath
    Add-Check -Name 'Standalone file hashing' -Passed ($hash -ceq '4ED88609CD3ECA3A686F3EA9E2A99A1430CA5D1900856765B269D5259FA8D92B') -Detail $hash

    $referencePath = Join-Path $testRoot 'reference.png'
    $candidatePath = Join-Path $testRoot 'candidate.png'
    $flatPath = Join-Path $testRoot 'flat.png'
    New-TestBitmap -Path $referencePath
    New-TestBitmap -Path $candidatePath -Line ([Drawing.Color]::FromArgb(160, 170, 190))
    New-TestBitmap -Path $flatPath -Line ([Drawing.Color]::FromArgb(22, 26, 38))

    $metrics = Get-VisualAuditImageMetrics -Path $referencePath -SampleStep 2
    Add-Check -Name 'Image metrics' -Passed ($metrics.Width -eq 120 -and $metrics.Height -eq 80 -and $metrics.Samples -gt 0) -Detail ($metrics | Out-String)

    $comparison = Compare-VisualAuditImages -ReferencePath $referencePath -CandidatePath $candidatePath -Scenario 'synthetic'
    Add-Check -Name 'Matched comparison' -Passed ($comparison.Scenario -eq 'synthetic' -and $comparison.EdgeStrengthRatio -gt 0) -Detail ($comparison | Out-String)

    $flatComparison = Compare-VisualAuditImages -ReferencePath $referencePath -CandidatePath $flatPath -Scenario 'missing-edges'
    Add-Check -Name 'Edge-loss candidate' -Passed (@($flatComparison.Candidates).Count -gt 0) -Detail ($flatComparison | ConvertTo-Json -Depth 5)

    $maskedMetrics = Get-VisualAuditImageMetrics -Path $referencePath -Masks @([pscustomobject]@{ X = 0; Y = 0; Width = 60; Height = 80 })
    Add-Check -Name 'Dynamic-region mask' -Passed ($maskedMetrics.Samples -lt $metrics.Samples) -Detail "masked=$($maskedMetrics.Samples), full=$($metrics.Samples)"

    $validShellPath = Join-Path $testRoot 'shell-valid.png'
    $mismatchedShellPath = Join-Path $testRoot 'shell-mismatched.png'
    $flatStatusPath = Join-Path $testRoot 'shell-flat-status.png'
    New-ShellHierarchyBitmap -Path $validShellPath
    New-ShellHierarchyBitmap -Path $mismatchedShellPath -Workspace ([Drawing.Color]::FromArgb(32, 40, 48))
    New-ShellHierarchyBitmap -Path $flatStatusPath -Status ([Drawing.Color]::FromArgb(16, 24, 32))

    $dominant = Get-VisualAuditDominantColor `
        -Path $validShellPath `
        -Region ([pscustomobject]@{ X = 0; Y = 0; Width = 160; Height = 10 })
    Add-Check -Name 'Dominant region color' -Passed ($dominant.Color -ceq '#101820' -and $dominant.Share -gt 0.8) -Detail ($dominant | ConvertTo-Json -Depth 4)

    $validShell = Get-VisualAuditShellHierarchy -Path $validShellPath
    Add-Check -Name 'Valid shell hierarchy' -Passed (@($validShell.Candidates).Count -eq 0) -Detail ($validShell | ConvertTo-Json -Depth 6)

    $mismatchedShell = Get-VisualAuditShellHierarchy -Path $mismatchedShellPath
    Add-Check -Name 'Shell body mismatch candidate' -Passed (@($mismatchedShell.Candidates | Where-Object { $_ -match 'Workspace dominant color' }).Count -gt 0) -Detail ($mismatchedShell | ConvertTo-Json -Depth 6)

    $flatStatus = Get-VisualAuditShellHierarchy -Path $flatStatusPath
    Add-Check -Name 'Flat status candidate' -Passed (@($flatStatus.Candidates | Where-Object { $_ -match 'not visibly darker' }).Count -gt 0) -Detail ($flatStatus | ConvertTo-Json -Depth 6)

    $validTabsPath = Join-Path $testRoot 'tabs-valid.png'
    $collapsedTabsPath = Join-Path $testRoot 'tabs-collapsed.png'
    $darkTabsPath = Join-Path $testRoot 'tabs-dark.png'
    $excessiveTabsPath = Join-Path $testRoot 'tabs-excessive.png'
    New-DocumentTabBitmap -Path $validTabsPath
    New-DocumentTabBitmap -Path $collapsedTabsPath -Channel ([Drawing.Color]::FromArgb(16, 24, 32))
    New-DocumentTabBitmap -Path $darkTabsPath -Channel ([Drawing.Color]::FromArgb(8, 12, 16))
    New-DocumentTabBitmap -Path $excessiveTabsPath -Channel ([Drawing.Color]::FromArgb(128, 144, 160))

    $validTabs = Get-VisualAuditDocumentTabHierarchy `
        -Path $validTabsPath `
        -ExpectedShellColor '#101820' `
        -ExpectedTabChannelColor '#1A2630'
    Add-Check -Name 'Valid document-tab hierarchy' -Passed (@($validTabs.Candidates).Count -eq 0) -Detail ($validTabs | ConvertTo-Json -Depth 6)

    $collapsedTabs = Get-VisualAuditDocumentTabHierarchy -Path $collapsedTabsPath
    Add-Check -Name 'Collapsed document-tab candidate' -Passed (@($collapsedTabs.Candidates | Where-Object { $_ -match 'collapses into the shell base' }).Count -gt 0) -Detail ($collapsedTabs | ConvertTo-Json -Depth 6)

    $darkTabs = Get-VisualAuditDocumentTabHierarchy -Path $darkTabsPath
    Add-Check -Name 'Dark document-tab candidate' -Passed (@($darkTabs.Candidates | Where-Object { $_ -match 'not visibly lighter' }).Count -gt 0) -Detail ($darkTabs | ConvertTo-Json -Depth 6)

    $excessiveTabs = Get-VisualAuditDocumentTabHierarchy -Path $excessiveTabsPath
    Add-Check -Name 'Excessive document-tab candidate' -Passed (@($excessiveTabs.Candidates | Where-Object { $_ -match 'excessively lighter' }).Count -gt 0) -Detail ($excessiveTabs | ConvertTo-Json -Depth 6)

    $interactionArguments = @{
        NeutralAnchor = '#30343A'
        Rest = '#20242A'
        Hover = '#3A3E44'
        Pressed = '#14181E'
        QuietBorder = '#5A6068'
        PressedBorder = '#AAB0B8'
        FocusBorder = '#8FD7FF'
        SelectedBorder = '#FFAA2B'
        Accent = '#FFAA2B'
    }
    $validInteraction = Get-VisualAuditInteractionHierarchy @interactionArguments
    Add-Check -Name 'Valid neutral interaction hierarchy' -Passed (@($validInteraction.Candidates).Count -eq 0) -Detail ($validInteraction | ConvertTo-Json -Depth 6)

    $collapsedInteractionArguments = $interactionArguments.Clone()
    $collapsedInteractionArguments.Hover = $collapsedInteractionArguments.Rest
    $collapsedInteraction = Get-VisualAuditInteractionHierarchy @collapsedInteractionArguments
    Add-Check -Name 'Collapsed interaction-state candidate' -Passed (@($collapsedInteraction.Candidates | Where-Object { $_ -match 'Resting and hover' }).Count -gt 0) -Detail ($collapsedInteraction | ConvertTo-Json -Depth 6)

    $accentInteractionArguments = $interactionArguments.Clone()
    $accentInteractionArguments.Rest = $accentInteractionArguments.Accent
    $accentInteraction = Get-VisualAuditInteractionHierarchy @accentInteractionArguments
    Add-Check -Name 'Generic accent-leak candidate' -Passed (@($accentInteraction.Candidates | Where-Object { $_ -match 'closer to the accent' }).Count -gt 0) -Detail ($accentInteraction | ConvertTo-Json -Depth 6)

    $weakPressedArguments = $interactionArguments.Clone()
    $weakPressedArguments.PressedBorder = '#25292F'
    $weakPressedInteraction = Get-VisualAuditInteractionHierarchy @weakPressedArguments
    Add-Check -Name 'Weak pressed-input border candidate' -Passed (@($weakPressedInteraction.Candidates | Where-Object { $_ -match 'pressed-input border' }).Count -gt 0) -Detail ($weakPressedInteraction | ConvertTo-Json -Depth 6)

    $weakFocusArguments = $interactionArguments.Clone()
    $weakFocusArguments.FocusBorder = '#30343A'
    $weakFocusInteraction = Get-VisualAuditInteractionHierarchy @weakFocusArguments
    Add-Check -Name 'Weak keyboard-focus candidate' -Passed (@($weakFocusInteraction.Candidates | Where-Object { $_ -match 'keyboard-focus border' }).Count -gt 0) -Detail ($weakFocusInteraction | ConvertTo-Json -Depth 6)

    $lostSelectionArguments = $interactionArguments.Clone()
    $lostSelectionArguments.SelectedBorder = '#5A6068'
    $lostSelectionInteraction = Get-VisualAuditInteractionHierarchy @lostSelectionArguments
    Add-Check -Name 'Lost selected-accent candidate' -Passed (@($lostSelectionInteraction.Candidates | Where-Object { $_ -match 'selected/default-action border' }).Count -gt 0) -Detail ($lostSelectionInteraction | ConvertTo-Json -Depth 6)

    $runtimeArguments = @{
        ScrollbarTrack = '#101820'
        ScrollbarRest = '#687888'
        ScrollbarHover = '#788898'
        ScrollbarPressed = '#98A8B8'
        Editor = '#101820'
        ActiveSelection = '#24506A'
        InactiveSelection = '#1A3040'
        CurrentLine = '#1A2430'
        FindHighlight = '#553514'
        ReferenceHighlight = '#24354A'
        SyntaxForeground = '#F0F4F8'
        Shell = '#101820'
        SolutionTitle = '#182028'
        ControlRest = '#202830'
        FocusBorder = '#8FD7FF'
    }
    $validRuntime = Get-VisualAuditRuntimeStateHierarchy @runtimeArguments
    Add-Check -Name 'Valid runtime highlight hierarchy' -Passed (@($validRuntime.Candidates).Count -eq 0) -Detail ($validRuntime | ConvertTo-Json -Depth 6)

    $collapsedScrollbarArguments = $runtimeArguments.Clone()
    $collapsedScrollbarArguments.ScrollbarRest = $collapsedScrollbarArguments.ScrollbarTrack
    $collapsedScrollbar = Get-VisualAuditRuntimeStateHierarchy @collapsedScrollbarArguments
    Add-Check -Name 'Collapsed scrollbar silhouette candidate' -Passed (@($collapsedScrollbar.Candidates | Where-Object { $_ -match 'resting scrollbar silhouette' }).Count -gt 0) -Detail ($collapsedScrollbar | ConvertTo-Json -Depth 6)

    $weakScrollbarOrderingArguments = $runtimeArguments.Clone()
    $weakScrollbarOrderingArguments.ScrollbarHover = $weakScrollbarOrderingArguments.ScrollbarRest
    $weakScrollbarOrderingArguments.ScrollbarPressed = $weakScrollbarOrderingArguments.ScrollbarHover
    $weakScrollbarOrdering = Get-VisualAuditRuntimeStateHierarchy @weakScrollbarOrderingArguments
    Add-Check -Name 'Scrollbar state-ordering candidate' -Passed (@($weakScrollbarOrdering.Candidates | Where-Object { $_ -match 'ordered visual hierarchy' }).Count -gt 0) -Detail ($weakScrollbarOrdering | ConvertTo-Json -Depth 6)

    $collapsedSelectionArguments = $runtimeArguments.Clone()
    $collapsedSelectionArguments.ActiveSelection = $collapsedSelectionArguments.Editor
    $collapsedSelection = Get-VisualAuditRuntimeStateHierarchy @collapsedSelectionArguments
    Add-Check -Name 'Collapsed active-selection candidate' -Passed (@($collapsedSelection.Candidates | Where-Object { $_ -match 'Active selection' }).Count -gt 0) -Detail ($collapsedSelection | ConvertTo-Json -Depth 6)

    $collapsedCurrentLineArguments = $runtimeArguments.Clone()
    $collapsedCurrentLineArguments.CurrentLine = $collapsedCurrentLineArguments.Editor
    $collapsedCurrentLine = Get-VisualAuditRuntimeStateHierarchy @collapsedCurrentLineArguments
    Add-Check -Name 'Collapsed current-line candidate' -Passed (@($collapsedCurrentLine.Candidates | Where-Object { $_ -match 'Current-line' }).Count -gt 0) -Detail ($collapsedCurrentLine | ConvertTo-Json -Depth 6)

    $weakHighlightArguments = $runtimeArguments.Clone()
    $weakHighlightArguments.SyntaxForeground = $weakHighlightArguments.FindHighlight
    $weakHighlight = Get-VisualAuditRuntimeStateHierarchy @weakHighlightArguments
    Add-Check -Name 'Find/reference text-preservation candidate' -Passed (@($weakHighlight.Candidates | Where-Object { $_ -match 'Find/reference' }).Count -gt 0) -Detail ($weakHighlight | ConvertTo-Json -Depth 6)

    $prominentSolutionTitleArguments = $runtimeArguments.Clone()
    $prominentSolutionTitleArguments.SolutionTitle = '#4DA6E6'
    $prominentSolutionTitle = Get-VisualAuditRuntimeStateHierarchy @prominentSolutionTitleArguments
    Add-Check -Name 'Prominent solution-title candidate' -Passed (@($prominentSolutionTitle.Candidates | Where-Object { $_ -match 'solution-title' }).Count -gt 0) -Detail ($prominentSolutionTitle | ConvertTo-Json -Depth 6)

    $weakRuntimeFocusArguments = $runtimeArguments.Clone()
    $weakRuntimeFocusArguments.FocusBorder = $weakRuntimeFocusArguments.ControlRest
    $weakRuntimeFocus = Get-VisualAuditRuntimeStateHierarchy @weakRuntimeFocusArguments
    Add-Check -Name 'Runtime focus-prominence candidate' -Passed (@($weakRuntimeFocus.Candidates | Where-Object { $_ -match 'keyboard-focus border' }).Count -gt 0) -Detail ($weakRuntimeFocus | ConvertTo-Json -Depth 6)

    $syntaxArguments = @{
        Editor = '#0B0F16'
        InactiveSelection = '#244DA6E6'
        Families = [ordered] @{
            Plain = '#E7EEF8'
            Keyword = '#FF6B9A'
            String = '#7EE6F2'
            Number = '#FACC15'
            Comment = '#A79A87'
            Method = '#FFE066'
            Type = '#B7A7F7'
            Variable = '#72B5FF'
            Operator = '#D4DCE8'
        }
    }
    $validSyntax = Get-VisualAuditSyntaxHierarchy @syntaxArguments
    Add-Check -Name 'Valid labelled syntax hierarchy' -Passed (@($validSyntax.Candidates).Count -eq 0) -Detail ($validSyntax | ConvertTo-Json -Depth 7)

    $typeCollapseArguments = $syntaxArguments.Clone()
    $typeCollapseArguments.Families = [ordered] @{} + $syntaxArguments.Families
    $typeCollapseArguments.Families.Type = $typeCollapseArguments.Families.Plain
    $typeCollapse = Get-VisualAuditSyntaxHierarchy @typeCollapseArguments
    Add-Check -Name 'Type and plain collapse candidate' -Passed (@($typeCollapse.Candidates | Where-Object { $_ -match 'type region collapses' }).Count -gt 0) -Detail ($typeCollapse | ConvertTo-Json -Depth 7)

    $lowChromaArguments = $syntaxArguments.Clone()
    $lowChromaArguments.Families = [ordered] @{
        Plain = '#F0F0F0'; Keyword = '#D8D8D8'; String = '#C8C8C8'; Number = '#E0E0E0';
        Comment = '#A8A8A8'; Method = '#D0D0D0'; Type = '#B8B8B8'; Variable = '#C0C0C0'; Operator = '#B0B0B0'
    }
    $lowChroma = Get-VisualAuditSyntaxHierarchy @lowChromaArguments
    Add-Check -Name 'Low-chroma concentration candidate' -Passed (@($lowChroma.Candidates | Where-Object { $_ -match 'low-chroma neutral lanes' }).Count -gt 0) -Detail ($lowChroma | ConvertTo-Json -Depth 7)

    $methodCollapseArguments = $syntaxArguments.Clone()
    $methodCollapseArguments.Families = [ordered] @{} + $syntaxArguments.Families
    $methodCollapseArguments.Families.Method = $methodCollapseArguments.Families.Type
    $methodCollapse = Get-VisualAuditSyntaxHierarchy @methodCollapseArguments
    Add-Check -Name 'Method and type collapse candidate' -Passed (@($methodCollapse.Candidates | Where-Object { $_ -match 'method region collapses' }).Count -gt 0) -Detail ($methodCollapse | ConvertTo-Json -Depth 7)

    $commentCollapseArguments = $syntaxArguments.Clone()
    $commentCollapseArguments.Families = [ordered] @{} + $syntaxArguments.Families
    $commentCollapseArguments.Families.Comment = $commentCollapseArguments.Families.Operator
    $commentCollapse = Get-VisualAuditSyntaxHierarchy @commentCollapseArguments
    Add-Check -Name 'Comment and operator collapse candidate' -Passed (@($commentCollapse.Candidates | Where-Object { $_ -match 'comment region collapses' }).Count -gt 0) -Detail ($commentCollapse | ConvertTo-Json -Depth 7)

    $selectionLossArguments = $syntaxArguments.Clone()
    $selectionLossArguments.InactiveSelection = '#A04DA6E6'
    $selectionLoss = Get-VisualAuditSyntaxHierarchy @selectionLossArguments
    Add-Check -Name 'Inactive-selection syntax-loss candidate' -Passed (@($selectionLoss.Candidates | Where-Object { $_ -match 'inactive selection' }).Count -gt 0) -Detail ($selectionLoss | ConvertTo-Json -Depth 7)

    $mismatchPath = Join-Path $testRoot 'mismatch.png'
    New-TestBitmap -Path $mismatchPath -Width 100
    $dimensionFailure = $false
    try {
        Compare-VisualAuditImages -ReferencePath $referencePath -CandidatePath $mismatchPath | Out-Null
    }
    catch {
        $dimensionFailure = $_.Exception.Message -match 'dimensions differ'
    }
    Add-Check -Name 'Dimension mismatch failure' -Passed $dimensionFailure -Detail 'Expected a hard failure for mismatched captures.'

    $payloadFailure = $false
    try {
        Assert-VisualAuditPayloadIdentity `
            -Packaged ([ordered] @{ 'Nightglass.pkgdef' = 'AAAA' }) `
            -Installed ([ordered] @{ 'Nightglass.pkgdef' = [pscustomobject]@{ Hash = 'BBBB'; Path = 'fixture' } })
    }
    catch {
        $payloadFailure = $_.Exception.Message -match 'does not match packaged hash'
    }
    Add-Check -Name 'Payload mismatch failure' -Passed $payloadFailure -Detail 'Expected a hard failure for stale installed payloads.'

    $zipPath = Join-Path $testRoot 'fixture.vsix'
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $zip.CreateEntry('Nightglass.pkgdef')
        $writer = New-Object IO.StreamWriter($entry.Open())
        try { $writer.Write('fixture payload') } finally { $writer.Dispose() }
    }
    finally {
        $zip.Dispose()
    }
    $hashes = Get-VsixPkgdefHashes -VsixPath $zipPath
    Add-Check -Name 'VSIX payload hashing' -Passed ($hashes.Count -eq 1 -and $hashes.Contains('Nightglass.pkgdef')) -Detail ($hashes | Out-String)
    Assert-VisualAuditThemeInventory -Packaged $hashes -ExpectedNames @('Nightglass.pkgdef')
    Add-Check -Name 'Exact theme inventory' -Passed $true -Detail 'Expected packaged theme names matched exactly.'

    $inventoryFailure = $false
    try {
        Assert-VisualAuditThemeInventory -Packaged $hashes -ExpectedNames @('Nightglass.pkgdef', 'Pinknoise.pkgdef')
    }
    catch {
        $inventoryFailure = $_.Exception.Message -match 'Expected 2 packaged .pkgdef files; found 1'
    }
    Add-Check -Name 'Theme inventory mismatch failure' -Passed $inventoryFailure -Detail 'Expected a hard failure for a stale packaged-theme count.'

    $reportPath = Join-Path $testRoot 'report.md'
    Write-VisualAuditReport `
        -Path $reportPath `
        -VsixPath $zipPath `
        -RootSuffix 'CosmoraAudit' `
        -Results @($comparison, $flatComparison) `
        -PackagedHashes $hashes `
        -InfrastructureNotes @('Synthetic fixture')
    $report = [IO.File]::ReadAllText($reportPath)
    Add-Check -Name 'Markdown report' -Passed ($report -match '# Automated Visual Theme Audit' -and $report -match 'Synthetic fixture') -Detail $report

    $checks | Format-Table -AutoSize
    $failed = @($checks | Where-Object { -not $_.Passed })
    if ($failed.Count -gt 0) {
        foreach ($check in $failed) {
            Write-Host "Failed '$($check.Name)': $($check.Detail)" -ForegroundColor Red
        }
        throw "$($failed.Count) visual-audit regression test(s) failed."
    }
    Write-Host "All $($checks.Count) visual-audit regression tests passed." -ForegroundColor Green
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $safePrefix = Join-Path $tempBase 'cosmora-visual-audit-'
    if ($resolved.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolved -PathType Container)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

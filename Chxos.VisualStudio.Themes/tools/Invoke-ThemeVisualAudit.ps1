[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $VsixPath,

    [Parameter()]
    [string[]] $ThemeName,

    [string] $Package = 'all-dev',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string] $RootSuffix = 'CosmoraAudit',

    [Parameter()]
    [string] $SolutionPath,

    [Parameter()]
    [string] $OutputDirectory,

    [Parameter()]
    [switch] $ResetProfile,

    [Parameter()]
    [switch] $SkipInstall,

    [Parameter()]
    [switch] $CaptureAllSurfaces
)

$ErrorActionPreference = 'Stop'
$toolsDirectory = $PSScriptRoot
$projectDirectory = Split-Path -Parent $toolsDirectory
$repositoryDirectory = Split-Path -Parent $projectDirectory
$modulePath = Join-Path $toolsDirectory 'VisualAudit.Common.psm1'
$packageInspector = Join-Path $toolsDirectory 'Test-VsixPackage.ps1'
Import-Module $modulePath -Force
Import-Module (Join-Path $toolsDirectory 'RuntimeAcceptance.psm1') -Force
$scenarioManifest = Get-Content (Join-Path $toolsDirectory 'RuntimeScenarios.json') -Raw | ConvertFrom-Json
$requiredCaptureScenarios = @($scenarioManifest | Where-Object Capture -eq 'existing-runner' | ForEach-Object Id)

if ([string]::IsNullOrWhiteSpace($SolutionPath)) {
    $SolutionPath = Join-Path $toolsDirectory 'VisualAuditFixture\VisualAuditFixture.slnx'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path $repositoryDirectory "artifacts\visual-audit\$stamp-vs18"
}

$VsixPath = (Resolve-Path -LiteralPath $VsixPath).Path
$SolutionPath = (Resolve-Path -LiteralPath $SolutionPath).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Import-Module (Join-Path $toolsDirectory 'PackageCatalog.psm1') -Force
$selectedPackage = Get-ThemePackage $Package
$themeCatalog = @(Get-PackageThemes $selectedPackage)
$ThemeName = @(Resolve-PackageThemeNames -Package $selectedPackage -ThemeName $ThemeName)
$allThemes = @($themeCatalog | ForEach-Object Name)
foreach ($requestedTheme in $ThemeName) {
    if ($requestedTheme -ne 'All' -and $requestedTheme -notin $allThemes) { throw "Unknown theme '$requestedTheme'. Use a catalog display name or All." }
}
$documentTabExpectations = @{
    'Amberroot' = [pscustomobject]@{ Shell = '#303228'; Channel = '#36382D' }
    'Aquatoxic' = [pscustomobject]@{ Shell = '#001D20'; Channel = '#072E32' }
    'Biolume' = [pscustomobject]@{ Shell = '#080B09'; Channel = '#111512' }
    'Nullsector' = [pscustomobject]@{ Shell = '#080B12'; Channel = '#0D121A' }
    'Cosmora' = [pscustomobject]@{ Shell = '#090C17'; Channel = '#141825' }
    'Cosmora Blueshift' = [pscustomobject]@{ Shell = '#07101C'; Channel = '#0E192B' }
    'Cosmora Redshift' = [pscustomobject]@{ Shell = '#190C08'; Channel = '#261510' }
    'Cosmora Ultraviolet' = [pscustomobject]@{ Shell = '#150C16'; Channel = '#211522' }
    'Foundation' = [pscustomobject]@{ Shell = '#0E0E11'; Channel = '#151518' }
    'Hardline' = [pscustomobject]@{ Shell = '#080909'; Channel = '#151718' }
    'Nightglass' = [pscustomobject]@{ Shell = '#0B1020'; Channel = '#111827' }
    'Pinknoise' = [pscustomobject]@{ Shell = '#0D0A10'; Channel = '#171019' }
    'Silverphase' = [pscustomobject]@{ Shell = '#0B0F16'; Channel = '#141A24' }
}
$expectedPkgdefNames = @($themeCatalog | ForEach-Object Pkgdef)
if ($ThemeName -contains 'All') {
    $ThemeName = $allThemes
}
$ThemeName = @($ThemeName | Select-Object -Unique)
$ThemeName = @($ThemeName | ForEach-Object {
    $requested = $_
    $allThemes | Where-Object { $_ -eq $requested }
})

function Get-VisualStudioPaths {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
        throw "vswhere.exe was not found at '$vswhere'."
    }
    $instanceJson = & $vswhere -latest -products * -version '[18.0,19.0)' -requires Microsoft.Component.MSBuild -format json
    $instances = @($instanceJson | ConvertFrom-Json)
    if ($instances.Count -ne 1) {
        throw "Expected one Visual Studio 2026 installation; found $($instances.Count)."
    }
    $instance = $instances[0]
    $installationPath = [string] $instance.installationPath
    $createExpInstance = Join-Path $installationPath 'VSSDK\VisualStudioIntegration\Tools\Bin\CreateExpInstance.exe'
    $paths = [pscustomobject]@{
        Installation = $installationPath
        InstallationVersion = [string] $instance.installationVersion
        InstanceId = [string] $instance.instanceId
        Devenv = Join-Path $installationPath 'Common7\IDE\devenv.exe'
        VsixInstaller = Join-Path $installationPath 'Common7\IDE\VSIXInstaller.exe'
        CreateExpInstance = if (Test-Path -LiteralPath $createExpInstance -PathType Leaf) { $createExpInstance } else { $null }
    }
    foreach ($property in @('Devenv', 'VsixInstaller')) {
        if (-not (Test-Path -LiteralPath $paths.$property -PathType Leaf)) {
            throw "Required Visual Studio tool '$property' was not found at '$($paths.$property)'."
        }
    }
    return $paths
}

function Wait-VisualStudioWindow {
    param(
        [Parameter(Mandatory)][Diagnostics.Process] $Process,
        [int] $TimeoutSeconds = 120
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Visual Studio exited with code $($Process.ExitCode) before its main window became available."
        }
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $Process.MainWindowHandle
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Visual Studio did not expose a main window within $TimeoutSeconds seconds."
}

function Wait-VisualStudioAutomationRoot {
    param(
        [Parameter(Mandatory)][Diagnostics.Process] $Process,
        [Parameter(Mandatory)][string] $ExpectedTitleFragment,
        [int] $TimeoutSeconds = 180,
        [int] $StableSeconds = 5
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $candidateHandle = [IntPtr]::Zero
    $stableSince = [DateTime]::MinValue
    do {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Visual Studio exited with code $($Process.ExitCode) before UI Automation became available."
        }

        $handle = $Process.MainWindowHandle
        $title = $Process.MainWindowTitle
        if ($handle -eq [IntPtr]::Zero -or
            [string]::IsNullOrWhiteSpace($title) -or
            $title -notlike "*$ExpectedTitleFragment*") {
            # After an Experimental Instance restart, Process.MainWindowHandle
            # can point at an untitled shell helper even though the visible
            # solution window is ready. Resolve the owned top-level UIA window
            # by process id and expected solution title instead.
            $processCondition = [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::ProcessIdProperty,
                $Process.Id)
            $ownedWindows = [Windows.Automation.AutomationElement]::RootElement.FindAll(
                [Windows.Automation.TreeScope]::Children,
                $processCondition)
            foreach ($ownedWindow in $ownedWindows) {
                $ownedTitle = [string] $ownedWindow.Current.Name
                $ownedHandle = [IntPtr] $ownedWindow.Current.NativeWindowHandle
                if ($ownedHandle -ne [IntPtr]::Zero -and
                    $ownedTitle -like "*$ExpectedTitleFragment*") {
                    $handle = $ownedHandle
                    $title = $ownedTitle
                    break
                }
            }
        }
        if ($handle -eq [IntPtr]::Zero -or
            [string]::IsNullOrWhiteSpace($title) -or
            $title -notlike "*$ExpectedTitleFragment*") {
            $candidateHandle = [IntPtr]::Zero
            $stableSince = [DateTime]::MinValue
        }
        elseif ($handle -ne $candidateHandle) {
            $candidateHandle = $handle
            $stableSince = [DateTime]::UtcNow
        }
        elseif (([DateTime]::UtcNow - $stableSince).TotalSeconds -ge $StableSeconds) {
            try {
                $root = [Windows.Automation.AutomationElement]::FromHandle($handle)
                return [pscustomobject]@{
                    Handle = $handle
                    Root = $root
                }
            }
            catch {
                $candidateHandle = [IntPtr]::Zero
                $stableSince = [DateTime]::MinValue
            }
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Visual Studio did not expose a stable UI Automation root within $TimeoutSeconds seconds."
}

function Get-AutomationDescendant {
    param(
        [Parameter(Mandatory)][Windows.Automation.AutomationElement] $Root,
        [Parameter(Mandatory)][string] $Name,
        [switch] $Exact,
        [Windows.Automation.ControlType] $ControlType,
        [int] $TimeoutSeconds = 15
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if ($Exact) {
            $condition = [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::NameProperty,
                $Name)
            if ($null -ne $ControlType) {
                $typeCondition = [Windows.Automation.PropertyCondition]::new(
                    [Windows.Automation.AutomationElement]::ControlTypeProperty,
                    $ControlType)
                $condition = [Windows.Automation.AndCondition]::new(
                    [Windows.Automation.Condition[]] @($condition, $typeCondition))
            }
            $element = $Root.FindFirst(
                [Windows.Automation.TreeScope]::Descendants,
                $condition)
            if ($null -ne $element) {
                return $element
            }
        }
        else {
            $elements = $Root.FindAll(
                [Windows.Automation.TreeScope]::Descendants,
                [Windows.Automation.Condition]::TrueCondition)
            foreach ($element in $elements) {
                if ([string] $element.Current.Name -like "*$Name*") {
                    return $element
                }
            }
        }
        Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}

function Invoke-AutomationElement {
    param([Parameter(Mandatory)][Windows.Automation.AutomationElement] $Element)
    $pattern = $null
    if ($Element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref] $pattern)) {
        ([Windows.Automation.InvokePattern] $pattern).Invoke()
        return
    }
    if ($Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref] $pattern)) {
        ([Windows.Automation.SelectionItemPattern] $pattern).Select()
        return
    }
    if ($Element.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern, [ref] $pattern)) {
        ([Windows.Automation.ExpandCollapsePattern] $pattern).Expand()
        return
    }
    if ($Element.TryGetCurrentPattern([Windows.Automation.LegacyIAccessiblePattern]::Pattern, [ref] $pattern)) {
        ([Windows.Automation.LegacyIAccessiblePattern] $pattern).DoDefaultAction()
        return
    }
    throw "Automation element '$($Element.Current.Name)' is not invokable or selectable."
}

function Invoke-AutomationElementByClick {
    param([Parameter(Mandatory)][Windows.Automation.AutomationElement] $Element)

    $bounds = $Element.Current.BoundingRectangle
    if ($bounds.IsEmpty -or $bounds.Width -lt 2 -or $bounds.Height -lt 2) {
        throw "Automation element '$($Element.Current.Name)' does not expose clickable bounds."
    }
    [VisualAuditNativeMethods]::SetCursorPos(
        [int] [Math]::Round($bounds.Left + ($bounds.Width / 2)),
        [int] [Math]::Round($bounds.Top + ($bounds.Height / 2))) | Out-Null
    [VisualAuditNativeMethods]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [VisualAuditNativeMethods]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}

function Open-VisualStudioMenuItem {
    param(
        [Parameter(Mandatory)][Windows.Automation.AutomationElement] $Root,
        [Parameter(Mandatory)][string] $Menu,
        [Parameter(Mandatory)][string] $Item
    )
    $menuElement = Get-AutomationDescendant `
        -Root $Root `
        -Name $Menu `
        -Exact `
        -ControlType ([Windows.Automation.ControlType]::MenuItem)
    if ($null -eq $menuElement) {
        throw "Visual Studio menu '$Menu' was not found."
    }
    # Mouse activation avoids an occasional Visual Studio 2026 UI Automation
    # InvokePattern deadlock observed after a terminal tool window was opened.
    Invoke-AutomationElementByClick -Element $menuElement
    Start-Sleep -Milliseconds 400
    $itemElement = Get-AutomationDescendant `
        -Root $Root `
        -Name $Item `
        -Exact `
        -ControlType ([Windows.Automation.ControlType]::MenuItem)
    if ($null -eq $itemElement) {
        [Windows.Forms.SendKeys]::SendWait('{ESC}')
        throw "Visual Studio menu item '$Menu > $Item' was not found."
    }
    Invoke-AutomationElementByClick -Element $itemElement
}

function Set-VisualStudioTheme {
    param(
        [Parameter(Mandatory)][Windows.Automation.AutomationElement] $Root,
        [Parameter(Mandatory)][string] $Name
    )
    # A newly created profile can expose its main HWND before the shell menu is
    # available. Treat the menu, rather than the window handle, as readiness.
    $tools = Get-AutomationDescendant `
        -Root $Root `
        -Name 'Tools' `
        -Exact `
        -ControlType ([Windows.Automation.ControlType]::MenuItem) `
        -TimeoutSeconds 120
    if ($null -eq $tools) {
        throw "Visual Studio menu 'Tools' was not found."
    }
    Invoke-AutomationElement -Element $tools
    Start-Sleep -Milliseconds 350

    $themeMenu = Get-AutomationDescendant `
        -Root $Root `
        -Name 'Theme' `
        -Exact `
        -ControlType ([Windows.Automation.ControlType]::MenuItem)
    if ($null -eq $themeMenu) {
        [Windows.Forms.SendKeys]::SendWait('{ESC}')
        throw "Visual Studio menu 'Tools > Theme' was not found."
    }
    Invoke-AutomationElement -Element $themeMenu
    Start-Sleep -Milliseconds 350

    $themeItem = Get-AutomationDescendant `
        -Root $Root `
        -Name $Name `
        -Exact `
        -ControlType ([Windows.Automation.ControlType]::MenuItem) `
        -TimeoutSeconds 10
    if ($null -eq $themeItem) {
        [Windows.Forms.SendKeys]::SendWait('{ESC}')
        throw "Theme '$Name' was not found in the Tools > Theme menu."
    }
    Invoke-AutomationElement -Element $themeItem
    Start-Sleep -Seconds 2
}

function Open-AuditFile {
    param(
        [Parameter(Mandatory)][string] $Devenv,
        [Parameter(Mandatory)][string] $RootSuffix,
        [Parameter(Mandatory)][string] $Path
    )
    Start-Process -FilePath $Devenv -ArgumentList @('/RootSuffix', $RootSuffix, '/Edit', $Path) -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 2
}

function Close-AllAuditDocuments {
    param(
        [Parameter(Mandatory)][IntPtr] $WindowHandle,
        [Parameter(Mandatory)][Windows.Automation.AutomationElement] $Root,
        [Parameter(Mandatory)][string] $Devenv,
        [Parameter(Mandatory)][string] $RootSuffix
    )

    [VisualAuditNativeMethods]::SetForegroundWindow($WindowHandle) | Out-Null
    Set-AuditPointerRelative -WindowHandle $WindowHandle -X 650 -Y 420
    [VisualAuditNativeMethods]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [VisualAuditNativeMethods]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    try {
        Open-VisualStudioMenuItem -Root $Root -Menu 'Window' -Item 'Close All Documents'
        Start-Sleep -Seconds 1
        return 'Window > Close All Documents'
    }
    catch {
        # VS 2026 does not consistently expose the item through UI Automation.
        # Execute the named VS command against this root suffix; unlike the old
        # Ctrl+K, Ctrl+W assumption, this does not open the Bookmarks window.
        $commandHelper = Start-Process `
            -FilePath $Devenv `
            -ArgumentList @('/RootSuffix', $RootSuffix, '/Command', 'Window.CloseAllDocuments') `
            -WindowStyle Hidden -PassThru
        try {
            if (-not $commandHelper.WaitForExit(3000)) {
                # This command can start a second hidden IDE instead of routing
                # to the running profile. Never accumulate one helper per theme.
                Stop-Process -Id $commandHelper.Id -Force -ErrorAction SilentlyContinue
                Write-Warning 'Close All Documents helper did not exit; stopped that helper. Document-state verification remains required.'
            }
        }
        finally { $commandHelper.Dispose() }
        return 'devenv /Command fallback (document state must be verified)'
    }
}

function Get-AuditScenarioMasks {
    param([Parameter(Mandatory)][string] $Scenario)

    $masks = New-Object System.Collections.Generic.List[object]
    # Account state, update badges, and notification chrome are machine-specific.
    $masks.Add([pscustomobject]@{ X = 1280; Y = 0; Width = 320; Height = 110 })
    if ($Scenario -eq 'extension-manager') {
        # Extension detail pages are remote/transient. Keep the navigation, list,
        # summary, separators, and outer pane geometry available for comparison.
        $masks.Add([pscustomobject]@{ X = 650; Y = 330; Width = 950; Height = 670 })
    }
    return $masks.ToArray()
}

function Set-AuditPointerRelative {
    param(
        [Parameter(Mandatory)][IntPtr] $WindowHandle,
        [Parameter(Mandatory)][int] $X,
        [Parameter(Mandatory)][int] $Y
    )

    $rectangle = New-Object VisualAuditNativeMethods+RECT
    if (-not [VisualAuditNativeMethods]::GetWindowRect($WindowHandle, [ref] $rectangle)) {
        throw 'Could not read the Visual Studio window rectangle for interaction capture.'
    }
    $width = [Math]::Max(1, $rectangle.Right - $rectangle.Left)
    $height = [Math]::Max(1, $rectangle.Bottom - $rectangle.Top)
    $scaledX = [int] [Math]::Round($X * ($width / 1600.0))
    $scaledY = [int] [Math]::Round($Y * ($height / 1000.0))
    [VisualAuditNativeMethods]::SetCursorPos(
        $rectangle.Left + [Math]::Min($width - 1, [Math]::Max(0, $scaledX)),
        $rectangle.Top + [Math]::Min($height - 1, [Math]::Max(0, $scaledY))) | Out-Null
    Start-Sleep -Milliseconds 600
}

function Capture-AuditScenarios {
    param(
        [Parameter(Mandatory)][string] $Theme,
        [Parameter(Mandatory)][string] $Prefix,
        [Parameter(Mandatory)][IntPtr] $WindowHandle,
        [Parameter(Mandatory)][Windows.Automation.AutomationElement] $Root,
        [Parameter(Mandatory)][pscustomobject] $Paths
    )

    $captures = [ordered] @{}
    Open-AuditFile -Devenv $Paths.Devenv -RootSuffix $RootSuffix -Path (Join-Path (Split-Path -Parent $SolutionPath) 'ThemeSample.cs')
    [VisualAuditNativeMethods]::SetForegroundWindow($WindowHandle) | Out-Null
    [Windows.Forms.SendKeys]::SendWait('^%l')
    Start-Sleep -Seconds 1
    $path = Join-Path $OutputDirectory "$Prefix-main-shell.png"
    Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
    $captures['main-shell'] = $path

    $closeMethod = Close-AllAuditDocuments `
        -WindowHandle $WindowHandle `
        -Root $Root `
        -Devenv $Paths.Devenv `
        -RootSuffix $RootSuffix
    Write-Host "  Closed documents using $closeMethod."
    $remainingDocument = $null
    foreach ($documentName in @(
        'ThemeSample.cs',
        'ThemeSample.razor',
        'theme-sample.css',
        'theme-sample.html',
        'theme-sample.json',
        'theme-sample.md',
        'theme-sample.xml'
    )) {
        $remainingDocument = Get-AutomationDescendant `
            -Root $Root `
            -Name $documentName `
            -Exact `
            -ControlType ([Windows.Automation.ControlType]::TabItem) `
            -TimeoutSeconds 1
        if ($null -ne $remainingDocument) { break }
    }
    if ($null -eq $remainingDocument) {
        $path = Join-Path $OutputDirectory "$Prefix-empty-workspace.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['empty-workspace'] = $path
    }
    else {
        Write-Warning "Empty-workspace capture was skipped because document tab '$($remainingDocument.Current.Name)' remained open."
    }

    foreach ($name in @('ThemeSample.cs', 'ThemeSample.razor', 'theme-sample.css')) {
        Open-AuditFile -Devenv $Paths.Devenv -RootSuffix $RootSuffix -Path (Join-Path (Split-Path -Parent $SolutionPath) $name)
    }
    $path = Join-Path $OutputDirectory "$Prefix-document-tabs.png"
    Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
    $captures['document-tabs'] = $path

    foreach ($file in @(
        @{ Scenario = 'csharp'; Name = 'ThemeSample.cs' },
        @{ Scenario = 'razor'; Name = 'ThemeSample.razor' },
        @{ Scenario = 'html'; Name = 'theme-sample.html' },
        @{ Scenario = 'css'; Name = 'theme-sample.css' },
        @{ Scenario = 'json'; Name = 'theme-sample.json' },
        @{ Scenario = 'xml'; Name = 'theme-sample.xml' },
        @{ Scenario = 'markdown'; Name = 'theme-sample.md' }
    )) {
        Open-AuditFile -Devenv $Paths.Devenv -RootSuffix $RootSuffix -Path (Join-Path (Split-Path -Parent $SolutionPath) $file.Name)
        # The isolated VS 18.x window exposes its active document in its title.
        # A successful /Edit launch alone does not establish that the requested
        # document became active. Missing states must not enter image comparison.
        $expectedTitleFragment = ' - ' + $file.Name + ' - '
        $observedTitle = [string] $Root.Current.Name
        if ($observedTitle.IndexOf($expectedTitleFragment, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            Write-Warning "Scenario '$($file.Scenario)' is invalid: expected active document '$($file.Name)', observed '$observedTitle'."
            continue
        }
        $path = Join-Path $OutputDirectory "$Prefix-$($file.Scenario).png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures[$file.Scenario] = $path
    }

    [VisualAuditNativeMethods]::SetForegroundWindow($WindowHandle) | Out-Null
    [Windows.Forms.SendKeys]::SendWait('^%o')
    Start-Sleep -Seconds 1
    $path = Join-Path $OutputDirectory "$Prefix-output.png"
    Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
    $captures['output'] = $path

    if ($CaptureAllSurfaces) {
        $fixtureRoot = Split-Path -Parent $SolutionPath
        Open-AuditFile -Devenv $Paths.Devenv -RootSuffix $RootSuffix -Path (Join-Path $fixtureRoot 'ThemeSample.cs')
        [VisualAuditNativeMethods]::SetForegroundWindow($WindowHandle) | Out-Null
        [Windows.Forms.SendKeys]::SendWait('^{HOME}')
        Start-Sleep -Milliseconds 400
        $path = Join-Path $OutputDirectory "$Prefix-editor-current-line.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['editor-current-line'] = $path

        [Windows.Forms.SendKeys]::SendWait('^f')
        [Windows.Forms.SendKeys]::SendWait('configuration')
        [Windows.Forms.SendKeys]::SendWait('{ENTER}{ESC}')
        Start-Sleep -Milliseconds 500
        $path = Join-Path $OutputDirectory "$Prefix-editor-find.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['editor-find'] = $path

        [Windows.Forms.SendKeys]::SendWait('^f')
        [Windows.Forms.SendKeys]::SendWait('committed')
        [Windows.Forms.SendKeys]::SendWait('{ENTER}{ESC}{LEFT}')
        Start-Sleep -Milliseconds 700
        $path = Join-Path $OutputDirectory "$Prefix-editor-reference.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['editor-reference'] = $path

        [Windows.Forms.SendKeys]::SendWait('{HOME}+{END}')
        Start-Sleep -Milliseconds 400
        $path = Join-Path $OutputDirectory "$Prefix-editor-active-selection.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['editor-active-selection'] = $path

        [Windows.Forms.SendKeys]::SendWait('^%l')
        Start-Sleep -Milliseconds 500
        $path = Join-Path $OutputDirectory "$Prefix-editor-inactive-selection.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['editor-inactive-selection'] = $path

        foreach ($highlightFixture in @(
            @{ Scenario = 'razor-find'; File = 'ThemeSample.razor'; Search = 'State' },
            @{ Scenario = 'css-find'; File = 'theme-sample.css'; Search = 'audit-accent' },
            @{ Scenario = 'html-find'; File = 'theme-sample.html'; Search = 'audit-card' }
        )) {
            Open-AuditFile -Devenv $Paths.Devenv -RootSuffix $RootSuffix -Path (Join-Path $fixtureRoot $highlightFixture.File)
            [VisualAuditNativeMethods]::SetForegroundWindow($WindowHandle) | Out-Null
            [Windows.Forms.SendKeys]::SendWait('^f')
            [Windows.Forms.SendKeys]::SendWait([string] $highlightFixture.Search)
            [Windows.Forms.SendKeys]::SendWait('{ENTER}{ESC}')
            Start-Sleep -Milliseconds 450
            $path = Join-Path $OutputDirectory "$Prefix-$($highlightFixture.Scenario).png"
            Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
            $captures[$highlightFixture.Scenario] = $path
        }

        Set-AuditPointerRelative -WindowHandle $WindowHandle -X 800 -Y 520
        $path = Join-Path $OutputDirectory "$Prefix-solution-title-rest.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['solution-title-rest'] = $path

        Set-AuditPointerRelative -WindowHandle $WindowHandle -X 800 -Y 20
        $path = Join-Path $OutputDirectory "$Prefix-solution-title-hover.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['solution-title-hover'] = $path

        $solutionName = [IO.Path]::GetFileNameWithoutExtension($SolutionPath)
        $solutionTitle = Get-AutomationDescendant -Root $Root -Name $solutionName -Exact
        if ($null -ne $solutionTitle) {
            try {
                $solutionTitle.SetFocus()
                Start-Sleep -Milliseconds 500
                $path = Join-Path $OutputDirectory "$Prefix-solution-title-focus.png"
                Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
                $captures['solution-title-focus'] = $path
            }
            catch {
                Write-Warning "Optional solution-title focus scenario was unavailable: $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "Optional solution-title focus scenario could not find '$solutionName'."
        }

        try {
            $alternateWindow = Get-Process |
                Where-Object {
                    $_.MainWindowHandle -ne [IntPtr]::Zero -and
                    $_.MainWindowHandle -ne $WindowHandle -and
                    $_.ProcessName -notin @('devenv', 'powershell', 'pwsh')
                } |
                Select-Object -First 1
            if ($null -eq $alternateWindow) {
                throw 'No alternate application window was available.'
            }
            [VisualAuditNativeMethods]::SetForegroundWindow($alternateWindow.MainWindowHandle) | Out-Null
            Start-Sleep -Milliseconds 500
            $path = Join-Path $OutputDirectory "$Prefix-solution-title-inactive.png"
            Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
            $captures['solution-title-inactive'] = $path
        }
        catch {
            Write-Warning "Optional solution-title inactive-window scenario was unavailable: $($_.Exception.Message)"
        }
        finally {
            [VisualAuditNativeMethods]::SetForegroundWindow($WindowHandle) | Out-Null
        }

        try {
            try {
                Open-VisualStudioMenuItem -Root $Root -Menu 'View' -Item 'Class View'
            }
            catch {
                [VisualAuditNativeMethods]::SetForegroundWindow($WindowHandle) | Out-Null
                [Windows.Forms.SendKeys]::SendWait('^+c')
            }
            Start-Sleep -Seconds 1
            $classView = Get-AutomationDescendant -Root $Root -Name 'Class View' -Exact
            if ($null -eq $classView) {
                throw "Neither View > Class View nor the Ctrl+Shift+C fallback exposed Class View."
            }
            $classSearch = $classView.FindFirst(
                [Windows.Automation.TreeScope]::Descendants,
                [Windows.Automation.PropertyCondition]::new(
                    [Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [Windows.Automation.ControlType]::Edit))
            if ($null -ne $classSearch) {
                Invoke-AutomationElementByClick -Element $classSearch
                [Windows.Forms.SendKeys]::SendWait('^a{BACKSPACE}')
                Start-Sleep -Milliseconds 300
            }
            # The project node can be virtualized and omit ExpandCollapsePattern.
            # Click the live disclosure glyph (rather than assuming a fixed
            # desktop position), then focus the row before using tree-native
            # expand-subtree keys.
            $projectNode = Get-AutomationDescendant `
                -Root $classView `
                -Name 'VisualAuditFixture' `
                -Exact `
                -ControlType ([Windows.Automation.ControlType]::TreeItem) `
                -TimeoutSeconds 5
            if ($null -ne $projectNode) {
                $projectBounds = $projectNode.Current.BoundingRectangle
                [VisualAuditNativeMethods]::SetCursorPos(
                    [int] [Math]::Round($projectBounds.Left - 12),
                    [int] [Math]::Round($projectBounds.Top + ($projectBounds.Height / 2))) | Out-Null
                [VisualAuditNativeMethods]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                [VisualAuditNativeMethods]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
                Start-Sleep -Milliseconds 300
                Invoke-AutomationElementByClick -Element $projectNode
            }
            else {
                $classBounds = $classView.Current.BoundingRectangle
                [VisualAuditNativeMethods]::SetCursorPos(
                    [int] [Math]::Round($classBounds.Left + [Math]::Min(90, $classBounds.Width / 3)),
                    [int] [Math]::Round($classBounds.Top + [Math]::Min(95, $classBounds.Height / 4))) | Out-Null
                [VisualAuditNativeMethods]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                [VisualAuditNativeMethods]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
            }
            [Windows.Forms.SendKeys]::SendWait('{RIGHT}')
            [Windows.Forms.SendKeys]::SendWait('{MULTIPLY}')
            Start-Sleep -Milliseconds 500
            # Expanding the project materializes its namespace as the last
            # visible child. Focus that namespace and expand its descendants so
            # the intentionally dense fixture reliably exposes a scrollbar.
            [Windows.Forms.SendKeys]::SendWait('{END}')
            [Windows.Forms.SendKeys]::SendWait('{RIGHT}')
            [Windows.Forms.SendKeys]::SendWait('{MULTIPLY}')
            Start-Sleep -Milliseconds 500
            for ($pass = 0; $pass -lt 4; $pass++) {
                $treeItems = $Root.FindAll(
                    [Windows.Automation.TreeScope]::Descendants,
                    [Windows.Automation.PropertyCondition]::new(
                        [Windows.Automation.AutomationElement]::ControlTypeProperty,
                        [Windows.Automation.ControlType]::TreeItem))
                $expandedAny = $false
                foreach ($treeItem in $treeItems) {
                    try {
                        $expandPattern = $treeItem.GetCurrentPattern(
                            [Windows.Automation.ExpandCollapsePattern]::Pattern)
                        if ($expandPattern.Current.ExpandCollapseState -eq
                            [Windows.Automation.ExpandCollapseState]::Collapsed) {
                            $expandPattern.Expand()
                            $expandedAny = $true
                        }
                    }
                    catch {
                        # Leaf items and virtualized nodes may not expose the pattern.
                    }
                }
                if (-not $expandedAny) { break }
                Start-Sleep -Milliseconds 350
            }
            $classBounds = $classView.Current.BoundingRectangle
            [VisualAuditNativeMethods]::SetCursorPos(
                [int] [Math]::Round($classBounds.Left + ($classBounds.Width / 2)),
                [int] [Math]::Round($classBounds.Top + ($classBounds.Height / 2))) | Out-Null
            Start-Sleep -Milliseconds 600
            $path = Join-Path $OutputDirectory "$Prefix-class-view-scrollbar-rest.png"
            Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
            $captures['class-view-scrollbar-rest'] = $path

            [VisualAuditNativeMethods]::SetCursorPos(
                [int] [Math]::Round($classBounds.Right - 8),
                [int] [Math]::Round($classBounds.Top + ($classBounds.Height / 2))) | Out-Null
            Start-Sleep -Milliseconds 600
            $path = Join-Path $OutputDirectory "$Prefix-class-view-scrollbar-hover.png"
            Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
            $captures['class-view-scrollbar-hover'] = $path

            try {
                [VisualAuditNativeMethods]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                Start-Sleep -Milliseconds 300
                $path = Join-Path $OutputDirectory "$Prefix-class-view-scrollbar-pressed.png"
                Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
                $captures['class-view-scrollbar-pressed'] = $path
            }
            finally {
                [VisualAuditNativeMethods]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
            }
        }
        catch {
            [Windows.Forms.SendKeys]::SendWait('{ESC}')
            Write-Warning "Optional Class View scrollbar scenarios were unavailable: $($_.Exception.Message)"
        }

        Set-AuditPointerRelative -WindowHandle $WindowHandle -X 800 -Y 520
        $path = Join-Path $OutputDirectory "$Prefix-interaction-rest.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['interaction-rest'] = $path

        Set-AuditPointerRelative -WindowHandle $WindowHandle -X 600 -Y 55
        $path = Join-Path $OutputDirectory "$Prefix-interaction-toolbar-hover.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['interaction-toolbar-hover'] = $path

        Set-AuditPointerRelative -WindowHandle $WindowHandle -X 70 -Y 945
        $path = Join-Path $OutputDirectory "$Prefix-interaction-zoom-hover.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['interaction-zoom-hover'] = $path

        [VisualAuditNativeMethods]::SetForegroundWindow($WindowHandle) | Out-Null
        [Windows.Forms.SendKeys]::SendWait('{TAB}')
        Start-Sleep -Milliseconds 600
        $path = Join-Path $OutputDirectory "$Prefix-interaction-keyboard-focus.png"
        Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
        $captures['interaction-keyboard-focus'] = $path

        foreach ($surface in @(
            @{ Menu = 'View'; Item = 'Terminal'; Scenario = 'developer-powershell'; CloseDocument = $false },
            @{ Menu = 'Extensions'; Item = 'Manage Extensions'; Scenario = 'extension-manager'; CloseDocument = $true },
            @{ Menu = 'Tools'; Item = 'Options'; Scenario = 'options'; CloseDocument = $true }
        )) {
            try {
                Open-VisualStudioMenuItem -Root $Root -Menu $surface.Menu -Item $surface.Item
                Start-Sleep -Seconds 2
                $path = Join-Path $OutputDirectory "$Prefix-$($surface.Scenario).png"
                Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
                $captures[$surface.Scenario] = $path
                if ($surface.CloseDocument) {
                    [Windows.Forms.SendKeys]::SendWait('^{F4}')
                }
                else {
                    [Windows.Forms.SendKeys]::SendWait('{ESC}')
                }
                Start-Sleep -Milliseconds 500
            }
            catch {
                [Windows.Forms.SendKeys]::SendWait('{ESC}')
                Write-Warning "Optional visual-audit scenario '$($surface.Scenario)' was unavailable: $($_.Exception.Message)"
            }
        }

        $toolsMenu = Get-AutomationDescendant `
            -Root $Root `
            -Name 'Tools' `
            -Exact `
            -ControlType ([Windows.Automation.ControlType]::MenuItem)
        if ($null -ne $toolsMenu) {
            Invoke-AutomationElement -Element $toolsMenu
            Start-Sleep -Milliseconds 500
            $path = Join-Path $OutputDirectory "$Prefix-menu.png"
            Save-WindowScreenshot -WindowHandle $WindowHandle -Path $path
            $captures['menu'] = $path
            [Windows.Forms.SendKeys]::SendWait('{ESC}')
        }
    }
    return $captures
}

$paths = Get-VisualStudioPaths
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $packageInspector -VsixPath $VsixPath -Package $Package
if ($LASTEXITCODE -ne 0) {
    throw "VSIX package inspection failed for '$VsixPath'."
}
$packagedHashes = Get-VsixPkgdefHashes -VsixPath $VsixPath
Assert-VisualAuditThemeInventory -Packaged $packagedHashes -ExpectedNames $expectedPkgdefNames

$profilePattern = Join-Path $env:LOCALAPPDATA "Microsoft\VisualStudio\*$RootSuffix*"
$profileExists = @(Get-Item -Path $profilePattern -ErrorAction SilentlyContinue).Count -gt 0
if ($ResetProfile) {
    if ([string]::IsNullOrWhiteSpace($paths.CreateExpInstance)) {
        throw "Visual Studio 2026 does not provide CreateExpInstance.exe; -ResetProfile is unavailable. Choose a new RootSuffix instead."
    }
    & $paths.CreateExpInstance /Reset '/VSInstance=18.0' "/RootSuffix=$RootSuffix"
    if ($LASTEXITCODE -ne 0) { throw "CreateExpInstance /Reset failed with exit code $LASTEXITCODE." }
}
elseif (-not $profileExists -and -not [string]::IsNullOrWhiteSpace($paths.CreateExpInstance)) {
    & $paths.CreateExpInstance /Create '/VSInstance=18.0' "/RootSuffix=$RootSuffix"
    if ($LASTEXITCODE -ne 0) { throw "CreateExpInstance /Create failed with exit code $LASTEXITCODE." }
}

if (-not $SkipInstall) {
    $installerLog = Join-Path $OutputDirectory 'vsix-install.log'
    $installer = Start-Process -FilePath $paths.VsixInstaller `
        -ArgumentList @('/quiet', "/instanceIds:$($paths.InstanceId)", "/rootSuffix:$RootSuffix", "/logFile:$installerLog", $VsixPath) `
        -Wait -PassThru -WindowStyle Hidden
    if ($installer.ExitCode -ne 0) {
        throw "VSIXInstaller failed with exit code $($installer.ExitCode). See '$installerLog'."
    }

    # A newly installed data-only VSIX can exist on disk before its pkgdef
    # registrations are incorporated into an Experimental Instance's cache.
    # Visual Studio 2026 refreshes that suffix-scoped cache through
    # /UpdateConfiguration; normal, Exp, and other profiles remain untouched.
    $configurationSwitch = '/UpdateConfiguration'
    $setup = Start-Process -FilePath $paths.Devenv `
        -ArgumentList @('/RootSuffix', $RootSuffix, $configurationSwitch) `
        -Wait -PassThru -WindowStyle Hidden
    if ($setup.ExitCode -ne 0) {
        throw "Visual Studio $configurationSwitch failed for root suffix '$RootSuffix' with exit code $($setup.ExitCode)."
    }
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
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
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
}
'@
}

$visualStudio = Start-Process -FilePath $paths.Devenv -ArgumentList @('/RootSuffix', $RootSuffix, $SolutionPath) -PassThru
try {
    # Wait for a named, stable handle that UI Automation can bind before moving
    # or capturing the shell.
    $expectedWindowTitle = [IO.Path]::GetFileNameWithoutExtension($SolutionPath)
    $automationWindow = Wait-VisualStudioAutomationRoot `
        -Process $visualStudio `
        -ExpectedTitleFragment $expectedWindowTitle
}
catch {
    if (-not $visualStudio.HasExited) {
        Stop-Process -Id $visualStudio.Id -Force -ErrorAction SilentlyContinue
    }
    throw
}
$windowHandle = $automationWindow.Handle
[VisualAuditNativeMethods]::MoveWindow($windowHandle, 40, 40, 1600, 1000, $true) | Out-Null
[VisualAuditNativeMethods]::SetForegroundWindow($windowHandle) | Out-Null
Write-Host "Visual Studio automation root is ready (HWND $windowHandle)."

$exactProfile = Join-Path $env:LOCALAPPDATA "Microsoft/VisualStudio/18.0_$($paths.InstanceId)$RootSuffix"
$installedHashes = Get-InstalledPkgdefHashes -RootSuffix $RootSuffix -ProfileDirectory $exactProfile -Names @($packagedHashes.Keys) -ExtensionIdentity $selectedPackage.Identity
Assert-VisualAuditPayloadIdentity -Packaged $packagedHashes -Installed $installedHashes
Write-Host 'Installed theme payload matches the inspected VSIX.'
[ordered]@{
    SchemaVersion = 2
    PackageKey = $Package
    PackageIdentity = $selectedPackage.Identity
    PackageVersion = $selectedPackage.Version
    Themes = @($themeCatalog | ForEach-Object Name)
    VsixSha256 = (Get-FileHash -LiteralPath $VsixPath -Algorithm SHA256).Hash
    InstallationVersion = $paths.InstallationVersion
    RootSuffix = $RootSuffix
    PackagedHashes = $packagedHashes
    InstalledHashes = $installedHashes
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'runtime-environment.json') -Encoding UTF8

$root = $automationWindow.Root
$referenceCaptures = [ordered]@{}
$captureCoverage = New-Object System.Collections.Generic.List[object]
foreach ($theme in $ThemeName) {
    foreach ($scenario in $requiredCaptureScenarios) {
        $captureCoverage.Add([pscustomobject]@{ Theme=$theme; Scenario=$scenario; Status='skipped'; Missing='Not reached by capture run.' })
    }
}
$captureCoverage | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'capture-coverage.json') -Encoding UTF8
$results = New-Object System.Collections.Generic.List[object]
$infrastructureNotes = New-Object System.Collections.Generic.List[string]
try {
    Write-Host 'Capturing the built-in Dark reference.'
    Set-VisualStudioTheme -Root $root -Name 'Dark'
    $referenceCaptures = Capture-AuditScenarios -Theme 'Dark' -Prefix 'dark' -WindowHandle $windowHandle -Root $root -Paths $paths

    foreach ($theme in $ThemeName) {
        Write-Host "Capturing theme '$theme'."
        Set-VisualStudioTheme -Root $root -Name $theme
        $prefix = $theme.ToLowerInvariant().Replace(' ', '-')
        $candidateCaptures = Capture-AuditScenarios -Theme $theme -Prefix $prefix -WindowHandle $windowHandle -Root $root -Paths $paths
        foreach ($capture in @(Get-CaptureCompleteness -RequiredScenarios $requiredCaptureScenarios -Reference $referenceCaptures -Candidate $candidateCaptures)) {
            $coverageRow = $captureCoverage | Where-Object { $_.Theme -ceq $theme -and $_.Scenario -ceq $capture.Scenario } | Select-Object -First 1
            $coverageRow.Status = $capture.Status
            $coverageRow.Missing = $capture.Missing
            $scenario = $capture.Scenario
            if ($capture.Status -ne 'captured') {
                $infrastructureNotes.Add("$theme / $scenario missing $($capture.Missing); required scenario is invalid.")
                continue
            }
            $comparison = Compare-VisualAuditImages `
                -ReferencePath $referenceCaptures[$scenario] `
                -CandidatePath $candidateCaptures[$scenario] `
                -Masks @(Get-AuditScenarioMasks -Scenario $scenario) `
                -Scenario "$theme / $scenario"
            if ($scenario -ceq 'empty-workspace') {
                $shellHierarchy = Get-VisualAuditShellHierarchy -Path $candidateCaptures[$scenario]
                $comparison | Add-Member -NotePropertyName ShellHierarchy -NotePropertyValue $shellHierarchy
                $comparison.Candidates = @($comparison.Candidates) + @($shellHierarchy.Candidates)
            }
            if ($scenario -ceq 'document-tabs') {
                $expectation = $documentTabExpectations[$theme]
                $tabHierarchy = Get-VisualAuditDocumentTabHierarchy `
                    -Path $candidateCaptures[$scenario] `
                    -ExpectedShellColor $expectation.Shell `
                    -ExpectedTabChannelColor $expectation.Channel
                $comparison | Add-Member -NotePropertyName DocumentTabHierarchy -NotePropertyValue $tabHierarchy
                $comparison.Candidates = @($comparison.Candidates) + @($tabHierarchy.Candidates)
            }
            $results.Add($comparison)
        }
    }
}
catch {
    if (-not $visualStudio.HasExited) {
        Stop-Process -Id $visualStudio.Id -Force -ErrorAction SilentlyContinue
    }
    throw
}
finally {
    $captureCoverage | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'capture-coverage.json') -Encoding UTF8
    try {
        Set-VisualStudioTheme -Root $root -Name 'Dark'
    }
    catch {
        $infrastructureNotes.Add("Could not restore built-in Dark automatically: $($_.Exception.Message)")
    }
    $auditProcesses = @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -eq 'devenv.exe' -and
                $_.CommandLine -like "*RootSuffix*$RootSuffix*"
            }
    )
    foreach ($auditProcess in $auditProcesses) {
        $process = Get-Process -Id $auditProcess.ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            $process.CloseMainWindow() | Out-Null
        }
    }
    Start-Sleep -Seconds 3
    foreach ($auditProcess in $auditProcesses) {
        if (Get-Process -Id $auditProcess.ProcessId -ErrorAction SilentlyContinue) {
            Stop-Process -Id $auditProcess.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

$jsonPath = Join-Path $OutputDirectory 'visual-audit-results.json'
$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$reportPath = Join-Path $OutputDirectory 'visual-audit-report.md'
Write-VisualAuditReport `
    -Path $reportPath `
    -VsixPath $VsixPath `
    -RootSuffix $RootSuffix `
    -Results $results `
    -PackagedHashes $packagedHashes `
    -InfrastructureNotes $infrastructureNotes

$captureCoverage | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'capture-coverage.json') -Encoding UTF8
Write-Host 'Visual capture run completed; captured scenes still require state and visual review.'
Write-Host "  Themes: $($ThemeName -join ', ')"
Write-Host "  Visual Studio 2026: $($paths.InstallationVersion) (instance $($paths.InstanceId))"
Write-Host "  Scenarios compared: $($results.Count)"
Write-Host "  Installed payload: exact package hash match"
Write-Host "  Report: $reportPath"
Write-Host '  Policy: advisory candidates only; no theme source was modified by the harness'

if (@($captureCoverage | Where-Object Status -ne 'captured').Count -gt 0) {
    Write-Error 'Required capture coverage is incomplete. See capture-coverage.json.'
    exit 1
}

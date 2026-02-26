<#
.SYNOPSIS
    DD Automation GUI Launcher
.DESCRIPTION
    Provides a graphical interface to select tools, file paths, and start DD Automation.
    This script is a refactored version of Launch.ps1, organized with clearer functions and PowerShell best practices.
#>

Param(
    [string]$ConfigPath
)

#region Setup and Validation

# Enforce PowerShell 7.2+
$minVersion = [version]"7.2"
if ($PSVersionTable.PSVersion -lt $minVersion) {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Host "PowerShell 7.2+ is required."
        $install = Read-Host "Install PowerShell 7.2+ via Winget? (Y/N)"
        if ($install -match '^[Yy]') {
            winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
            $pwsh = Get-Command pwsh.exe -ErrorAction Stop
        } else {
            Write-Host "Please install PowerShell 7.2+ manually from https://aka.ms/pscore"
            exit 1
        }
    }
    Write-Host "Relaunching under PowerShell 7.2+..."
    & $pwsh.Source -NoProfile -File $MyInvocation.MyCommand.Definition @args
    exit
}

# Define script root and load core logging first.
# Dot-sourcing is used here because `using module` does not support dynamic paths (e.g., with $PSScriptRoot),
# which is necessary for this script to be portable.
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'modules\Logging.ps1')

# Initialize logging before any GUI initialization
Initialize-Log -LogDirectory (Join-Path $PSScriptRoot 'logs') -LogFileName 'DDAutomation_GUI.log' -MaxLogFiles 3
Write-Log -Message "DD Automation Launcher started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level 'INFO'

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
        Write-Log -Message "Config file not found at $ConfigPath" -Level 'ERROR'
        Write-Host "Config file not found at $ConfigPath"
        exit 1
    }

    $resolvedConfigPath = (Resolve-Path -Path $ConfigPath).Path
    Set-ActiveConfigPath -Path $resolvedConfigPath
    Write-Log -Message "Using config path provided on command line: $resolvedConfigPath" -Level 'INFO'
}

$script:gitHubFeatureMap = [ordered]@{
    GitHubCodeQL         = 'CodeQL'
    GitHubSecretScanning = 'SecretScanning'
    GitHubDependabot     = 'Dependabot'
}

function Initialize-WpfRuntime {
    # Configure DPI awareness BEFORE loading WPF assemblies.
    $script:DpiAwarenessConfigured = $false
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ProcessDpiAwareness {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetProcessDPIAware();

    public static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = (IntPtr)(-4);
}
'@

        if ([ProcessDpiAwareness]::SetProcessDpiAwarenessContext([ProcessDpiAwareness]::DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {
            $script:DpiAwarenessConfigured = $true
        } elseif ([ProcessDpiAwareness]::SetProcessDPIAware()) {
            $script:DpiAwarenessConfigured = $true
        }
    } catch {
        Write-Log -Message "DPI awareness configuration warning: $_" -Level 'WARNING'
    }

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Xaml
    Add-Type -AssemblyName System.Windows.Forms
}

Initialize-WpfRuntime

# Load remaining modules after DPI/WinForms initialization.
. (Join-Path $scriptDir 'modules\Config.ps1')
. (Join-Path $scriptDir 'modules\GitHub.ps1')
. (Join-Path $scriptDir 'modules\TenableWAS.ps1')
. (Join-Path $scriptDir 'modules\BurpSuite.ps1')
. (Join-Path $scriptDir 'modules\EnvValidator.ps1')
. (Join-Path $scriptDir 'DefectDojo.ps1')
. (Join-Path $scriptDir 'Sonarqube.ps1')
. (Join-Path $scriptDir 'Uploader.ps1')
. (Join-Path $scriptDir 'AutomationWorkflows.ps1')

# Validate environment dependencies before launching GUI
try {
    Validate-Environment
} catch {
    [System.Windows.MessageBox]::Show("Environment validation failed: $_", 'Error', 'OK', 'Error') | Out-Null
    exit 1
}

#endregion Setup and Validation

#region GUI Helper Functions

function Write-GuiMessage {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )
    Write-Log -Message $Message -Level $Level
    $timestamp = (Get-Date -Format 'HH:mm:ss')
    $script:lstStatus.Items.Add("$timestamp [$Level] $Message") | Out-Null
    # Auto-scroll to the latest message
    $script:lstStatus.ScrollIntoView($script:lstStatus.Items[$script:lstStatus.Items.Count - 1])
}

function Get-GitHubFeatureState {
    param(
        [hashtable]$Config,
        [string]$ToolKey
    )

    if (-not $Config -or -not $Config.ContainsKey('Tools')) { return $false }
    if (-not $script:gitHubFeatureMap.Contains($ToolKey)) { return $false }

    $tools = $Config.Tools
    if (-not $tools.ContainsKey('GitHub') -or $tools.GitHub -isnot [hashtable]) { return $false }

    $featureName = $script:gitHubFeatureMap[$ToolKey]
    if (-not $tools.GitHub.ContainsKey($featureName)) { return $false }

    return [bool]$tools.GitHub[$featureName]
}

function Set-GitHubFeatureState {
    param(
        [hashtable]$Config,
        [string]$ToolKey,
        [bool]$Value
    )

    if (-not $Config.ContainsKey('Tools') -or $Config.Tools -isnot [hashtable]) {
        $Config.Tools = @{}
    }
    if (-not $Config.Tools.ContainsKey('GitHub') -or $Config.Tools.GitHub -isnot [hashtable]) {
        $Config.Tools.GitHub = @{}
    }
    if (-not $script:gitHubFeatureMap.Contains($ToolKey)) { return }

    $featureName = $script:gitHubFeatureMap[$ToolKey]
    $Config.Tools.GitHub[$featureName] = $Value
}

#endregion GUI Helper Functions

#region GUI Creation

function Initialize-GuiElements {
    $script:chkBoxes = @{}
    $script:gitHubToolKeys = [string[]]$script:gitHubFeatureMap.Keys
    $script:tools = @('TenableWAS','SonarQube','BurpSuite','DefectDojo') + $script:gitHubToolKeys

    $screenWidth = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $screenHeight = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $windowWidth = [Math]::Max(720, [Math]::Min([int]($screenWidth * 0.6), [int]($screenWidth - 80)))
    $windowHeight = [Math]::Max(760, [Math]::Min([int]($screenHeight * 0.8), [int]($screenHeight - 80)))

    $script:form = New-Object System.Windows.Window
    $script:form.Title = 'DD Automation Launcher'
    $script:form.Width = $windowWidth
    $script:form.Height = $windowHeight
    $script:form.MinWidth = 640
    $script:form.MinHeight = 720
    $script:form.WindowStartupLocation = 'CenterScreen'
    $script:form.SizeToContent = 'Manual'

    $rootGrid = New-Object System.Windows.Controls.Grid
    $rootGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = '*' }))
    $rootGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = 'Auto' }))

    $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
    $scrollViewer.VerticalScrollBarVisibility = 'Auto'
    $scrollViewer.HorizontalScrollBarVisibility = 'Auto'
    [System.Windows.Controls.Grid]::SetRow($scrollViewer, 0)

    $contentStack = New-Object System.Windows.Controls.StackPanel
    $contentStack.Orientation = 'Vertical'
    $contentStack.Margin = '10'
    $scrollViewer.Content = $contentStack

    $toolsGroup = New-Object System.Windows.Controls.GroupBox
    $toolsGroup.Header = 'Select Tools'
    $toolsGroup.Margin = '0,0,0,10'

    $toolsWrap = New-Object System.Windows.Controls.WrapPanel
    $toolsWrap.Margin = '10'
    $toolsWrap.ItemWidth = 180
    $toolsGroup.Content = $toolsWrap

    $script:toolTip = New-Object System.Windows.Controls.ToolTip

    foreach ($name in $script:tools) {
        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.Content = $name
        $chk.IsChecked = $true
        $chk.Margin = '0,0,10,6'
        switch ($name) {
            'TenableWAS' { $chk.ToolTip = "Downloads selected Tenable WAS scans and uploads to DefectDojo. Each scan creates/updates its own test." }
            'SonarQube' { $chk.ToolTip = "This checkbox uses the built-in SonarQube DefectDojo functionality (IF SET UP - see wiki if not), to process SonarQube into DefectDojo" }
            'BurpSuite' { $chk.ToolTip = "Scans the specified folder for BurpSuite XML reports and uploads them to DefectDojo." }
            'DefectDojo' { $chk.ToolTip = "This checkbox uploads all other tools to DefectDojo. If unchecked, other tool will execute but not upload." }
            'GitHubCodeQL' { $chk.Content = 'GitHub CodeQL'; $chk.ToolTip = "Download and process GitHub CodeQL SARIF reports, optionally upload to DefectDojo." }
            'GitHubSecretScanning' { $chk.Content = 'GitHub Secret Scanning'; $chk.ToolTip = "Download GitHub Secret Scanning JSON alerts, optionally upload to DefectDojo." }
            'GitHubDependabot' { $chk.Content = 'GitHub Dependabot'; $chk.ToolTip = "Download GitHub Dependabot alerts JSON and upload to DefectDojo when configured." }
        }
        $toolsWrap.Children.Add($chk) | Out-Null
        $script:chkBoxes[$name] = $chk
    }

    $contentStack.Children.Add($toolsGroup) | Out-Null

    $formGrid = New-Object System.Windows.Controls.Grid
    $formGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
    $formGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = '*' }))
    $formGrid.Margin = '0,0,0,10'

    $script:formRowIndex = 0
    function Add-FormRow {
        param(
            [string]$Label,
            [System.Windows.UIElement]$Control
        )

        $formGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = 'Auto' }))
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $Label
        $lbl.Margin = '0,6,10,6'
        [System.Windows.Controls.Grid]::SetRow($lbl, $script:formRowIndex)
        [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
        $formGrid.Children.Add($lbl) | Out-Null

        $Control.Margin = '0,4,0,4'
        [System.Windows.Controls.Grid]::SetRow($Control, $script:formRowIndex)
        [System.Windows.Controls.Grid]::SetColumn($Control, 1)
        $formGrid.Children.Add($Control) | Out-Null
        $script:formRowIndex++
    }

    $script:txtBurp = New-Object System.Windows.Controls.TextBox
    $script:txtBurp.MinWidth = 240
    $script:btnBrowse = New-Object System.Windows.Controls.Button
    $script:btnBrowse.Content = 'Browse...'
    $script:btnBrowse.Margin = '10,0,0,0'
    $burpPanel = New-Object System.Windows.Controls.DockPanel
    $burpPanel.LastChildFill = $true
    [System.Windows.Controls.DockPanel]::SetDock($script:btnBrowse, 'Right')
    $burpPanel.Children.Add($script:btnBrowse) | Out-Null
    $burpPanel.Children.Add($script:txtBurp) | Out-Null
    Add-FormRow -Label 'BurpSuite XML Folder:' -Control $burpPanel

    $tenablePanel = New-Object System.Windows.Controls.StackPanel
    $tenablePanel.Orientation = 'Vertical'
    $script:txtTenableSearch = New-Object System.Windows.Controls.TextBox
    $script:txtTenableSearch.MinWidth = 240
    $script:txtTenableSearch.Margin = '0,0,0,6'
    $script:txtTenableSearch.ToolTip = 'Search scans by name...'

    $tenableListPanel = New-Object System.Windows.Controls.DockPanel
    $script:btnRefreshTenable = New-Object System.Windows.Controls.Button
    $script:btnRefreshTenable.Content = 'Refresh'
    $script:btnRefreshTenable.Margin = '10,0,0,0'
    $script:btnRefreshTenable.Width = 80

    $script:tenableScroll = New-Object System.Windows.Controls.ScrollViewer
    $script:tenableScroll.Height = 140
    $script:tenableScroll.VerticalScrollBarVisibility = 'Auto'
    $script:tenableScroll.HorizontalScrollBarVisibility = 'Disabled'
    $script:tenableScanPanel = New-Object System.Windows.Controls.StackPanel
    $script:tenableScanPanel.Orientation = 'Vertical'
    $script:tenableScanPanel.Margin = '2,2,2,2'
    $script:tenableScroll.Content = $script:tenableScanPanel

    [System.Windows.Controls.DockPanel]::SetDock($script:btnRefreshTenable, 'Right')
    $tenableListPanel.Children.Add($script:btnRefreshTenable) | Out-Null
    $tenableListPanel.Children.Add($script:tenableScroll) | Out-Null

    $tenablePanel.Children.Add($script:txtTenableSearch) | Out-Null
    $tenablePanel.Children.Add($tenableListPanel) | Out-Null
    Add-FormRow -Label 'TenableWAS Scans:' -Control $tenablePanel

    $script:txtGitHubOrgs = New-Object System.Windows.Controls.TextBox
    $script:txtGitHubOrgs.ToolTip = 'Enter one or more GitHub organizations, separated by commas.'
    Add-FormRow -Label 'GitHub Orgs:' -Control $script:txtGitHubOrgs

    $script:cmbDDProduct = New-Object System.Windows.Controls.ComboBox
    $script:cmbDDEng = New-Object System.Windows.Controls.ComboBox
    $script:cmbDDApiScan = New-Object System.Windows.Controls.ComboBox
    $script:cmbDDTestSonar = New-Object System.Windows.Controls.ComboBox
    $script:cmbDDTestBurp = New-Object System.Windows.Controls.ComboBox
    $script:cmbDDTestDependabot = New-Object System.Windows.Controls.ComboBox
    $script:cmbDDSeverity = New-Object System.Windows.Controls.ComboBox

    foreach ($combo in @($script:cmbDDProduct, $script:cmbDDEng, $script:cmbDDApiScan, $script:cmbDDTestSonar, $script:cmbDDTestBurp, $script:cmbDDTestDependabot, $script:cmbDDSeverity)) {
        $combo.IsEnabled = $false
        $combo.MinWidth = 220
    }

    Add-FormRow -Label 'DefectDojo Product:' -Control $script:cmbDDProduct
    Add-FormRow -Label 'Engagement:' -Control $script:cmbDDEng
    Add-FormRow -Label 'API Scan Config:' -Control $script:cmbDDApiScan
    Add-FormRow -Label 'SonarQube Test:' -Control $script:cmbDDTestSonar
    Add-FormRow -Label 'BurpSuite Test:' -Control $script:cmbDDTestBurp
    Add-FormRow -Label 'Dependabot Test:' -Control $script:cmbDDTestDependabot
    Add-FormRow -Label 'Minimum Severity:' -Control $script:cmbDDSeverity

    $script:cmbDDSeverity.ItemsSource = @('Info','Low','Medium','High','Critical')

    $script:chkDDCloseFindings = New-Object System.Windows.Controls.CheckBox
    $script:chkDDCloseFindings.Content = 'Close Old Findings'
    $script:chkDDCloseFindings.IsEnabled = $false
    Add-FormRow -Label '' -Control $script:chkDDCloseFindings

    $script:txtTags = New-Object System.Windows.Controls.TextBox
    $script:txtTags.IsEnabled = $false
    $script:txtTags.ToolTip = 'Enter tags to apply to all scan uploads (e.g., automated-scan, dd-automation). Separate multiple tags with commas.'
    Add-FormRow -Label 'Tags:' -Control $script:txtTags

    $script:chkApplyTagsToFindings = New-Object System.Windows.Controls.CheckBox
    $script:chkApplyTagsToFindings.Content = 'Apply tags to findings'
    $script:chkApplyTagsToFindings.IsEnabled = $false
    Add-FormRow -Label '' -Control $script:chkApplyTagsToFindings

    $script:chkApplyTagsToEndpoints = New-Object System.Windows.Controls.CheckBox
    $script:chkApplyTagsToEndpoints.Content = 'Apply tags to endpoints'
    $script:chkApplyTagsToEndpoints.IsEnabled = $false
    Add-FormRow -Label '' -Control $script:chkApplyTagsToEndpoints

    $contentStack.Children.Add($formGrid) | Out-Null

    $manualGroup = New-Object System.Windows.Controls.GroupBox
    $manualGroup.Header = 'Manual Upload (DefectDojo CLI)'
    $manualGroup.Margin = '0,10,0,0'
    $manualPanel = New-Object System.Windows.Controls.DockPanel
    $manualPanel.Margin = '10'
    $script:btnLaunchTool = New-Object System.Windows.Controls.Button
    $script:btnLaunchTool.Content = 'Launch DefectDojo CLI'
    $script:btnLaunchTool.Margin = '0,0,10,0'
    $manualInfo = New-Object System.Windows.Controls.TextBlock
    $manualInfo.Text = 'Opens defectdojo-cli.exe in a new console; no data is passed.'
    $manualInfo.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($script:btnLaunchTool, 'Left')
    $manualPanel.Children.Add($script:btnLaunchTool) | Out-Null
    $manualPanel.Children.Add($manualInfo) | Out-Null
    $manualGroup.Content = $manualPanel
    $contentStack.Children.Add($manualGroup) | Out-Null

    $rootGrid.Children.Add($scrollViewer) | Out-Null

    $statusGrid = New-Object System.Windows.Controls.Grid
    $statusGrid.Margin = '10'
    $statusGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = '*' }))
    $statusGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = 'Auto' }))
    [System.Windows.Controls.Grid]::SetRow($statusGrid, 1)

    $script:lstStatus = New-Object System.Windows.Controls.ListBox
    [System.Windows.Controls.Grid]::SetRow($script:lstStatus, 0)
    $statusGrid.Children.Add($script:lstStatus) | Out-Null

    $buttonPanel = New-Object System.Windows.Controls.DockPanel
    $buttonPanel.LastChildFill = $true
    $buttonPanel.Margin = '0,8,0,0'
    [System.Windows.Controls.Grid]::SetRow($buttonPanel, 1)

    $script:btnLaunch = New-Object System.Windows.Controls.Button
    $script:btnLaunch.Content = 'GO'
    $script:btnLaunch.Width = 100
    $script:btnLaunch.Margin = '0,0,10,0'

    $script:btnCancel = New-Object System.Windows.Controls.Button
    $script:btnCancel.Content = 'Close'
    $script:btnCancel.Width = 100

    $buttonsStack = New-Object System.Windows.Controls.StackPanel
    $buttonsStack.Orientation = 'Horizontal'
    $buttonsStack.HorizontalAlignment = 'Right'
    $buttonsStack.Children.Add($script:btnCancel) | Out-Null
    $buttonsStack.Children.Add($script:btnLaunch) | Out-Null
    [System.Windows.Controls.DockPanel]::SetDock($buttonsStack, 'Right')

    $script:lblComplete = New-Object System.Windows.Controls.TextBlock
    $script:lblComplete.Text = ''
    $script:lblComplete.FontSize = 14
    $script:lblComplete.FontWeight = 'Bold'
    $script:lblComplete.Foreground = 'Green'
    $script:lblComplete.VerticalAlignment = 'Center'
    $script:lblComplete.Visibility = 'Collapsed'

    $buttonPanel.Children.Add($buttonsStack) | Out-Null
    $buttonPanel.Children.Add($script:lblComplete) | Out-Null
    $statusGrid.Children.Add($buttonPanel) | Out-Null

    $rootGrid.Children.Add($statusGrid) | Out-Null
    $script:form.Content = $rootGrid
}

#endregion GUI Creation

#region Event Handlers

function Register-EventHandlers {
    # Tool selection checkboxes
    $chkBoxes['BurpSuite'].Add_Checked({
        $script:txtBurp.IsEnabled = $true
        $script:btnBrowse.IsEnabled = $true
        $script:cmbDDTestBurp.IsEnabled = ($script:cmbDDTestBurp.Items.Count -gt 0)
    })
    $chkBoxes['BurpSuite'].Add_Unchecked({
        $script:txtBurp.IsEnabled = $false
        $script:btnBrowse.IsEnabled = $false
        $script:cmbDDTestBurp.IsEnabled = $false
    })
    $chkBoxes['TenableWAS'].Add_Checked({
        $script:tenableScroll.IsEnabled = $true
        $script:txtTenableSearch.IsEnabled = $true
        $script:btnRefreshTenable.IsEnabled = $true
        if ($script:tenableScanPanel.Children.Count -eq 0) {
            Load-TenableScans
        }
    })
    $chkBoxes['TenableWAS'].Add_Unchecked({
        $script:tenableScroll.IsEnabled = $false
        $script:txtTenableSearch.IsEnabled = $false
        $script:btnRefreshTenable.IsEnabled = $false
    })
    $script:btnRefreshTenable.Add_Click({ Load-TenableScans })
    
    # Tenable scan search/filter
    $script:txtTenableSearch.Add_TextChanged({
        Apply-TenableSearch -SearchTerm $this.Text
    })

    $chkBoxes['SonarQube'].Add_Checked({
        $script:cmbDDTestSonar.IsEnabled = ($script:cmbDDTestSonar.Items.Count -gt 0)
        $script:cmbDDApiScan.IsEnabled = ($script:cmbDDApiScan.Items.Count -gt 0)
    })
    $chkBoxes['SonarQube'].Add_Unchecked({
        $script:cmbDDTestSonar.IsEnabled = $false
        $script:cmbDDApiScan.IsEnabled = $false
    })
    foreach ($key in $script:gitHubToolKeys) {
        $chkBoxes[$key].Add_Checked({ Update-GitHubControlState })
        $chkBoxes[$key].Add_Unchecked({ Update-GitHubControlState })
    }
    $chkBoxes['DefectDojo'].Add_Checked({
        $script:cmbDDSeverity.IsEnabled = $true
        $script:chkDDCloseFindings.IsEnabled = $true
        $script:txtTags.IsEnabled = $true
        $script:chkApplyTagsToFindings.IsEnabled = $true
        $script:chkApplyTagsToEndpoints.IsEnabled = $true
    })
    $chkBoxes['DefectDojo'].Add_Unchecked({
        $script:cmbDDSeverity.IsEnabled = $false
        $script:chkDDCloseFindings.IsEnabled = $false
        $script:txtTags.IsEnabled = $false
        $script:chkApplyTagsToFindings.IsEnabled = $false
        $script:chkApplyTagsToEndpoints.IsEnabled = $false
    })

    # Browse for BurpSuite folder
    $btnBrowse.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($folderDialog.ShowDialog() -eq 'OK') {
            $script:txtBurp.Text = $folderDialog.SelectedPath
        }
    })

    # DefectDojo dropdowns
    $cmbDDProduct.Add_SelectionChanged({ Handle-ProductChange })
    $cmbDDEng.Add_SelectionChanged({ Handle-EngagementChange })

    # Launch DefectDojo CLI button
    $btnLaunchTool.Add_Click({ Invoke-ExternalTool })

    # Main action buttons
    $btnLaunch.Add_Click({ Invoke-Automation })
    $btnCancel.Content = 'Close'
    $btnCancel.Add_Click({ $script:form.Close() })

    Update-GitHubControlState
}

function Get-WpfSelectedTool {
    param([string]$ToolName)
    if (-not $script:chkBoxes.ContainsKey($ToolName)) { return $false }
    return [bool]$script:chkBoxes[$ToolName].IsChecked
}

function Update-GitHubControlState {
    $anyGitHub = $false
    foreach ($key in $script:gitHubToolKeys) {
        if ($script:chkBoxes.ContainsKey($key) -and $script:chkBoxes[$key].IsChecked) {
            $anyGitHub = $true
            break
        }
    }

    $script:txtGitHubOrgs.IsEnabled = $anyGitHub
    $script:cmbDDTestDependabot.IsEnabled = ($script:chkBoxes['GitHubDependabot'].IsChecked -and $script:cmbDDTestDependabot.Items.Count -gt 0)
}

function Handle-ProductChange {
    $selectedProduct = $script:cmbDDProduct.SelectedItem
    if (-not $selectedProduct) { return }

    Write-GuiMessage "Loading engagements for product $($selectedProduct.Name)..."
    try {
        $engagements = Get-DefectDojoEngagements -ProductId $selectedProduct.Id
        $script:cmbDDEng.Items.Clear()
        if ($engagements) {
            foreach ($e in $engagements) { $script:cmbDDEng.Items.Add($e) | Out-Null }
        }
        $script:cmbDDEng.DisplayMemberPath = 'Name'; $script:cmbDDEng.SelectedValuePath = 'Id'
        $script:cmbDDEng.IsEnabled = $true

        # Clear subsequent dropdowns
        @($script:cmbDDTestSonar, $script:cmbDDTestBurp) | ForEach-Object {
            $_.IsEnabled = $false; $_.Items.Clear()
        }
    } catch {
        Write-GuiMessage "Failed to load engagements: $_" 'ERROR'
    }
}

function Handle-EngagementChange {
    $selectedEngagement = $script:cmbDDEng.SelectedItem
    if (-not $selectedEngagement) { return }

    Write-GuiMessage "Loading tests for engagement $($selectedEngagement.Name)..."
    try {
        $tests = Get-DefectDojoTests -EngagementId $selectedEngagement.Id
        foreach ($cmb in @($script:cmbDDTestSonar, $script:cmbDDTestBurp, $script:cmbDDTestDependabot)) {
            $cmb.Items.Clear()
            if ($tests) {
                foreach ($t in $tests) { $cmb.Items.Add($t) | Out-Null }
            }
            $cmb.SelectedValuePath = 'Id'
        }
        # Set DisplayMember based on needed display, Title works for most Dojo tests
        $script:cmbDDTestSonar.DisplayMemberPath = 'Title'     # Show test type title for SonarQube
        $script:cmbDDTestBurp.DisplayMemberPath = 'Title'      # Show test type title for BurpSuite
        $script:cmbDDTestDependabot.DisplayMemberPath = 'Title'

        # Re-evaluate enabled state based on tool selection and if tests were found
        $script:cmbDDTestSonar.IsEnabled  = (Get-WpfSelectedTool -ToolName 'SonarQube') -and $tests.Count -gt 0
        $script:cmbDDTestBurp.IsEnabled   = (Get-WpfSelectedTool -ToolName 'BurpSuite') -and $tests.Count -gt 0
        $script:cmbDDTestDependabot.IsEnabled = (Get-WpfSelectedTool -ToolName 'GitHubDependabot') -and $tests.Count -gt 0
        Update-GitHubControlState
        if (-not $tests) {
            Write-GuiMessage "No DefectDojo tests found for engagement $($selectedEngagement.Name)." 'WARNING'
        }
    } catch {
        Write-GuiMessage "Failed to load tests: $_" 'ERROR'
    }
}

function Invoke-ExternalTool {
    try {
        # Disable button to prevent double clicks
        $script:btnLaunchTool.IsEnabled = $false
        
        # Compute tool path
        $toolPath = Join-Path $PSScriptRoot 'modules\defectdojo-cli.exe'
        
        # Check if tool exists
        if (-not (Test-Path -Path $toolPath -PathType Leaf)) {
            [System.Windows.MessageBox]::Show(
                "DefectDojo CLI not found at modules\defectdojo-cli.exe. Please add the EXE to the modules folder.",
                'Tool Not Found',
                'OK',
                'Warning'
            ) | Out-Null
            $script:btnLaunchTool.IsEnabled = $true
            return
        }
        
        # Ensure CLI sees expected API token
        $apiKey = $env:DOJO_API_KEY
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Write-GuiMessage "DOJO_API_KEY environment variable is not set; cannot launch DefectDojo CLI." 'ERROR'
            [System.Windows.MessageBox]::Show(
                "DOJO_API_KEY is not configured. Please populate the variable and relaunch.",
                'Missing Environment Variable',
                'OK',
                'Error'
            ) | Out-Null
            $script:btnLaunchTool.IsEnabled = $true
            return
        }

        try {
            [System.Environment]::SetEnvironmentVariable('DD_CLI_API_TOKEN', $apiKey, [System.EnvironmentVariableTarget]::User)
            $env:DD_CLI_API_TOKEN = $apiKey
            Write-GuiMessage "DD_CLI_API_TOKEN synchronized with DOJO_API_KEY."
        } catch {
            Write-GuiMessage "Failed to set DD_CLI_API_TOKEN: $_" 'ERROR'
            [System.Windows.MessageBox]::Show(
                "Failed to update DD_CLI_API_TOKEN. See log for details.",
                'Environment Variable Error',
                'OK',
                'Error'
            ) | Out-Null
            $script:btnLaunchTool.IsEnabled = $true
            return
        }

        # Log before launch
        Write-GuiMessage "Launching DefectDojo CLI: modules\defectdojo-cli.exe"

        # Launch the tool in a PowerShell window and keep it open 
        # hacky.... but it works
        $workingDirectory = Split-Path $toolPath -Parent
        $escapedWorkingDir = $workingDirectory.Replace("'", "''")
        $escapedToolPath = $toolPath.Replace("'", "''")
        $command = "& { Set-Location -LiteralPath '$escapedWorkingDir'; & '$escapedToolPath' interactive }"
        Start-Process -FilePath 'pwsh.exe' -ArgumentList @('-NoExit', '-NoLogo', '-Command', $command) -WorkingDirectory $workingDirectory
        
        # Log after launch
        Write-GuiMessage "DefectDojo CLI launched in a new window (console stays open)."
        
    } catch {
        Write-GuiMessage "Failed to launch DefectDojo CLI: $_" 'ERROR'
    } finally {
        # Re-enable button
        $script:btnLaunchTool.IsEnabled = $true
    }
}

#endregion Event Handlers

#region Data Loading and Pre-population

function Load-TenableScans {
    Write-GuiMessage "Loading TenableWAS scans..."
    try {
        $scans = Get-TenableWASScanConfigs
        $script:allTenableScans = @()
        $script:tenableScanPanel.Children.Clear()
        if ($scans) {
            $script:allTenableScans = $scans
            Apply-TenableSearch -SearchTerm ($script:txtTenableSearch.Text)
        }
        
        # Restore selection if config has names
        $config = Get-Config
        if ($config.TenableWASScanNames -and $config.TenableWASScanNames.Count -gt 0) {
            $script:checkedTenableScanIds = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($scan in $script:allTenableScans) {
                if ($scan.Name -in $config.TenableWASScanNames) {
                    $null = $script:checkedTenableScanIds.Add([string]$scan.Id)
                }
            }
            Apply-TenableSearch -SearchTerm ($script:txtTenableSearch.Text)
        }
    } catch {
        Write-GuiMessage "Failed to load TenableWAS scans: $_" 'ERROR'
    }
}

function Apply-TenableSearch {
    param([string]$SearchTerm)

    # Preserve current checked IDs
    if (-not $script:checkedTenableScanIds) {
        $script:checkedTenableScanIds = [System.Collections.Generic.HashSet[string]]::new()
    }

    $script:tenableScanPanel.Children.Clear()
    if (-not $script:allTenableScans) { return }

    $term = $SearchTerm
    $filtered = if ([string]::IsNullOrWhiteSpace($term)) { 
        $script:allTenableScans 
    } else {
        $script:allTenableScans | Where-Object { $_.Name -like "*${term}*" }
    }

    foreach ($scan in $filtered) {
        $checkbox = New-Object System.Windows.Controls.CheckBox
        $checkbox.Content = $scan.Name
        $checkbox.Tag = $scan
        $checkbox.Margin = '2,2,2,2'
        $checkbox.IsChecked = $script:checkedTenableScanIds.Contains([string]$scan.Id)
        $checkbox.Add_Checked({
            param($sender, $args)
            $scanInfo = $sender.Tag
            if ($scanInfo) { $null = $script:checkedTenableScanIds.Add([string]$scanInfo.Id) }
        })
        $checkbox.Add_Unchecked({
            param($sender, $args)
            $scanInfo = $sender.Tag
            if ($scanInfo) { $null = $script:checkedTenableScanIds.Remove([string]$scanInfo.Id) }
        })
        $script:tenableScanPanel.Children.Add($checkbox) | Out-Null
    }
}

function Load-DefectDojoData {
    if (Get-WpfSelectedTool -ToolName 'DefectDojo') {
        Write-GuiMessage 'Loading DefectDojo products...'
        try {
            $products = Get-DefectDojoProducts
            $script:cmbDDProduct.Items.Clear()
            foreach ($p in $products) { $script:cmbDDProduct.Items.Add($p) | Out-Null }
            $script:cmbDDProduct.DisplayMemberPath = 'Name'; $script:cmbDDProduct.SelectedValuePath = 'Id'
            $script:cmbDDProduct.IsEnabled = $true
        } catch {
            Write-GuiMessage "Failed to load DefectDojo products: $_" 'ERROR'
        }
    }

    if (Get-WpfSelectedTool -ToolName 'SonarQube') {
        Write-GuiMessage 'Loading DefectDojo API scan configurations...'
        try {
            # This assumes a Product ID might be available in config for pre-loading.
            # If not, Get-DefectDojoApiScanConfigurations should handle a null ProductId.
            $config = Get-Config
            $apiConfigs = Get-DefectDojoApiScanConfigurations -ProductId $config.DefectDojo.APIScanConfigID
            $script:cmbDDApiScan.Items.Clear()
            if ($apiConfigs) {
                foreach ($c in $apiConfigs) { $script:cmbDDApiScan.Items.Add($c) | Out-Null }
            }
            $script:cmbDDApiScan.DisplayMemberPath = 'Name'; $script:cmbDDApiScan.SelectedValuePath = 'Id'
            $script:cmbDDApiScan.IsEnabled = $true
        } catch {
            Write-GuiMessage "Failed to load API scan configurations: $_" 'ERROR'
        }
    }
}

function Prepopulate-FormFromConfig {
    param([hashtable]$Config)

    Write-GuiMessage "Loading settings from config file..."
    foreach ($tool in $script:tools) {
        if ($script:gitHubFeatureMap.Contains($tool)) {
            $script:chkBoxes[$tool].IsChecked = Get-GitHubFeatureState -Config $Config -ToolKey $tool
        }
        elseif ($Config.Tools.ContainsKey($tool)) {
            $script:chkBoxes[$tool].IsChecked = [bool]$Config.Tools[$tool]
        }
        else {
            $Config.Tools[$tool] = $script:chkBoxes[$tool].IsChecked
        }
    }
    Update-GitHubControlState

    # Enable DefectDojo-dependent controls if DefectDojo checkbox is checked
    # (setting .IsChecked programmatically doesn't fire CheckedChanged event)
    if ($script:chkBoxes['DefectDojo'].IsChecked) {
        $script:cmbDDSeverity.IsEnabled = $true
        $script:chkDDCloseFindings.IsEnabled = $true
        $script:txtTags.IsEnabled = $true
        $script:chkApplyTagsToFindings.IsEnabled = $true
        $script:chkApplyTagsToEndpoints.IsEnabled = $true
    }

    if ($script:chkBoxes['TenableWAS'].IsChecked) {
        if (-not $script:checkedTenableScanIds) {
            $script:checkedTenableScanIds = [System.Collections.Generic.HashSet[string]]::new()
        }
        Load-TenableScans
    }

    if ($Config.Paths.ContainsKey('BurpSuiteXmlFolder')) {
        $script:txtBurp.Text = $Config.Paths.BurpSuiteXmlFolder
    }

    if ($Config.GitHub -and $Config.GitHub.Orgs) {
        $orgList = @($Config.GitHub.Orgs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        if ($orgList.Count -gt 0) {
            $orgText = $orgList -join ', '
            $script:txtGitHubOrgs.Text = $orgText
            Write-GuiMessage ("Loaded GitHub organizations from config: {0}" -f $orgText)
        }
        else {
            $script:txtGitHubOrgs.Clear()
            Write-GuiMessage 'No GitHub organizations found in config; textbox cleared.' 'WARNING'
        }
    }
    else {
        $script:txtGitHubOrgs.Clear()
        Write-GuiMessage 'GitHub configuration block missing or empty; textbox cleared.' 'WARNING'
    }

    if ($Config.DefectDojo) {
        # Pre-select Product, which will trigger chained events for Engagements and Tests
        if ($Config.DefectDojo.ProductId) {
            $selectedProduct = $script:cmbDDProduct.Items | Where-Object { $_.Id -eq $Config.DefectDojo.ProductId }
            if ($selectedProduct) {
            $script:cmbDDProduct.SelectedItem = $selectedProduct
            # Manually trigger dependent loads as events might not fire before form is shown
            Handle-ProductChange
            $script:form.Dispatcher.Invoke([action]{} )
                
                if ($Config.DefectDojo.EngagementId) {
                    $selectedEngagement = $script:cmbDDEng.Items | Where-Object { $_.Id -eq $Config.DefectDojo.EngagementId }
                    if ($selectedEngagement) {
                    $script:cmbDDEng.SelectedItem = $selectedEngagement
                    Handle-EngagementChange
                    $script:form.Dispatcher.Invoke([action]{} )

                        # Pre-select test dropdowns after engagement is loaded
                        if ($Config.DefectDojo.SonarQubeTestId) {
                            $selectedSonarTest = $script:cmbDDTestSonar.Items | Where-Object { $_.Id -eq $Config.DefectDojo.SonarQubeTestId }
                            if ($selectedSonarTest) { $script:cmbDDTestSonar.SelectedItem = $selectedSonarTest }
                        }
                        if ($Config.DefectDojo.BurpSuiteTestId) {
                            $selectedBurpTest = $script:cmbDDTestBurp.Items | Where-Object { $_.Id -eq $Config.DefectDojo.BurpSuiteTestId }
                            if ($selectedBurpTest) { $script:cmbDDTestBurp.SelectedItem = $selectedBurpTest }
                        }
                        if ($Config.DefectDojo.GitHubDependabotTestId) {
                            $selectedDependabotTest = $script:cmbDDTestDependabot.Items | Where-Object { $_.Id -eq $Config.DefectDojo.GitHubDependabotTestId }
                            if ($selectedDependabotTest) { $script:cmbDDTestDependabot.SelectedItem = $selectedDependabotTest }
                        }
                    }
                }
            }
        }
        
        # Pre-select stand-alone items
        if ($Config.DefectDojo.APIScanConfigId) {
            $selectedApiConfig = $script:cmbDDApiScan.Items | Where-Object { $_.Id -eq $Config.DefectDojo.APIScanConfigId }
            if ($selectedApiConfig) { $script:cmbDDApiScan.SelectedItem = $selectedApiConfig }
        }
        if ($Config.DefectDojo.MinimumSeverity) {
            $script:cmbDDSeverity.SelectedItem = $Config.DefectDojo.MinimumSeverity
        }
        if ($Config.DefectDojo.CloseOldFindings) {
            $script:chkDDCloseFindings.IsChecked = $Config.DefectDojo.CloseOldFindings
        }
        if ($Config.DefectDojo.Tags) {
            $tagsText = ($Config.DefectDojo.Tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
            $script:txtTags.Text = $tagsText
        }
        if ($Config.DefectDojo.ApplyTagsToFindings) {
            $script:chkApplyTagsToFindings.IsChecked = $Config.DefectDojo.ApplyTagsToFindings
        }
        if ($Config.DefectDojo.ApplyTagsToEndpoints) {
            $script:chkApplyTagsToEndpoints.IsChecked = $Config.DefectDojo.ApplyTagsToEndpoints
        }
    }
    Write-GuiMessage "Pre-population complete."
}


#endregion Data Loading and Pre-population

#region Main Automation Logic

function Invoke-Automation {
    try {
        # Disable the launch button while processing
        $script:btnLaunch.IsEnabled = $false
        $script:lblComplete.Visibility = 'Collapsed'
        
        $config = Get-Config

        # Validate GUI inputs
        if ($script:chkBoxes['BurpSuite'].IsChecked -and -not (Test-Path -Path $script:txtBurp.Text -PathType Container)) {
            [System.Windows.MessageBox]::Show("Please select a valid BurpSuite XML folder.", 'Validation Error', 'OK', 'Error') | Out-Null
            $script:btnLaunch.IsEnabled = $true
            return
        }

        # Update config from GUI selections
        foreach ($tool in $script:tools) {
            if ($script:gitHubFeatureMap.Contains($tool)) {
                Set-GitHubFeatureState -Config $config -ToolKey $tool -Value $script:chkBoxes[$tool].IsChecked
            }
            else {
                $config.Tools[$tool] = $script:chkBoxes[$tool].IsChecked
            }
        }
        if ($config.Tools.BurpSuite) { $config.Paths.BurpSuiteXmlFolder = $script:txtBurp.Text }
        
        if (-not $script:checkedTenableScanIds) {
            $script:checkedTenableScanIds = [System.Collections.Generic.HashSet[string]]::new()
        }
        $selectedScans = @($script:allTenableScans | Where-Object { $script:checkedTenableScanIds.Contains([string]$_.Id) })
        $tenableScanNamesChanged = $false
        if ($selectedScans.Count -gt 0) {
             $newScanNames = @($selectedScans | ForEach-Object { $_.Name })
             
             # Get existing scan names, filtering out nulls
             $existingScanNames = if ($config.ContainsKey('TenableWASScanNames') -and $null -ne $config.TenableWASScanNames) {
                 @($config.TenableWASScanNames | Where-Object { $_ })
             } else {
                 @()
             }
             
             # Check if scan names have changed
             if ($existingScanNames.Count -eq 0 -and $newScanNames.Count -gt 0) {
                 # No existing scans, but we have new ones
                 $tenableScanNamesChanged = $true
             } elseif ($existingScanNames.Count -ne $newScanNames.Count) {
                 # Different count
                 $tenableScanNamesChanged = $true
             } elseif ($existingScanNames.Count -gt 0) {
                 # Same count, check if contents differ
                 $differences = Compare-Object -ReferenceObject $existingScanNames -DifferenceObject $newScanNames -ErrorAction SilentlyContinue
                 if ($differences) {
                     $tenableScanNamesChanged = $true
                 }
             }
             
             if ($tenableScanNamesChanged) {
                 $config.TenableWASScanNames = $newScanNames
                 Write-GuiMessage "TenableWAS scan selection changed: $($newScanNames -join ', ')"
             }
             $config.TenableWASSelectedScans = @($selectedScans)
        }

        $existingGitHubOrgs = @($config.GitHub.Orgs)
        $githubInput = $script:txtGitHubOrgs.Text
        $parsedGitHubOrgs = @()
        if ($null -ne $githubInput) {
            $parsedGitHubOrgs = @($githubInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        if ($parsedGitHubOrgs.Count -gt 0) {
            $orgSummary = $parsedGitHubOrgs -join ', '
            Write-GuiMessage ("Using GitHub organizations from textbox: {0}" -f $orgSummary)

            $differences = Compare-Object -ReferenceObject $existingGitHubOrgs -DifferenceObject $parsedGitHubOrgs
            $config.GitHub.Orgs = $parsedGitHubOrgs

            if ($differences) {
                try {
                    Write-GuiMessage ("Saving GitHub organizations to config: {0}" -f $orgSummary)
                    Save-Config -Config $config
                    Write-GuiMessage 'GitHub organization configuration saved.'
                } catch {
                    Write-GuiMessage "Failed to save GitHub organization configuration: $_" 'ERROR'
                }
            }
            else {
                Write-GuiMessage 'GitHub organization list unchanged; no config save required.'
            }
        }
        else {
            Write-GuiMessage 'GitHub organization textbox is empty; retaining existing configuration values.' 'WARNING'
            if ($config.GitHub.Orgs) {
                $script:txtGitHubOrgs.Text = ($config.GitHub.Orgs -join ', ')
            }
        }

        # Save TenableWAS scan selections if they changed
        if ($tenableScanNamesChanged) {
            try {
                Write-GuiMessage "Saving TenableWAS scan selections to config..."
                Save-Config -Config $config
                Write-GuiMessage 'TenableWAS scan selection saved.'
            } catch {
                Write-GuiMessage "Failed to save TenableWAS scan selection: $_" 'ERROR'
            }
        }

        # Save DefectDojo selections to config BEFORE running workflows
        # This ensures all modules that call Get-Config internally will use the updated values
        if ($config.Tools.DefectDojo) {
            Save-DefectDojoConfig -Config $config
        }

        $selectedToolLabels = @()
        foreach ($tool in $script:tools) {
            $isEnabled = $false
            if ($script:gitHubFeatureMap.Contains($tool)) {
                $isEnabled = Get-GitHubFeatureState -Config $config -ToolKey $tool
            }
            elseif ($config.Tools.ContainsKey($tool)) {
                $isEnabled = [bool]$config.Tools[$tool]
            }
            if ($isEnabled) {
                $selectedToolLabels += [string]$script:chkBoxes[$tool].Content
            }
        }
        Write-GuiMessage "Selected Tools: $($selectedToolLabels -join ', ')"

        # Process TenableWAS
        if ($config.Tools.TenableWAS) {
            Write-GuiMessage "Starting TenableWAS workflow..."
            Invoke-Workflow-TenableWAS -Config $config
            Write-GuiMessage "TenableWAS workflow finished."
        }

        # Process SonarQube
        if ($config.Tools.SonarQube) {
            Write-GuiMessage "Starting SonarQube workflow..."
            Invoke-Workflow-SonarQube -Config $config
            Write-GuiMessage "SonarQube workflow finished."
        }

        # Process BurpSuite
        if ($config.Tools.BurpSuite) {
            Write-GuiMessage "Starting BurpSuite workflow..."
            Invoke-Workflow-BurpSuite -Config $config
            Write-GuiMessage "BurpSuite workflow finished."
        }

        # Process GitHub CodeQL
        if (Get-GitHubFeatureState -Config $config -ToolKey 'GitHubCodeQL') {
            Write-GuiMessage "Starting GitHub CodeQL workflow..."
            Invoke-Workflow-GitHubCodeQL -Config $config
            Write-GuiMessage "GitHub CodeQL workflow finished."
        }

        # Process GitHub Secret Scanning
        if (Get-GitHubFeatureState -Config $config -ToolKey 'GitHubSecretScanning') {
            Write-GuiMessage "Starting GitHub Secret Scanning workflow..."
            Invoke-Workflow-GitHubSecretScanning -Config $config
            Write-GuiMessage "GitHub Secret Scanning workflow finished."
        }

        # Process GitHub Dependabot alerts
        if (Get-GitHubFeatureState -Config $config -ToolKey 'GitHubDependabot') {
            Write-GuiMessage "Starting GitHub Dependabot workflow..."
            Invoke-Workflow-GitHubDependabot -Config $config
            Write-GuiMessage "GitHub Dependabot workflow finished."
        }

        # Expose the updated config to the parent session for potential post-script actions
        Set-Variable -Name Config -Scope Global -Value $config
        Write-GuiMessage 'Configuration stored in global: $Config. Tasks completed successfully!'

        # Show completion message
        $script:lblComplete.Text = "Complete! Ready for next task."
        $script:lblComplete.Visibility = 'Visible'
        
        # Re-enable the launch button to allow for additional tasks
        $script:btnLaunch.IsEnabled = $true

    } catch {
        Write-GuiMessage "An unexpected error occurred: $_" 'ERROR'
        $script:btnLaunch.IsEnabled = $true
    }
}

function Save-DefectDojoConfig {
    param([hashtable]$Config)

    $selections = @{
        Product         = $script:cmbDDProduct.SelectedItem
        Engagement      = $script:cmbDDEng.SelectedItem
        ApiScanConfig   = $script:cmbDDApiScan.SelectedItem
        SonarQubeTest   = $script:cmbDDTestSonar.SelectedItem
        BurpSuiteTest   = $script:cmbDDTestBurp.SelectedItem
        GitHubDependabotTest = $script:cmbDDTestDependabot.SelectedItem
        MinimumSeverity = $script:cmbDDSeverity.SelectedItem
    }

    $dependabotEnabled = Get-GitHubFeatureState -Config $Config -ToolKey 'GitHubDependabot'

    # Parse and save tags
    $tagsText = $script:txtTags.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($tagsText)) {
        # Split by comma, trim whitespace, filter empties
        $tagArray = @($tagsText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if (-not $Config.DefectDojo) { $Config.DefectDojo = @{} }
        $Config.DefectDojo.Tags = $tagArray
    } else {
        if (-not $Config.DefectDojo) { $Config.DefectDojo = @{} }
        $Config.DefectDojo.Tags = @()
    }
    # Save tag flags
    if (-not $Config.DefectDojo) { $Config.DefectDojo = @{} }
    $Config.DefectDojo.ApplyTagsToFindings = [bool]$script:chkApplyTagsToFindings.IsChecked
    $Config.DefectDojo.ApplyTagsToEndpoints = [bool]$script:chkApplyTagsToEndpoints.IsChecked

    # Validate that all necessary selections have been made
    $incomplete = $false
    if (-not $selections.Product -or -not $selections.Engagement) { $incomplete = $true }
    if ($Config.Tools.SonarQube -and (-not $selections.SonarQubeTest -or -not $selections.ApiScanConfig)) { $incomplete = $true }
    if ($incomplete) {
        Write-GuiMessage 'DefectDojo selections incomplete; skipping config save.' 'WARNING'
        return
    }

    # Update the config object
    $Config.DefectDojo = @{
        ProductId         = $selections.Product.Id
        EngagementId      = $selections.Engagement.Id
        APIScanConfigId   = $selections.ApiScanConfig.Id
        SonarQubeTestId   = $selections.SonarQubeTest.Id
        BurpSuiteTestId   = $selections.BurpSuiteTest.Id
        GitHubDependabotTestId = $selections.GitHubDependabotTest.Id
        MinimumSeverity   = $selections.MinimumSeverity
        CloseOldFindings  = [bool]$script:chkDDCloseFindings.IsChecked
        ApplyTagsToFindings = [bool]$script:chkApplyTagsToFindings.IsChecked
        ApplyTagsToEndpoints = [bool]$script:chkApplyTagsToEndpoints.IsChecked
        Tags = $Config.DefectDojo.Tags  # Preserve tags that were saved before validation
    }

    Write-GuiMessage "Saving DefectDojo selections to config file..."
    foreach($key in $selections.Keys) {
        if($selections[$key]) {
            Write-GuiMessage "Selected ${key}: $($selections[$key].Name) (Id: $($selections[$key].Id))"
        }
    }
    
    try {
        Save-Config -Config $Config
        Write-GuiMessage 'DefectDojo configuration saved.'
    } catch {
        Write-GuiMessage "Failed to save DefectDojo configuration: $_" 'ERROR'
    }
}

#endregion Main Automation Logic

#region Script Entry Point

function Main {
    Initialize-GuiElements
    Register-EventHandlers
    
    Write-GuiMessage "DD Automation Launcher started."
    
    # Load data from APIs and config file
    Load-DefectDojoData
    $initialConfig = Get-Config
    Prepopulate-FormFromConfig -Config $initialConfig

    # Show the form
    $script:form.ShowDialog() | Out-Null
    if ($script:form -and $script:form.IsVisible) {
        $script:form.Close()
    }
    $script:form = $null
}

Main

#endregion Script Entry Point

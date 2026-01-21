<#
.SYNOPSIS
    DD Automation GUI Launcher
.DESCRIPTION
    Provides a graphical interface to select tools, file paths, and start DD Automation.
    This script is a refactored version of Launch.ps1, organized with clearer functions and PowerShell best practices.
#>

Param()

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

# Define script root and load modules.
# Dot-sourcing is used here because `using module` does not support dynamic paths (e.g., with $PSScriptRoot),
# which is necessary for this script to be portable.
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'modules\Logging.ps1')
. (Join-Path $scriptDir 'modules\Config.ps1')
. (Join-Path $scriptDir 'modules\GitHub.ps1')
. (Join-Path $scriptDir 'modules\TenableWAS.ps1')
. (Join-Path $scriptDir 'modules\BurpSuite.ps1')
. (Join-Path $scriptDir 'modules\EnvValidator.ps1')
. (Join-Path $scriptDir 'DefectDojo.ps1')
. (Join-Path $scriptDir 'Sonarqube.ps1')
. (Join-Path $scriptDir 'Uploader.ps1')
# Initialize logging
Initialize-Log -LogDirectory (Join-Path $PSScriptRoot 'logs') -LogFileName 'DDAutomationLauncher_Renewed.log' -Overwrite
Write-Log -Message "DD Automation Launcher started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level 'INFO'

$script:gitHubFeatureMap = [ordered]@{
    GitHubCodeQL         = 'CodeQL'
    GitHubSecretScanning = 'SecretScanning'
    GitHubDependabot     = 'Dependabot'
}

# Add Windows Forms types for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Validate environment dependencies before launching GUI
try {
    Validate-Environment
} catch {
    [System.Windows.Forms.MessageBox]::Show("Environment validation failed: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
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
    $script:lstStatus.TopIndex = $script:lstStatus.Items.Count - 1
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
    # Script-level scope allows these variables to be accessed by event handlers
    $script:form = New-Object System.Windows.Forms.Form
    $script:chkBoxes = @{}
    $script:gitHubToolKeys = [string[]]$script:gitHubFeatureMap.Keys
    $script:tools = @('TenableWAS','SonarQube','BurpSuite','DefectDojo') + $script:gitHubToolKeys

    # Form settings
    $form.Text = 'DD Automation Launcher'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(640, 900)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    # Tools GroupBox
    $grpTools = New-Object System.Windows.Forms.GroupBox
    $grpTools.Text = 'Select Tools'
    $grpTools.Size = New-Object System.Drawing.Size(600, 130)
    $grpTools.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($grpTools)

    # Create tooltip for checkboxes
    $script:toolTip = New-Object System.Windows.Forms.ToolTip
    $script:toolTip.ShowAlways = $true

    # Tool Checkboxes (uniform spacing even with longer labels)
    $columnCount = 3
    $columnWidth = 180
    for ($i = 0; $i -lt $tools.Count; $i++) {
        $name = $tools[$i]
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = $name
        $chk.AutoSize = $true
        $x = 10 + ($i % $columnCount) * $columnWidth
        $y = 20 + [Math]::Floor($i / $columnCount) * 30
        $chk.Location = New-Object System.Drawing.Point($x, $y)
        $chk.Checked = $true
        $grpTools.Controls.Add($chk)
        $chkBoxes[$name] = $chk
        
        # Add tooltips for each checkbox
        switch ($name) {
            'TenableWAS' { $script:toolTip.SetToolTip($chk, "Downloads selected Tenable WAS scans and uploads to DefectDojo. Each scan creates/updates its own test.") }
            'SonarQube' { $script:toolTip.SetToolTip($chk, "This checkbox uses the built-in SonarQube DefectDojo functionality (IF SET UP - see wiki if not), to process SonarQube into DefectDojo") }
            'BurpSuite' { $script:toolTip.SetToolTip($chk, "Scans the specified folder for BurpSuite XML reports and uploads them to DefectDojo.") }
            'DefectDojo' { $script:toolTip.SetToolTip($chk, "This checkbox uploads all other tools to DefectDojo. If unchecked, other tool will execute but not upload.") }
            'GitHubCodeQL' {
                $chk.Text = 'GitHub CodeQL'
                $script:toolTip.SetToolTip($chk, "Download and process GitHub CodeQL SARIF reports, optionally upload to DefectDojo.")
            }
            'GitHubSecretScanning' {
                $chk.Text = 'GitHub Secret Scanning'
                $script:toolTip.SetToolTip($chk, "Download GitHub Secret Scanning JSON alerts, optionally upload to DefectDojo.")
            }
            'GitHubDependabot' {
                $chk.Text = 'GitHub Dependabot'
                $script:toolTip.SetToolTip($chk, "Download GitHub Dependabot alerts JSON and upload to DefectDojo when configured.")
            }
        }
    }

    # BurpSuite Controls
    $lblBurp = New-Object System.Windows.Forms.Label -Property @{ Text = 'BurpSuite XML Folder:'; AutoSize = $true; Location = New-Object System.Drawing.Point(10, 150) }
    $script:txtBurp = New-Object System.Windows.Forms.TextBox -Property @{ Size = New-Object System.Drawing.Size(370, 20); Location = New-Object System.Drawing.Point(150, 148) }
    $script:btnBrowse = New-Object System.Windows.Forms.Button -Property @{ Text = 'Browse...'; Location = New-Object System.Drawing.Point(540, 145); Size = New-Object System.Drawing.Size(80, 24) }
    $form.Controls.AddRange(@($lblBurp, $txtBurp, $btnBrowse))

    # TenableWAS Controls
    $lblTenable = New-Object System.Windows.Forms.Label -Property @{ Text = 'TenableWAS Scans:'; AutoSize = $true; Location = New-Object System.Drawing.Point(10, 180) }
    $script:txtTenableSearch = New-Object System.Windows.Forms.TextBox -Property @{ 
        Size = New-Object System.Drawing.Size(330, 20); 
        Location = New-Object System.Drawing.Point(150, 180)
        PlaceholderText = "Search scans by name..."
    }
    $script:lstTenableScans = New-Object System.Windows.Forms.CheckedListBox -Property @{ 
        Size = New-Object System.Drawing.Size(330, 70); 
        Location = New-Object System.Drawing.Point(150, 205); 
        CheckOnClick = $true 
    }
    $script:btnRefreshTenable = New-Object System.Windows.Forms.Button -Property @{ Text = 'Refresh'; Location = New-Object System.Drawing.Point(490, 205); Size = New-Object System.Drawing.Size(60, 25) }
    $form.Controls.AddRange(@($lblTenable, $script:txtTenableSearch, $script:lstTenableScans, $script:btnRefreshTenable))

    # GitHub organization controls
    $lblGitHubOrgs = New-Object System.Windows.Forms.Label -Property @{ Text = 'GitHub Orgs:'; AutoSize = $true; Location = New-Object System.Drawing.Point(10, 300) }
    $script:txtGitHubOrgs = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(150, 298)
        Size     = New-Object System.Drawing.Size(330, 20)
        Enabled  = $true
    }
    $form.Controls.AddRange(@($lblGitHubOrgs, $script:txtGitHubOrgs))
    $script:toolTip.SetToolTip($script:txtGitHubOrgs, 'Enter one or more GitHub organizations, separated by commas.')

    # DefectDojo Controls
    $ddControls = @{
        lblDDProduct            = [Tuple]::Create('DefectDojo Product:', 330)
        lblDDEng                = [Tuple]::Create('Engagement:', 360)
        lblDDApiScan            = [Tuple]::Create('API Scan Config:', 390)
        lblDDTestSonar          = [Tuple]::Create('SonarQube Test:', 420)
        lblDDTestBurp           = [Tuple]::Create('BurpSuite Test:', 450)
        lblDDTestDependabot     = [Tuple]::Create('Dependabot Test:', 480)
        lblDDSeverity           = [Tuple]::Create('Minimum Severity:', 510)
    }

    foreach ($name in $ddControls.Keys) {
        $label = New-Object System.Windows.Forms.Label -Property @{ Text = $ddControls[$name].Item1; AutoSize = $true; Location = New-Object System.Drawing.Point(10, $ddControls[$name].Item2) }
        $comboName = $name.Replace('lblDD','cmbDD')
        $combobox = New-Object System.Windows.Forms.ComboBox -Property @{ DropDownStyle = 'DropDownList'; Location = New-Object System.Drawing.Point(150, ($ddControls[$name].Item2 - 2)); Size = New-Object System.Drawing.Size(220, 20); Enabled = $false }
        $form.Controls.AddRange(@($label, $combobox))
        Set-Variable -Name $comboName -Scope Script -Value $combobox
    }
    $script:cmbDDSeverity.Items.AddRange(@('Info','Low','Medium','High','Critical'))

    # Close Old Findings on Reimport Checkbox
    $lblDDCloseFindings = New-Object System.Windows.Forms.Label -Property @{ Text = 'Close Old Findings:'; AutoSize = $true; Location = New-Object System.Drawing.Point(10, 540) }
    $script:chkDDCloseFindings = New-Object System.Windows.Forms.CheckBox -Property @{ AutoSize = $true; Location = New-Object System.Drawing.Point(150, 542); Checked = $false; Enabled = $false }
    $form.Controls.AddRange(@($lblDDCloseFindings, $script:chkDDCloseFindings))
    $script:toolTip.SetToolTip($script:chkDDCloseFindings, 'When checked, old findings will be closed on reimport. When unchecked, previous findings are preserved.')

    # Manual Upload (DefectDojo CLI) GroupBox
    $grpManualTool = New-Object System.Windows.Forms.GroupBox
    $grpManualTool.Text = 'Manual Upload (DefectDojo CLI)'
    $grpManualTool.Size = New-Object System.Drawing.Size(580, 80)
    $grpManualTool.Location = New-Object System.Drawing.Point(10, 570)
    $form.Controls.Add($grpManualTool)

    # Launch DefectDojo CLI Button
    $script:btnLaunchTool = New-Object System.Windows.Forms.Button
    $script:btnLaunchTool.Text = 'Launch DefectDojo CLI'
    $script:btnLaunchTool.Size = New-Object System.Drawing.Size(150, 30)
    $script:btnLaunchTool.Location = New-Object System.Drawing.Point(10, 20)
    $grpManualTool.Controls.Add($script:btnLaunchTool)

    # Info label for Manual Upload
    $lblManualInfo = New-Object System.Windows.Forms.Label
    $lblManualInfo.Text = 'Opens defectdojo-cli.exe in a new console; no data is passed.'
    $lblManualInfo.AutoSize = $true
    $lblManualInfo.Location = New-Object System.Drawing.Point(170, 27)
    $grpManualTool.Controls.Add($lblManualInfo)

    # Add tooltip for Launch DefectDojo CLI button
    $script:toolTip.SetToolTip($script:btnLaunchTool, "Runs modules\defectdojo-cli.exe in a separate window (stays open).")

    # Status ListBox (moved down to accommodate new group)
    $script:lstStatus = New-Object System.Windows.Forms.ListBox -Property @{ Size = New-Object System.Drawing.Size(600, 130); Location = New-Object System.Drawing.Point(10, 660) }
    $form.Controls.Add($lstStatus)

    # Action Buttons
    $script:btnLaunch = New-Object System.Windows.Forms.Button -Property @{ Text = 'GO'; Location = New-Object System.Drawing.Point(440, 795); Size = New-Object System.Drawing.Size(80, 30) }
    $script:btnCancel = New-Object System.Windows.Forms.Button -Property @{ Text = 'Cancel'; Location = New-Object System.Drawing.Point(540, 795); Size = New-Object System.Drawing.Size(80, 30) }
    
    # Add completion message label
    $script:lblComplete = New-Object System.Windows.Forms.Label -Property @{ 
        Text = ""; 
        Location = New-Object System.Drawing.Point(10, 830); 
        Size = New-Object System.Drawing.Size(400, 25);
        Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold);
        ForeColor = [System.Drawing.Color]::Green;
        Visible = $false
    }

    
    $form.Controls.AddRange(@($btnLaunch, $btnCancel, $script:lblComplete))
}

#endregion GUI Creation

#region Event Handlers

function Register-EventHandlers {
    # Tool selection checkboxes
    $chkBoxes['BurpSuite'].Add_CheckedChanged({
        $script:txtBurp.Enabled = $this.Checked
        $script:btnBrowse.Enabled = $this.Checked
        $script:cmbDDTestBurp.Enabled = $this.Checked -and $script:cmbDDTestBurp.Items.Count -gt 0
    })
    $chkBoxes['TenableWAS'].Add_CheckedChanged({
        $script:lstTenableScans.Enabled = $this.Checked
        $script:txtTenableSearch.Enabled = $this.Checked
        $script:btnRefreshTenable.Enabled = $this.Checked
        if ($this.Checked -and $script:lstTenableScans.Items.Count -eq 0) {
            Load-TenableScans
        }
    })
    $script:btnRefreshTenable.Add_Click({ Load-TenableScans })
    
    # Tenable scan search/filter
    $script:txtTenableSearch.Add_TextChanged({
        Apply-TenableSearch -SearchTerm $this.Text
    })

    $chkBoxes['SonarQube'].Add_CheckedChanged({
        $script:cmbDDTestSonar.Enabled = $this.Checked -and $script:cmbDDTestSonar.Items.Count -gt 0
        $script:cmbDDApiScan.Enabled = $this.Checked -and $script:cmbDDApiScan.Items.Count -gt 0
    })
    foreach ($key in $script:gitHubToolKeys) {
        $chkBoxes[$key].Add_CheckedChanged({
            Update-GitHubControlState
        })
    }
    $chkBoxes['DefectDojo'].Add_CheckedChanged({
        $script:cmbDDSeverity.Enabled = $this.Checked
        $script:chkDDCloseFindings.Enabled = $this.Checked
    })

    # Browse for BurpSuite folder
    $btnBrowse.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($folderDialog.ShowDialog() -eq 'OK') {
            $script:txtBurp.Text = $folderDialog.SelectedPath
        }
    })

    # DefectDojo dropdowns
    $cmbDDProduct.Add_SelectedIndexChanged({ Handle-ProductChange })
    $cmbDDEng.Add_SelectedIndexChanged({ Handle-EngagementChange })

    # Launch DefectDojo CLI button
    $btnLaunchTool.Add_Click({ Invoke-ExternalTool })

    # Main action buttons
    $btnLaunch.Add_Click({ Invoke-Automation })
    $btnCancel.Text = "Close"  # Rename to "Close" for clarity
    $btnCancel.Add_Click({ $script:form.Close() })

    Update-GitHubControlState
}

function Update-GitHubControlState {
    $anyGitHub = $false
    foreach ($key in $script:gitHubToolKeys) {
        if ($script:chkBoxes.ContainsKey($key) -and $script:chkBoxes[$key].Checked) {
            $anyGitHub = $true
            break
        }
    }

    $script:txtGitHubOrgs.Enabled = $anyGitHub
    $script:cmbDDTestDependabot.Enabled = $script:chkBoxes['GitHubDependabot'].Checked -and $script:cmbDDTestDependabot.Items.Count -gt 0
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
        $script:cmbDDEng.DisplayMember = 'Name'; $script:cmbDDEng.ValueMember = 'Id'
        $script:cmbDDEng.Enabled = $true

        # Clear subsequent dropdowns
        @($script:cmbDDTestSonar, $script:cmbDDTestBurp) | ForEach-Object {
            $_.Enabled = $false; $_.Items.Clear()
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
            $cmb.ValueMember = 'Id'
        }
        # Set DisplayMember based on needed display, Title works for most Dojo tests
        $script:cmbDDTestSonar.DisplayMember = 'Title'     # Show test type title for SonarQube
        $script:cmbDDTestBurp.DisplayMember = 'Title'      # Show test type title for BurpSuite
        $script:cmbDDTestDependabot.DisplayMember = 'Title'

        # Re-evaluate enabled state based on tool selection and if tests were found
        $script:cmbDDTestSonar.Enabled  = $script:chkBoxes['SonarQube'].Checked  -and $tests.Count -gt 0
        $script:cmbDDTestBurp.Enabled   = $script:chkBoxes['BurpSuite'].Checked -and $tests.Count -gt 0
        $script:cmbDDTestDependabot.Enabled = $script:chkBoxes['GitHubDependabot'].Checked -and $tests.Count -gt 0
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
        $script:btnLaunchTool.Enabled = $false
        
        # Compute tool path
        $toolPath = Join-Path $PSScriptRoot 'modules\defectdojo-cli.exe'
        
        # Check if tool exists
        if (-not (Test-Path -Path $toolPath -PathType Leaf)) {
            [System.Windows.Forms.MessageBox]::Show(
                "DefectDojo CLI not found at modules\defectdojo-cli.exe. Please add the EXE to the modules folder.", 
                "Tool Not Found", 
                [System.Windows.Forms.MessageBoxButtons]::OK, 
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $script:btnLaunchTool.Enabled = $true
            return
        }
        
        # Ensure CLI sees expected API token
        $apiKey = $env:DOJO_API_KEY
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Write-GuiMessage "DOJO_API_KEY environment variable is not set; cannot launch DefectDojo CLI." 'ERROR'
            [System.Windows.Forms.MessageBox]::Show(
                "DOJO_API_KEY is not configured. Please populate the variable and relaunch.",
                "Missing Environment Variable",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            $script:btnLaunchTool.Enabled = $true
            return
        }

        try {
            [System.Environment]::SetEnvironmentVariable('DD_CLI_API_TOKEN', $apiKey, [System.EnvironmentVariableTarget]::User)
            $env:DD_CLI_API_TOKEN = $apiKey
            Write-GuiMessage "DD_CLI_API_TOKEN synchronized with DOJO_API_KEY."
        } catch {
            Write-GuiMessage "Failed to set DD_CLI_API_TOKEN: $_" 'ERROR'
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to update DD_CLI_API_TOKEN. See log for details.",
                "Environment Variable Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            $script:btnLaunchTool.Enabled = $true
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
        $script:btnLaunchTool.Enabled = $true
    }
}

#endregion Event Handlers

#region Data Loading and Pre-population

function Load-TenableScans {
    Write-GuiMessage "Loading TenableWAS scans..."
    try {
        $scans = Get-TenableWASScanConfigs
        $script:allTenableScans = @()
        $script:lstTenableScans.Items.Clear()
        if ($scans) {
            $script:allTenableScans = $scans
            Apply-TenableSearch -SearchTerm ($script:txtTenableSearch.Text)
        }
        $script:lstTenableScans.DisplayMember = "Name"
        $script:lstTenableScans.ValueMember = "Id"
        
        # Restore selection if config has names
        $config = Get-Config
        if ($config.TenableWASScanNames -and $config.TenableWASScanNames.Count -gt 0) {
            for ($i = 0; $i -lt $script:lstTenableScans.Items.Count; $i++) {
                $item = $script:lstTenableScans.Items[$i]
                if ($item.Name -in $config.TenableWASScanNames) {
                    $script:lstTenableScans.SetItemChecked($i, $true)
                }
            }
        }
    } catch {
        Write-GuiMessage "Failed to load TenableWAS scans: $_" 'ERROR'
    }
}

function Apply-TenableSearch {
    param([string]$SearchTerm)

    # Preserve current checked IDs
    $checkedIds = @()
    for ($i = 0; $i -lt $script:lstTenableScans.Items.Count; $i++) {
        if ($script:lstTenableScans.GetItemChecked($i)) {
            $checkedIds += $script:lstTenableScans.Items[$i].Id
        }
    }

    $script:lstTenableScans.Items.Clear()
    if (-not $script:allTenableScans) { return }

    $term = $SearchTerm
    $filtered = if ([string]::IsNullOrWhiteSpace($term)) { 
        $script:allTenableScans 
    } else {
        $script:allTenableScans | Where-Object { $_.Name -like "*${term}*" }
    }

    foreach ($scan in $filtered) {
        $null = $script:lstTenableScans.Items.Add($scan)
    }

    # Re-check items that were previously checked
    for ($i = 0; $i -lt $script:lstTenableScans.Items.Count; $i++) {
        if ($script:lstTenableScans.Items[$i].Id -in $checkedIds) {
            $script:lstTenableScans.SetItemChecked($i, $true)
        }
    }
}

function Load-DefectDojoData {
    if ($script:chkBoxes['DefectDojo'].Checked) {
        Write-GuiMessage 'Loading DefectDojo products...'
        try {
            $products = Get-DefectDojoProducts
            $script:cmbDDProduct.Items.Clear()
            foreach ($p in $products) { $script:cmbDDProduct.Items.Add($p) | Out-Null }
            $script:cmbDDProduct.DisplayMember = 'Name'; $script:cmbDDProduct.ValueMember = 'Id'
            $script:cmbDDProduct.Enabled = $true
        } catch {
            Write-GuiMessage "Failed to load DefectDojo products: $_" 'ERROR'
        }
    }

    if ($script:chkBoxes['SonarQube'].Checked) {
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
            $script:cmbDDApiScan.DisplayMember = 'Name'; $script:cmbDDApiScan.ValueMember = 'Id'
            $script:cmbDDApiScan.Enabled = $true
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
            $script:chkBoxes[$tool].Checked = Get-GitHubFeatureState -Config $Config -ToolKey $tool
        }
        elseif ($Config.Tools.ContainsKey($tool)) {
            $script:chkBoxes[$tool].Checked = [bool]$Config.Tools[$tool]
        }
        else {
            $Config.Tools[$tool] = $script:chkBoxes[$tool].Checked
        }
    }
    Update-GitHubControlState

    # Enable DefectDojo-dependent controls if DefectDojo checkbox is checked
    # (setting .Checked programmatically doesn't fire CheckedChanged event)
    if ($script:chkBoxes['DefectDojo'].Checked) {
        $script:cmbDDSeverity.Enabled = $true
        $script:chkDDCloseFindings.Enabled = $true
    }

    if ($script:chkBoxes['TenableWAS'].Checked) {
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
                $script:form.Update() # Allow UI to update
                
                if ($Config.DefectDojo.EngagementId) {
                    $selectedEngagement = $script:cmbDDEng.Items | Where-Object { $_.Id -eq $Config.DefectDojo.EngagementId }
                    if ($selectedEngagement) {
                        $script:cmbDDEng.SelectedItem = $selectedEngagement
                        Handle-EngagementChange
                        $script:form.Update()

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
            $script:chkDDCloseFindings.Checked = $Config.DefectDojo.CloseOldFindings
        }
    }
    Write-GuiMessage "Pre-population complete."
}


#endregion Data Loading and Pre-population

#region Main Automation Logic

function Invoke-Automation {
    try {
        # Disable the launch button while processing
        $script:btnLaunch.Enabled = $false
        $script:lblComplete.Visible = $false
        
        $config = Get-Config

        # Validate GUI inputs
        if ($script:chkBoxes['BurpSuite'].Checked -and -not (Test-Path -Path $script:txtBurp.Text -PathType Container)) {
            [System.Windows.Forms.MessageBox]::Show("Please select a valid BurpSuite XML folder.", "Validation Error", "OK", "Error") | Out-Null
            $script:btnLaunch.Enabled = $true
            return
        }

        # Update config from GUI selections
        foreach ($tool in $script:tools) {
            if ($script:gitHubFeatureMap.Contains($tool)) {
                Set-GitHubFeatureState -Config $config -ToolKey $tool -Value $script:chkBoxes[$tool].Checked
            }
            else {
                $config.Tools[$tool] = $script:chkBoxes[$tool].Checked
            }
        }
        if ($config.Tools.BurpSuite) { $config.Paths.BurpSuiteXmlFolder = $script:txtBurp.Text }
        
        $selectedScans = $script:lstTenableScans.CheckedItems
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
                $selectedToolLabels += $script:chkBoxes[$tool].Text
            }
        }
        Write-GuiMessage "Selected Tools: $($selectedToolLabels -join ', ')"

        # Process TenableWAS
        if ($config.Tools.TenableWAS) {
            Process-TenableWAS -Config $config
        }

        # Process SonarQube
        if ($config.Tools.SonarQube) {
            Process-SonarQube -Config $config
        }

        # Process BurpSuite
        if ($config.Tools.BurpSuite) {
            Process-BurpSuite -Config $config
        }

        # Process GitHub CodeQL
        if (Get-GitHubFeatureState -Config $config -ToolKey 'GitHubCodeQL') {
            Process-GitHubCodeQL -Config $config
        }

        # Process GitHub Secret Scanning
        if (Get-GitHubFeatureState -Config $config -ToolKey 'GitHubSecretScanning') {
            Process-GitHubSecretScanning -Config $config
        }

        # Process GitHub Dependabot alerts
        if (Get-GitHubFeatureState -Config $config -ToolKey 'GitHubDependabot') {
            Process-GitHubDependabot -Config $config
        }

        # Save DefectDojo selections back to config
        if ($config.Tools.DefectDojo) {
            Save-DefectDojoConfig -Config $config
        }

        # Expose the updated config to the parent session for potential post-script actions
        Set-Variable -Name Config -Scope Global -Value $config
        Write-GuiMessage 'Configuration stored in global: $Config. Tasks completed successfully!'

        # Show completion message
        $script:lblComplete.Text = "Complete! Ready for next task."
        $script:lblComplete.Visible = $true
        
        # Re-enable the launch button to allow for additional tasks
        $script:btnLaunch.Enabled = $true

    } catch {
        Write-GuiMessage "An unexpected error occurred: $_" 'ERROR'
        $script:btnLaunch.Enabled = $true
    }
}

function Process-TenableWAS {
    param([hashtable]$Config)

    if (-not $Config.TenableWASSelectedScans -or $Config.TenableWASSelectedScans.Count -eq 0) {
        Write-GuiMessage "No TenableWAS scans selected." 'WARNING'
        return
    }

    # Initialize DefectDojo-specific variables if DefectDojo is enabled
    if ($Config.Tools.DefectDojo) {
        # Verify engagement is selected (required for test creation)
        $engagement = $script:cmbDDEng.SelectedItem
        if (-not $engagement) {
            Write-GuiMessage "No DefectDojo engagement selected; cannot create TenableWAS tests." 'ERROR'
            return
        }

        # Get test_type ID dynamically by looking up 'Tenable Scan' parser name
        # This ensures compatibility across different DefectDojo instances where test type IDs may differ
        try {
            $tenableTestTypeId = Get-DefectDojoTestType -TestTypeName 'Tenable Scan'
            Write-GuiMessage "Resolved 'Tenable Scan' test type to ID: $tenableTestTypeId"
        } catch {
            Write-GuiMessage "Failed to lookup 'Tenable Scan' test type: $_" 'ERROR'
            return
        }

        # Retrieve existing tests once for efficiency
        $existingTests = @(Get-DefectDojoTests -EngagementId $engagement.Id)
    }

    $uploadErrors = 0
    $totalScans = $Config.TenableWASSelectedScans.Count

    foreach ($scan in $Config.TenableWASSelectedScans) {
        Write-GuiMessage "Starting TenableWAS scan export (Scan: $($scan.Name) - ID: $($scan.Id))"
        try {
            # Step 1: Export scan report
            $exportedFile = Export-TenableWASScan -ScanName $scan.Name
            Write-GuiMessage "TenableWAS scan export completed: $exportedFile"

            if ($Config.Tools.DefectDojo) {
                Write-GuiMessage "Processing TenableWAS scan for DefectDojo upload..."

                # Step 2: Determine test name
                $serviceName = "$($scan.Name) (Tenable WAS)"

                # Step 3: Check if test exists
                $existingTest = $existingTests | Where-Object {
                    $_.Title -in @($serviceName, $scan.Name, "$($scan.Name) (Tenable)")
                } | Select-Object -First 1

                if (-not $existingTest) {
                    # Step 4a: Create new test
                    Write-GuiMessage "Creating new DefectDojo test: $serviceName"
                    try {
                        $newTest = New-DefectDojoTest -EngagementId $engagement.Id -TestName $serviceName -TestType $tenableTestTypeId
                        Write-GuiMessage "Test created successfully: $serviceName (ID: $($newTest.Id))"
                        $existingTests = @($existingTests) + $newTest  # Add to cache
                        $testId = $newTest.Id
                    } catch {
                        $errorMsg = $_.Exception.Message
                        Write-GuiMessage "Failed to create test ${serviceName}: $errorMsg" 'ERROR'
                        $uploadErrors++
                        continue  # Skip to next scan
                    }
                } else {
                    # Step 4b: Use existing test
                    Write-GuiMessage "Using existing DefectDojo test: $($existingTest.Title) (ID: $($existingTest.Id))"
                    $testId = $existingTest.Id
                }

                # Step 5: Upload scan to test
                $filePathString = ([string]$exportedFile).Trim()
                Upload-DefectDojoScan -FilePath $filePathString -TestId $testId -ScanType 'Tenable Scan' -CloseOldFindings $script:chkDDCloseFindings.Checked
                Write-GuiMessage "TenableWAS scan report uploaded successfully to DefectDojo test: $serviceName"
            }
        } catch {
            $uploadErrors++
            Write-GuiMessage "TenableWAS processing failed for $($scan.Name): $_" 'ERROR'
        }
    }

    # Summary reporting
    if ($Config.Tools.DefectDojo) {
        if ($uploadErrors -eq 0) {
            Write-GuiMessage "All $totalScans TenableWAS scans uploaded successfully to DefectDojo"
        } else {
            $successCount = $totalScans - $uploadErrors
            Write-GuiMessage "TenableWAS upload completed: $successCount successful, $uploadErrors failed" 'WARNING'
        }
    }
}

function Process-SonarQube {
    param([hashtable]$Config)
    Write-GuiMessage "Processing SonarQube scan..."
    try {
        $apiScanConfig = $script:cmbDDApiScan.SelectedItem
        $test = $script:cmbDDTestSonar.SelectedItem
        Invoke-SonarQubeProcessing -ApiScanConfiguration $apiScanConfig.Id -Test $test.Id
        Write-GuiMessage "SonarQube processing completed for test $($test.Name)"
    } catch {
        Write-GuiMessage "SonarQube processing failed: $_" 'ERROR'
    }
}

function Process-BurpSuite {
    param([hashtable]$Config)
    Write-GuiMessage "Starting BurpSuite XML report processing..."
    try {
        # Get XML files from configured folder
        $xmlFiles = Get-BurpSuiteReports -FolderPath $Config.Paths.BurpSuiteXmlFolder

        if (-not $xmlFiles -or $xmlFiles.Count -eq 0) {
            Write-GuiMessage "No BurpSuite XML files found in folder: $($Config.Paths.BurpSuiteXmlFolder)" 'WARNING'
            return
        }

        Write-GuiMessage "Found $($xmlFiles.Count) BurpSuite XML report(s)"

        if ($Config.Tools.DefectDojo) {
            Write-GuiMessage "Uploading BurpSuite report to DefectDojo..."

            # Get the specifically selected BurpSuite test
            $burpTest = $script:cmbDDTestBurp.SelectedItem
            if (-not $burpTest) {
                Write-GuiMessage "No BurpSuite test selected for DefectDojo upload" 'WARNING'
                return
            }

            # Upload only the first XML file found
            $xmlFile = $xmlFiles[0]
            $fileName = [System.IO.Path]::GetFileName($xmlFile)

            if ($xmlFiles.Count -gt 1) {
                Write-GuiMessage "Multiple XML files found. Uploading only: $fileName" 'WARNING'
                Write-GuiMessage "Other files will be ignored. Process one scan at a time." 'WARNING'
            }

            try {
                Write-GuiMessage "Uploading $fileName to DefectDojo test: $($burpTest.Title)"

                # Ensure file path is explicitly converted to string
                $filePathString = ([string]$xmlFile).Trim()

                # Upload to DefectDojo using Burp Scan type
                Upload-DefectDojoScan -FilePath $filePathString -TestId $burpTest.Id -ScanType 'Burp Scan' -CloseOldFindings $script:chkDDCloseFindings.Checked
                Write-GuiMessage "Successfully uploaded $fileName to DefectDojo test: $($burpTest.Title)"
            } catch {
                Write-GuiMessage "Failed to upload $fileName : $_" 'ERROR'
            }
        }
    } catch {
        Write-GuiMessage "BurpSuite processing failed: $_" 'ERROR'
    }
}

function Process-GitHubCodeQL {
    param([hashtable]$Config)
    Write-GuiMessage "Starting GitHub CodeQL download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-GuiMessage "No GitHub organizations configured. Skipping GitHub processing." 'WARNING'
            return
        }

        Write-GuiMessage ("Processing GitHub organizations: {0}" -f ($orgs -join ', '))

        GitHub-CodeQLDownload -Owners $orgs
        Write-GuiMessage "GitHub CodeQL download completed."

        if ($Config.Tools.DefectDojo) {
            Write-GuiMessage "Uploading GitHub CodeQL reports to DefectDojo..."
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubCodeScanning'
            $sarifFiles = Get-ChildItem -Path $downloadRoot -Filter '*.sarif' -Recurse | Select-Object -ExpandProperty FullName
            $uploadErrors = 0

            $engagement = $script:cmbDDEng.SelectedItem
            if (-not $engagement) {
                Write-GuiMessage "No DefectDojo engagement selected; skipping GitHub uploads." 'WARNING'
                return
            }
            $existingTests = @(Get-DefectDojoTests -EngagementId $engagement.Id)
            
            foreach ($file in $sarifFiles) {
                try {
                    # Extract service name from SARIF file
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)

                    # Remove numeric suffixes
                    $baseServiceName = $fileName -replace '-\d+$', ''
                    $repoNameOnly = $baseServiceName
                    if ($baseServiceName -match '^(?<org>[^-]+)-(?<repo>.+)$') {
                        $repoNameOnly = $Matches['repo']
                    }

                    $serviceNameCore = $repoNameOnly
                    $serviceName = "$serviceNameCore (CodeQL)"

                    # Check if test exists, create if not
                    $existingTest = $existingTests | Where-Object { $_.title -in @($serviceName, $serviceNameCore, $repoNameOnly) } | Select-Object -First 1

                    if (-not $existingTest) {
                        Write-GuiMessage "Creating new test: $serviceName"
                        try {
                            $newTest = New-DefectDojoTest -EngagementId $engagement.Id -TestName $serviceName -TestType 20 #hard coded in DD why
                            Write-GuiMessage "Test created successfully: $serviceName (ID: $($newTest.Id))"
                            $existingTests = @($existingTests) + $newTest
                        } catch {
                            Write-GuiMessage "Failed to create test $serviceName : $_" 'ERROR'
                            continue
                        }
                        #Upload with new test ID
                        Upload-DefectDojoScan -FilePath $file -TestId $newTest.Id -ScanType 'SARIF' -CloseOldFindings $script:chkDDCloseFindings.Checked
                    } else {
                        Write-GuiMessage "Using existing test: $($existingTest.Title) (ID: $($existingTest.Id))"
                        #Upload with existing test ID
                        Upload-DefectDojoScan -FilePath $file -TestId $existingTest.Id -ScanType 'SARIF' -CloseOldFindings $script:chkDDCloseFindings.Checked
                    }


                } catch {
                    $uploadErrors++
                    Write-GuiMessage "Failed to upload $file to DefectDojo: $_" 'ERROR'
                }
            }

            if ($uploadErrors -eq 0) {
                Write-GuiMessage "GitHub CodeQL reports uploaded successfully to DefectDojo"
                # Clean up downloaded files after successful uploads
                try {
                    Write-GuiMessage "Cleaning up downloaded GitHub CodeQL files..."
                    Remove-Item -Path $downloadRoot -Recurse -Force
                    Write-GuiMessage "GitHub CodeQL download directory cleaned up successfully"
                } catch {
                    Write-GuiMessage "Failed to clean up download directory: $_" 'WARNING'
                }
            } else {
                Write-GuiMessage "GitHub CodeQL upload completed with $uploadErrors error(s). Download files retained for review." 'WARNING'
            }
        }
    } catch {
        Write-GuiMessage "GitHub CodeQL processing failed: $_" 'ERROR'
    }
}

function Process-GitHubSecretScanning {
    param([hashtable]$Config)
    Write-GuiMessage "Starting GitHub Secret Scanning download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-GuiMessage 'No GitHub organizations configured. Skipping GitHub Secret Scanning.' 'WARNING'
            return
        }

        Write-GuiMessage ("Processing GitHub organizations for secret scanning: {0}" -f ($orgs -join ', '))
        GitHub-SecretScanDownload -Owners $orgs
        Write-GuiMessage "GitHub Secret Scanning download completed."

        if ($Config.Tools.DefectDojo) {
            Write-GuiMessage "Uploading GitHub Secret Scanning reports to DefectDojo..."
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubSecretScanning'
            $jsonFiles = Get-ChildItem -Path $downloadRoot -Filter '*-secrets.json' -Recurse | Select-Object -ExpandProperty FullName
            $uploadErrors = 0

            foreach ($file in $jsonFiles) {
                try {
                    # Extract service name from JSON file (remove suffixes and org prefix)
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)
                    $repoName = $fileName -replace '-secrets$', ''
                    $baseServiceName = $repoName -replace '-\d+$', ''
                    $repoNameOnly = $baseServiceName
                    if ($baseServiceName -match '^(?<org>[^-]+)-(?<repo>.+)$') {
                        $repoNameOnly = $Matches['repo']
                    }

                    # Append tool type to test name
                    $serviceName = "$repoNameOnly (Secret Scanning)"

                    # Check if test exists, create if not
                    $engagement = $script:cmbDDEng.SelectedItem
                    $existingTests = Get-DefectDojoTests -EngagementId $engagement.Id
                    $existingTest = $existingTests | Where-Object {
                        $_.title -in @(
                            $serviceName,
                            "$baseServiceName (Secret Scanning)",
                            "$repoName (Secret Scanning)"
                        )
                    } | Select-Object -First 1

                    if (-not $existingTest) {
                        Write-GuiMessage "Creating new test: $serviceName"
                        try {
                            $newTest = New-DefectDojoTest -EngagementId $engagement.Id -TestName $serviceName -TestType 215 #also hard coded in DD why
                            Write-GuiMessage "Test created successfully: $serviceName (ID: $($newTest.Id))"
                        } catch {
                            Write-GuiMessage "Failed to create test $serviceName : $_" 'ERROR'
                            continue
                        }
                        #Upload with new test ID
                        Upload-DefectDojoScan -FilePath $file -TestId $newTest.Id -ScanType 'Universal Parser - GitHub Secret Scanning' -CloseOldFindings $script:chkDDCloseFindings.Checked
                    } else {
                        Write-GuiMessage "Using existing test: $serviceName (ID: $($existingTest.Id))"
                        #Upload with existing test ID
                        Upload-DefectDojoScan -FilePath $file -TestId $existingTest.Id -ScanType 'Universal Parser - GitHub Secret Scanning' -CloseOldFindings $script:chkDDCloseFindings.Checked
                    }
                } catch {
                    $uploadErrors++
                    Write-GuiMessage "Failed to upload $file to DefectDojo: $_" 'ERROR'
                }
            }

            if ($uploadErrors -eq 0) {
                Write-GuiMessage "GitHub Secret Scanning reports uploaded successfully to DefectDojo"
                # Clean up downloaded files after successful uploads
                try {
                    Write-GuiMessage "Cleaning up downloaded GitHub Secret Scanning files..."
                    Remove-Item -Path $downloadRoot -Recurse -Force
                    Write-GuiMessage "GitHub Secret Scanning download directory cleaned up successfully"
                } catch {
                    Write-GuiMessage "Failed to clean up download directory: $_" 'WARNING'
                }
            } else {
                Write-GuiMessage "GitHub Secret Scanning upload completed with $uploadErrors error(s). Download files retained for review." 'WARNING'
            }
        }
    } catch {
        Write-GuiMessage "GitHub Secret Scanning processing failed: $_" 'ERROR'
    }
}

function Process-GitHubDependabot {
    param([hashtable]$Config)
    Write-GuiMessage "Starting GitHub Dependabot download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-GuiMessage 'No GitHub organizations configured. Skipping Dependabot export.' 'WARNING'
            return
        }

        Write-GuiMessage ("Processing GitHub organizations for Dependabot: {0}" -f ($orgs -join ', '))
        $dependabotFiles = GitHub-DependabotDownload -Owners $orgs
        Write-GuiMessage "GitHub Dependabot download completed."

        if (-not $dependabotFiles -or $dependabotFiles.Count -eq 0) {
            Write-GuiMessage 'No open Dependabot alerts downloaded; skipping uploads.'
            return
        }

        if ($Config.Tools.DefectDojo) {
            Write-GuiMessage "Uploading GitHub Dependabot JSON files to DefectDojo..."
            $dependabotTest = $script:cmbDDTestDependabot.SelectedItem
            if (-not $dependabotTest) {
                Write-GuiMessage 'No DefectDojo Dependabot test selected; skipping uploads.' 'WARNING'
                return
            }

            $uploadErrors = 0
            foreach ($file in $dependabotFiles) {
                try {
                    Upload-DefectDojoScan -FilePath $file -TestId $dependabotTest.Id -ScanType 'Universal Parser - GitHub Dependabot Aert5s' -CloseOldFindings $script:chkDDCloseFindings.Checked
                    Write-GuiMessage "Uploaded Dependabot JSON: $([System.IO.Path]::GetFileName($file)) to test $($dependabotTest.Name)"
                } catch {
                    $uploadErrors++
                    Write-GuiMessage "Failed to upload $file to DefectDojo: $_" 'ERROR'
                }
            }

            if ($uploadErrors -eq 0) {
                Write-GuiMessage "GitHub Dependabot JSON files uploaded successfully to $($dependabotTest.Name)"
                $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubDependabot'
                try {
                    Remove-Item -Path $downloadRoot -Recurse -Force
                    Write-GuiMessage "GitHub Dependabot download directory cleaned up successfully"
                } catch {
                    Write-GuiMessage "Failed to clean up Dependabot download directory: $_" 'WARNING'
                }
            } else {
                Write-GuiMessage "Dependabot uploads completed with $uploadErrors error(s); downloaded files retained for review." 'WARNING'
            }
        }
    } catch {
        Write-GuiMessage "GitHub Dependabot processing failed: $_" 'ERROR'
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

    # Validate that all necessary selections have been made
    $incomplete = $false
    if (-not $selections.Product -or -not $selections.Engagement) { $incomplete = $true }
    if ($Config.Tools.SonarQube -and (-not $selections.SonarQubeTest -or -not $selections.ApiScanConfig)) { $incomplete = $true }
    if ($Config.Tools.BurpSuite -and -not $selections.BurpSuiteTest) { $incomplete = $true }
    if ($dependabotEnabled -and $Config.Tools.DefectDojo -and -not $selections.GitHubDependabotTest) { $incomplete = $true }

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
        CloseOldFindings  = $script:chkDDCloseFindings.Checked
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
    $script:form.Dispose()
}

Main

#endregion Script Entry Point


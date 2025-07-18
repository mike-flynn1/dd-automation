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
. (Join-Path $scriptDir 'TenableWAS.ps1')
. (Join-Path $scriptDir 'EnvValidator.ps1')
. (Join-Path $scriptDir 'DefectDojo.ps1')
. (Join-Path $scriptDir 'Sonarqube.ps1')
. (Join-Path $scriptDir 'Uploader.ps1')

# Initialize logging
Initialize-Log -LogDirectory (Join-Path $PSScriptRoot 'logs') -LogFileName 'DDAutomationLauncher_Renewed.log' -Overwrite
Write-Log -Message "DD Automation Launcher started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level 'INFO'

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

#endregion GUI Helper Functions

#region GUI Creation

function Initialize-GuiElements {
    # Script-level scope allows these variables to be accessed by event handlers
    $script:form = New-Object System.Windows.Forms.Form
    $script:chkBoxes = @{}
    $script:tools = @('TenableWAS','SonarQube','BurpSuite','DefectDojo')

    # Form settings
    $form.Text = 'DD Automation Launcher'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(620, 700)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    # Tools GroupBox
    $grpTools = New-Object System.Windows.Forms.GroupBox
    $grpTools.Text = 'Select Tools'
    $grpTools.Size = New-Object System.Drawing.Size(580, 100)
    $grpTools.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($grpTools)

    # Tool Checkboxes
    for ($i = 0; $i -lt $tools.Count; $i++) {
        $name = $tools[$i]
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = $name
        $chk.AutoSize = $true
        $chk.Location = New-Object System.Drawing.Point((10 + ($i * 140)), 20)
        $chk.Checked = $true
        $grpTools.Controls.Add($chk)
        $chkBoxes[$name] = $chk
    }

    # BurpSuite Controls
    $lblBurp = New-Object System.Windows.Forms.Label -Property @{ Text = 'BurpSuite XML Folder:'; AutoSize = $true; Location = New-Object System.Drawing.Point(10, 120) }
    $script:txtBurp = New-Object System.Windows.Forms.TextBox -Property @{ Size = New-Object System.Drawing.Size(370, 20); Location = New-Object System.Drawing.Point(150, 118) }
    $script:btnBrowse = New-Object System.Windows.Forms.Button -Property @{ Text = 'Browse...'; Location = New-Object System.Drawing.Point(520, 115); Size = New-Object System.Drawing.Size(80, 24) }
    $form.Controls.AddRange(@($lblBurp, $txtBurp, $btnBrowse))

    # TenableWAS Controls
    $lblTenable = New-Object System.Windows.Forms.Label -Property @{ Text = 'TenableWAS Scan ID:'; AutoSize = $true; Location = New-Object System.Drawing.Point(10, 180) }
    $script:txtTenable = New-Object System.Windows.Forms.TextBox -Property @{ Size = New-Object System.Drawing.Size(370, 20); Location = New-Object System.Drawing.Point(150, 178) }
    $form.Controls.AddRange(@($lblTenable, $txtTenable))

    # DefectDojo Controls
    $ddControls = @{
        lblDDProduct      = [Tuple]::Create('DefectDojo Product:', 210)
        lblDDEng          = [Tuple]::Create('Engagement:', 240)
        lblDDApiScan      = [Tuple]::Create('API Scan Config:', 270)
        lblDDTestTenable  = [Tuple]::Create('TenableWAS Test:', 300)
        lblDDTestSonar    = [Tuple]::Create('SonarQube Test:', 330)
        lblDDTestBurp     = [Tuple]::Create('BurpSuite Test:', 360)
        lblDDSeverity     = [Tuple]::Create('Minimum Severity:', 390)
    }

    foreach ($name in $ddControls.Keys) {
        $label = New-Object System.Windows.Forms.Label -Property @{ Text = $ddControls[$name].Item1; AutoSize = $true; Location = New-Object System.Drawing.Point(10, $ddControls[$name].Item2) }
        $comboName = $name.Replace('lblDD','cmbDD')
        $combobox = New-Object System.Windows.Forms.ComboBox -Property @{ DropDownStyle = 'DropDownList'; Location = New-Object System.Drawing.Point(150, ($ddControls[$name].Item2 - 2)); Size = New-Object System.Drawing.Size(220, 20); Enabled = $false }
        $form.Controls.AddRange(@($label, $combobox))
        Set-Variable -Name $comboName -Scope Script -Value $combobox
    }
    $script:cmbDDSeverity.Items.AddRange(@('Info','Low','Medium','High','Critical'))

    # Status ListBox
    $script:lstStatus = New-Object System.Windows.Forms.ListBox -Property @{ Size = New-Object System.Drawing.Size(580, 180); Location = New-Object System.Drawing.Point(10, 420) }
    $form.Controls.Add($lstStatus)

    # Action Buttons
    $script:btnLaunch = New-Object System.Windows.Forms.Button -Property @{ Text = 'GO'; Location = New-Object System.Drawing.Point(420, 620); Size = New-Object System.Drawing.Size(80, 30) }
    $script:btnCancel = New-Object System.Windows.Forms.Button -Property @{ Text = 'Cancel'; Location = New-Object System.Drawing.Point(520, 620); Size = New-Object System.Drawing.Size(80, 30) }
    
    # Add completion message label
    $script:lblComplete = New-Object System.Windows.Forms.Label -Property @{ 
        Text = ""; 
        Location = New-Object System.Drawing.Point(10, 625); 
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
    $chkBoxes['TenableWAS'].Add_CheckedChanged({ $script:cmbDDTestTenable.Enabled = $this.Checked -and $script:cmbDDTestTenable.Items.Count -gt 0 })
    $chkBoxes['SonarQube'].Add_CheckedChanged({
        $script:cmbDDTestSonar.Enabled = $this.Checked -and $script:cmbDDTestSonar.Items.Count -gt 0
        $script:cmbDDApiScan.Enabled = $this.Checked -and $script:cmbDDApiScan.Items.Count -gt 0
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

    # Main action buttons
    $btnLaunch.Add_Click({ Invoke-Automation })
    $btnCancel.Text = "Close"  # Rename to "Close" for clarity
    $btnCancel.Add_Click({ $script:form.Close() })
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
        @($script:cmbDDTestTenable, $script:cmbDDTestSonar, $script:cmbDDTestBurp) | ForEach-Object {
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
        foreach ($cmb in @($script:cmbDDTestTenable, $script:cmbDDTestSonar, $script:cmbDDTestBurp)) {
            $cmb.Items.Clear()
            if ($tests) {
                foreach ($t in $tests) { $cmb.Items.Add($t) | Out-Null }
            }
            $cmb.DisplayMember = 'Name'; $cmb.ValueMember = 'Id'
        }

        # Re-evaluate enabled state based on tool selection and if tests were found
        $script:cmbDDTestTenable.Enabled = $script:chkBoxes['TenableWAS'].Checked -and $tests.Count -gt 0
        $script:cmbDDTestSonar.Enabled  = $script:chkBoxes['SonarQube'].Checked  -and $tests.Count -gt 0
        $script:cmbDDTestBurp.Enabled   = $script:chkBoxes['BurpSuite'].Checked -and $tests.Count -gt 0

        if (-not $tests) {
            Write-GuiMessage "No DefectDojo tests found for engagement $($selectedEngagement.Name)." 'WARNING'
        }
    } catch {
        Write-GuiMessage "Failed to load tests: $_" 'ERROR'
    }
}

#endregion Event Handlers

#region Data Loading and Pre-population

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
        if ($Config.Tools.ContainsKey($tool)) {
            $script:chkBoxes[$tool].Checked = [bool]$Config.Tools[$tool]
        }
    }

    if ($Config.TenableWASScanId ) {
        $script:txtTenable.Text = $Config.TenableWASScanId
    }

    if ($Config.Paths.ContainsKey('BurpSuiteXmlFolder')) {
        $script:txtBurp.Text = $Config.Paths.BurpSuiteXmlFolder
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
            $config.Tools[$tool] = $script:chkBoxes[$tool].Checked
        }
        if ($config.Tools.BurpSuite) { $config.Paths.BurpSuiteXmlFolder = $script:txtBurp.Text }
        if ($script:txtTenable.Text) { $config.TenableWASScanId = $script:txtTenable.Text }

        Write-GuiMessage "Selected Tools: $(($script:tools | Where-Object { $config.Tools[$_] }) -join ', ')"

        # Process TenableWAS
        if ($config.Tools.TenableWAS) {
            Process-TenableWAS -Config $config
        }

        # Process SonarQube
        if ($config.Tools.SonarQube) {
            Process-SonarQube -Config $config
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
    Write-GuiMessage "Starting TenableWAS scan export (Scan ID: $($Config.TenableWASScanId))"
    try {
        $exportedFile = Export-TenableWASScan -ScanId $Config.TenableWASScanId
        Write-GuiMessage "TenableWAS scan export completed: $exportedFile"

        if ($Config.Tools.DefectDojo) {
            Write-GuiMessage "Uploading TenableWAS scan report to DefectDojo..."

            # Get the specifically selected TenableWAS test
            $tenableTest = $script:cmbDDTestTenable.SelectedItem
            if (-not $tenableTest) {
                Write-GuiMessage "No TenableWAS test selected for DefectDojo upload" 'WARNING'
                return
            }

            # Ensure file path is explicitly converted to string
            $filePathString = ([string]$exportedFile).Trim()

            # Upload directly to the TenableWAS test only
            Upload-DefectDojoScan -FilePath $filePathString -TestId $tenableTest.Id -ScanType 'Tenable Scan'
            Write-GuiMessage "TenableWAS scan report uploaded successfully to DefectDojo test: $($tenableTest.Name)"
        }
    } catch {
        Write-GuiMessage "TenableWAS processing failed: $_" 'ERROR'
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

function Save-DefectDojoConfig {
    param([hashtable]$Config)

    $selections = @{
        Product         = $script:cmbDDProduct.SelectedItem
        Engagement      = $script:cmbDDEng.SelectedItem
        ApiScanConfig   = $script:cmbDDApiScan.SelectedItem
        TenableWASTest  = $script:cmbDDTestTenable.SelectedItem
        SonarQubeTest   = $script:cmbDDTestSonar.SelectedItem
        BurpSuiteTest   = $script:cmbDDTestBurp.SelectedItem
        MinimumSeverity = $script:cmbDDSeverity.SelectedItem
    }

    # Validate that all necessary selections have been made
    $incomplete = $false
    if (-not $selections.Product -or -not $selections.Engagement) { $incomplete = $true }
    if ($Config.Tools.TenableWAS -and -not $selections.TenableWASTest) { $incomplete = $true }
    if ($Config.Tools.SonarQube -and (-not $selections.SonarQubeTest -or -not $selections.ApiScanConfig)) { $incomplete = $true }
    if ($Config.Tools.BurpSuite -and -not $selections.BurpSuiteTest) { $incomplete = $true }

    if ($incomplete) {
        Write-GuiMessage 'DefectDojo selections incomplete; skipping config save.' 'WARNING'
        return
    }

    # Update the config object
    $Config.DefectDojo = @{
        ProductId         = $selections.Product.Id
        EngagementId      = $selections.Engagement.Id
        APIScanConfigId   = $selections.ApiScanConfig.Id
        TenableWASTestId  = $selections.TenableWASTest.Id
        SonarQubeTestId   = $selections.SonarQubeTest.Id
        BurpSuiteTestId   = $selections.BurpSuiteTest.Id
        MinimumSeverity   = $selections.MinimumSeverity
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

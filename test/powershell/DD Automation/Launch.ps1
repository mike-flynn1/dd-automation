<#
    .SYNOPSIS
        DD Automation GUI Launcher
    .DESCRIPTION
        Provides a graphical interface to select tools, file paths, and start DD Automation.
    #>
    
Param()

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

    
    $scriptDir = $PSScriptRoot

    # I know dot source is not best practice, but im lazy
    . (Join-Path $scriptDir 'modules\Logging.ps1')
    . (Join-Path $scriptDir 'modules\Config.ps1')
    . (Join-Path $scriptDir 'TenableWAS.ps1')
    . (Join-Path $scriptDir 'EnvValidator.ps1')
    . (Join-Path $scriptDir 'DefectDojo.ps1')

    #DEBUG
    Get-Command -Module Logging | Format-Table -AutoSize
    
    Initialize-Log -LogDirectory (Join-Path $scriptDir '..\logs') -LogFileName 'DDAutomationLauncher.log' -Overwrite
    Write-Log -Message "DD Automation Launcher started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level 'INFO'

    # Add Windows Forms types
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    try {
        Validate-Environment
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Environment validation failed: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }
    
    # Create form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'DD Automation Launcher'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(620, 700)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    
    # Tools selection GroupBox
    $grpTools = New-Object System.Windows.Forms.GroupBox
    $grpTools.Text = 'Select Tools'
    $grpTools.Size = New-Object System.Drawing.Size(580, 100)
    $grpTools.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($grpTools)
    
    # Tool checkboxes
    $tools = @('TenableWAS','SonarQube','BurpSuite','DefectDojo')
    $chkBoxes = @{}
    for ($i = 0; $i -lt $tools.Count; $i++) {
        $name = $tools[$i]
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = $name
        $chk.AutoSize = $true
        $xPos = 10 + ($i * 140)
        $chk.Location = New-Object System.Drawing.Point($xPos, 20)
        $chk.Checked = $true
        $grpTools.Controls.Add($chk)
        $chkBoxes[$name] = $chk
    }
    
    # BurpSuite XML folder picker
    $lblBurp = New-Object System.Windows.Forms.Label
    $lblBurp.Text = 'BurpSuite XML Folder:'
    $lblBurp.AutoSize = $true
    $lblBurp.Location = New-Object System.Drawing.Point(10, 120)
    $form.Controls.Add($lblBurp)
    
    $txtBurp = New-Object System.Windows.Forms.TextBox
    $txtBurp.Size = New-Object System.Drawing.Size(370, 20)
    $txtBurp.Location = New-Object System.Drawing.Point(150, 118)
    $form.Controls.Add($txtBurp)
    
    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = 'Browse...'
    $btnBrowse.Location = New-Object System.Drawing.Point(520, 115)
    $btnBrowse.Size = New-Object System.Drawing.Size(80, 24)
    $form.Controls.Add($btnBrowse)
    
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    
    $btnBrowse.Add_Click({
        if ($folderDialog.ShowDialog() -eq 'OK') {
            $txtBurp.Text = $folderDialog.SelectedPath
        }
    })
    # Enable/disable BurpSuite picker based on selection
    $txtBurp.Enabled = $chkBoxes['BurpSuite'].Checked
    $btnBrowse.Enabled = $chkBoxes['BurpSuite'].Checked
    $chkBoxes['BurpSuite'].Add_CheckedChanged({
        $txtBurp.Enabled = $chkBoxes['BurpSuite'].Checked
        $btnBrowse.Enabled = $chkBoxes['BurpSuite'].Checked
    })
    
    # Debug mode checkbox
    # $chkDebug = New-Object System.Windows.Forms.CheckBox
    # $chkDebug.Text = 'Debug Mode'
    # $chkDebug.AutoSize = $true
    # $chkDebug.Location = New-Object System.Drawing.Point(10, 150)
    # $form.Controls.Add($chkDebug)
    
    # TenableWAS Scan ID entry
    $lblTenable = New-Object System.Windows.Forms.Label
    $lblTenable.Text = 'TenableWAS Scan ID:'
    $lblTenable.AutoSize = $true
    $lblTenable.Location = New-Object System.Drawing.Point(10, 180)
    $form.Controls.Add($lblTenable)

    $txtTenable = New-Object System.Windows.Forms.TextBox
    $txtTenable.Size = New-Object System.Drawing.Size(370, 20)
    $txtTenable.Location = New-Object System.Drawing.Point(150, 178)
    $form.Controls.Add($txtTenable)

    # DefectDojo selection: Product, Engagement, Test
    $lblDDProduct = New-Object System.Windows.Forms.Label
    $lblDDProduct.Text = 'DefectDojo Product:'
    $lblDDProduct.AutoSize = $true
    $lblDDProduct.Location = New-Object System.Drawing.Point(10, 210)
    $form.Controls.Add($lblDDProduct)

    $cmbDDProduct = New-Object System.Windows.Forms.ComboBox
    $cmbDDProduct.DropDownStyle = 'DropDownList'
    $cmbDDProduct.Location = New-Object System.Drawing.Point(150, 208)
    $cmbDDProduct.Size = New-Object System.Drawing.Size(220, 20)
    $cmbDDProduct.Enabled = $false
    $form.Controls.Add($cmbDDProduct)

    $lblDDEng = New-Object System.Windows.Forms.Label
    $lblDDEng.Text = 'Engagement:'
    $lblDDEng.AutoSize = $true
    $lblDDEng.Location = New-Object System.Drawing.Point(10, 240)
    $form.Controls.Add($lblDDEng)

    $cmbDDEng = New-Object System.Windows.Forms.ComboBox
    $cmbDDEng.DropDownStyle = 'DropDownList'
    $cmbDDEng.Location = New-Object System.Drawing.Point(150, 238)
    $cmbDDEng.Size = New-Object System.Drawing.Size(220, 20)
    $cmbDDEng.Enabled = $false
    $form.Controls.Add($cmbDDEng)

    # DefectDojo test selectors for each tool
    $lblDDTestTenable = New-Object System.Windows.Forms.Label
    $lblDDTestTenable.Text = 'TenableWAS Test:'
    $lblDDTestTenable.AutoSize = $true
    $lblDDTestTenable.Location = New-Object System.Drawing.Point(10, 300)
    $form.Controls.Add($lblDDTestTenable)

    $cmbDDTestTenable = New-Object System.Windows.Forms.ComboBox
    $cmbDDTestTenable.DropDownStyle = 'DropDownList'
    $cmbDDTestTenable.Location = New-Object System.Drawing.Point(150, 298)
    $cmbDDTestTenable.Size = New-Object System.Drawing.Size(220, 20)
    $cmbDDTestTenable.Enabled = $false
    $form.Controls.Add($cmbDDTestTenable)

    $lblDDTestSonar = New-Object System.Windows.Forms.Label
    $lblDDTestSonar.Text = 'SonarQube Test:'
    $lblDDTestSonar.AutoSize = $true
    $lblDDTestSonar.Location = New-Object System.Drawing.Point(10, 330)
    $form.Controls.Add($lblDDTestSonar)

    $cmbDDTestSonar = New-Object System.Windows.Forms.ComboBox
    $cmbDDTestSonar.DropDownStyle = 'DropDownList'
    $cmbDDTestSonar.Location = New-Object System.Drawing.Point(150, 328)
    $cmbDDTestSonar.Size = New-Object System.Drawing.Size(220, 20)
    $cmbDDTestSonar.Enabled = $false
    $form.Controls.Add($cmbDDTestSonar)

    $lblDDTestBurp = New-Object System.Windows.Forms.Label
    $lblDDTestBurp.Text = 'BurpSuite Test:'
    $lblDDTestBurp.AutoSize = $true
    $lblDDTestBurp.Location = New-Object System.Drawing.Point(10, 360)
    $form.Controls.Add($lblDDTestBurp)

    $cmbDDTestBurp = New-Object System.Windows.Forms.ComboBox
    $cmbDDTestBurp.DropDownStyle = 'DropDownList'
    $cmbDDTestBurp.Location = New-Object System.Drawing.Point(150, 358)
    $cmbDDTestBurp.Size = New-Object System.Drawing.Size(220, 20)
    $cmbDDTestBurp.Enabled = $false
    $form.Controls.Add($cmbDDTestBurp)

    # Enable/disable test selectors based on tool selection
    $chkBoxes['TenableWAS'].Add_CheckedChanged({ $cmbDDTestTenable.Enabled = $chkBoxes['TenableWAS'].Checked -and $cmbDDTestTenable.Items.Count -gt 0 })
    $chkBoxes['SonarQube'].Add_CheckedChanged({  $cmbDDTestSonar.Enabled  = $chkBoxes['SonarQube'].Checked  -and $cmbDDTestSonar.Items.Count  -gt 0 })
    $chkBoxes['BurpSuite'].Add_CheckedChanged({ $cmbDDTestBurp.Enabled   = $chkBoxes['BurpSuite'].Checked -and $cmbDDTestBurp.Items.Count   -gt 0 })

    # Load products when DefectDojo is enabled
    if ($chkBoxes['DefectDojo'].Checked) {
        Write-GuiMessage 'Loading DefectDojo products...'
        try {
            $products = Get-DefectDojoProducts
            $cmbDDProduct.Items.Clear()
            foreach ($p in $products) { $cmbDDProduct.Items.Add($p) | Out-Null }
            $cmbDDProduct.DisplayMember = 'Name'; $cmbDDProduct.ValueMember = 'Id'
            $cmbDDProduct.Enabled = $true
        } catch {
            Write-GuiMessage "Failed to load DefectDojo products: $_" 'ERROR'
        }
    }

    $cmbDDProduct.Add_SelectedIndexChanged({
        $sel = $cmbDDProduct.SelectedItem
        if ($sel) {
            Write-GuiMessage "Loading engagements for product $($sel.Name)..."
            try {
                $engs = Get-DefectDojoEngagements -ProductId $sel.Id
                $cmbDDEng.Items.Clear()
                foreach ($e in $engs) { $cmbDDEng.Items.Add($e) | Out-Null }
                $cmbDDEng.DisplayMember = 'Name'; $cmbDDEng.ValueMember = 'Id'
                $cmbDDEng.Enabled = $true
                $cmbDDTestTenable.Enabled = $false; $cmbDDTestTenable.Items.Clear()
                $cmbDDTestSonar.Enabled  = $false; $cmbDDTestSonar.Items.Clear()
                $cmbDDTestBurp.Enabled   = $false; $cmbDDTestBurp.Items.Clear()
            } catch {
                Write-GuiMessage "Failed to load engagements: $_" 'ERROR'
            }
        }
    })

    $cmbDDEng.Add_SelectedIndexChanged({
        $selEng = $cmbDDEng.SelectedItem
        if ($selEng) {
            try {
                Write-GuiMessage "Loading tests for engagement $($selEng.Name)..."
                $tests = Get-DefectDojoTests -EngagementId $selEng.Id
                foreach ($cmb in @($cmbDDTestTenable, $cmbDDTestSonar, $cmbDDTestBurp)) {
                    $cmb.Items.Clear()
                    if ($tests) {
                        foreach ($t in $tests) { $cmb.Items.Add($t) | Out-Null }
                    }
                    $cmb.DisplayMember = 'Name'; $cmb.ValueMember = 'Id'
                    $cmb.Enabled = ($tests -and $tests.Count -gt 0)
                }
                if (-not $chkBoxes['TenableWAS'].Checked) { $cmbDDTestTenable.Enabled = $false }
                if (-not $chkBoxes['SonarQube'].Checked)  { $cmbDDTestSonar.Enabled  = $false }
                if (-not $chkBoxes['BurpSuite'].Checked) { $cmbDDTestBurp.Enabled   = $false }
                if (-not $tests -or $tests.Count -eq 0) {
                    Write-GuiMessage "No DefectDojo tests found for engagement $($selEng.Name)." 'WARNING'
                }
            } catch {
                Write-GuiMessage "Failed to load tests: $_" 'ERROR'
            }
        }
    })

    # Status ListBox
    $lstStatus = New-Object System.Windows.Forms.ListBox
    $lstStatus.Size = New-Object System.Drawing.Size(580, 180)
    $lstStatus.Location = New-Object System.Drawing.Point(10, 420)
    $form.Controls.Add($lstStatus)
    
    # Buttons
    $btnLaunch = New-Object System.Windows.Forms.Button
    $btnLaunch.Text = 'Launch'
    $btnLaunch.Location = New-Object System.Drawing.Point(420, 620)
    $btnLaunch.Size = New-Object System.Drawing.Size(80, 30)
    $form.Controls.Add($btnLaunch)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(520, 620)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $form.Controls.Add($btnCancel)
      # Define log function for GUI
    function Write-GuiMessage {
        param(
            [string]$Message,
            [ValidateSet('INFO','WARNING','ERROR')]
            [string]$Level = 'INFO'
        )
        try {
        Write-Log -Message $Message -Level $Level
        }
        catch {
            # Fallback: Write to console if log not initialized
            Write-Warning "Log file not initialized. Message: $Message"
        }
        $timestamp = (Get-Date -Format 'HH:mm:ss')
        $lstStatus.Items.Add("$timestamp [$Level] $Message") | Out-Null
    }
    # Initial GUI status
    Write-GuiMessage "DD Automation Launcher started."
    
    # Button events
    $btnLaunch.Add_Click({

           
            try {
            # Load existing config or example
            $config = Get-Config
            # Validate BurpSuite folder if selected
            if ($chkBoxes['BurpSuite'].Checked -and -not (Test-Path -Path $txtBurp.Text)) {
                [System.Windows.Forms.MessageBox]::Show("Please select a valid BurpSuite XML folder.","Validation Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                return
            }
    
            # Override based on GUI
            foreach ($tool in $tools) {
                $config.Tools[$tool] = $chkBoxes[$tool].Checked
            }
            if ($config.Tools.BurpSuite -and $txtBurp.Text) {
                $config.Paths.BurpSuiteXmlFolder = $txtBurp.Text
            }
            $config.Debug = $chkDebug.Checked
            # Capture TenableWAS Scan ID from GUI
            if ($txtTenable.Text) {
                if (-not $config.TenableWAS) { $config.TenableWAS = @{} }
                $config.TenableWAS.ScanId = $txtTenable.Text
            }
    
    
            Write-GuiMessage "Selected Tools: $(($tools | Where-Object { $config.Tools[$_] }) -join ', ')"
            if ($config.Tools.BurpSuite) {
                Write-GuiMessage "BurpSuite XML folder: $($config.Paths.BurpSuiteXmlFolder)"
            }
    
            # Expose to session
            Set-Variable -Name Config -Scope Global -Value $config

            if ($config.Tools.TenableWAS) {
                Write-GuiMessage "Starting TenableWAS scan export (Scan ID: $($config.TenableWAS.ScanId))"
                try {
                    $exportedFile = Export-TenableWASScan -ScanId $config.TenableWAS.ScanId
                    Start-Sleep -Seconds 5
                    Write-GuiMessage "TenableWAS scan export completed: $exportedFile"
                    
                    # Upload the exported file to DefectDojo if both TenableWAS and DefectDojo are enabled
                    if ($config.Tools.DefectDojo) {
                        Write-GuiMessage "Uploading TenableWAS scan report to DefectDojo..."
                        try {
                            # Import the Uploader module if not already loaded
                            $uploaderPath = Join-Path $scriptDir 'Uploader.ps1'
                            . $uploaderPath
                            
                            # Ensure file path is explicitly converted to string
                            $filePathString = ([string]$exportedFile).Trim()

                            # Upload the file to DefectDojo using the Select-DefectDojoScans function
                            Select-DefectDojoScans -FilePath $filePathString
                            Write-GuiMessage "TenableWAS scan report uploaded successfully to DefectDojo" 'INFO'
                        } catch {
                            Write-GuiMessage "Failed to upload TenableWAS scan report to DefectDojo: $_" 'ERROR'
                        }
                    }
                } catch {
                    Write-GuiMessage "TenableWAS scan export failed: $_" 'ERROR'
                }
            }

            # Save DefectDojo selections and write back to config file if selected
            if ($config.Tools.DefectDojo) {
                if ($cmbDDProduct.SelectedItem -and $cmbDDEng.SelectedItem `
                    -and ((-not $config.Tools.TenableWAS) -or $cmbDDTestTenable.SelectedItem) `
                    -and ((-not $config.Tools.SonarQube)  -or $cmbDDTestSonar.SelectedItem) `
                    -and ((-not $config.Tools.BurpSuite) -or $cmbDDTestBurp.SelectedItem)) {
                    $config.DefectDojo = @{ 
                        ProductId         = $cmbDDProduct.SelectedItem.Id
                        EngagementId      = $cmbDDEng.SelectedItem.Id
                        TenableWASTestId  = $cmbDDTestTenable.SelectedItem.Id
                        SonarQubeTestId   = $cmbDDTestSonar.SelectedItem.Id
                        BurpSuiteTestId   = $cmbDDTestBurp.SelectedItem.Id
                    }
                    Write-GuiMessage "Selected DefectDojo Product: $($cmbDDProduct.SelectedItem.Name) (Id: $($cmbDDProduct.SelectedItem.Id))"
                    Write-GuiMessage "Selected Engagement: $($cmbDDEng.SelectedItem.Name) (Id: $($cmbDDEng.SelectedItem.Id))"
                    Write-GuiMessage "Selected TenableWAS Test: $($cmbDDTestTenable.SelectedItem.Name) (Id: $($cmbDDTestTenable.SelectedItem.Id))"
                    Write-GuiMessage "Selected SonarQube Test: $($cmbDDTestSonar.SelectedItem.Name) (Id: $($cmbDDTestSonar.SelectedItem.Id))"
                    Write-GuiMessage "Selected BurpSuite Test: $($cmbDDTestBurp.SelectedItem.Name) (Id: $($cmbDDTestBurp.SelectedItem.Id))"
                    Write-GuiMessage 'Saving DefectDojo selections to config file...'
                    try {
                        Save-Config -Config $config
                        Write-GuiMessage 'DefectDojo configuration saved.'
                    } catch {
                        Write-GuiMessage "Failed to save DefectDojo configuration: $_" 'ERROR'
                    }
                } else {
                    Write-GuiMessage 'DefectDojo selections incomplete; skipping config save.' 'WARNING'
                }
            }
            Write-GuiMessage 'Configuration stored in global $Config. Closing GUI.'
            Start-Sleep -Milliseconds 500
            $form.Close()
        }
        
        catch {
            Write-GuiMessage "Error: $_" 'ERROR'
        }
    })
    
    $btnCancel.Add_Click({ $form.Close() })
    # Prepopulate GUI from existing config
    $initialConfig = Get-Config
    foreach ($tool in $tools) {
        if ($initialConfig.Tools.ContainsKey($tool)) {
            $chkBoxes[$tool].Checked = [bool]$initialConfig.Tools[$tool]
        }
    }
    $chkDebug.Checked = [bool]$initialConfig.Debug
    if ($initialConfig.Paths.ContainsKey('BurpSuiteXmlFolder')) {
        $txtBurp.Text = $initialConfig.Paths.BurpSuiteXmlFolder
    }
    # Prepopulate TenableWAS Scan ID
    if ($initialConfig.TenableWAS -and $initialConfig.TenableWAS.ScanId) {
        $txtTenable.Text = $initialConfig.TenableWAS.ScanId
    } elseif ($initialConfig.TenableWASScanId) {
        $txtTenable.Text = $initialConfig.TenableWASScanId
    }

    # Prepopulate DefectDojo selections
    if ($initialConfig.DefectDojo) {
        Write-GuiMessage 'Prepopulating DefectDojo products...'
        try {
            $cmbDDProduct.Items.Clear()
            $products = Get-DefectDojoProducts
            foreach ($p in $products) { $cmbDDProduct.Items.Add($p) | Out-Null }
            $cmbDDProduct.DisplayMember = 'Name'; $cmbDDProduct.ValueMember = 'Id'
            $cmbDDProduct.Enabled = $true
            if ($initialConfig.DefectDojo.ProductId) {
                $sel = $cmbDDProduct.Items | Where-Object { $_.Id -eq $initialConfig.DefectDojo.ProductId }
                if ($sel) { $cmbDDProduct.SelectedItem = $sel }
            }
        } catch {
            Write-GuiMessage "Failed to prepopulate DefectDojo products: $_" 'ERROR'
        }
        if ($initialConfig.DefectDojo.EngagementId) {
            try {
                $selEng = $cmbDDEng.Items | Where-Object { $_.Id -eq $initialConfig.DefectDojo.EngagementId }
                if ($selEng) { $cmbDDEng.SelectedItem = $selEng }
            } catch {
                Write-GuiMessage "Failed to prepopulate DefectDojo engagements: $_" 'ERROR'
            }
        }
        # Prepopulate tool-specific DefectDojo tests
        if ($initialConfig.DefectDojo.TenableWASTestId) {
            try {
                $sel = $cmbDDTestTenable.Items | Where-Object { $_.Id -eq $initialConfig.DefectDojo.TenableWASTestId }
                if ($sel) { $cmbDDTestTenable.SelectedItem = $sel }
            } catch {
                Write-GuiMessage "Failed to prepopulate DefectDojo TenableWAS test: $_" 'ERROR'
            }
        }
        if ($initialConfig.DefectDojo.SonarQubeTestId) {
            try {
                $sel = $cmbDDTestSonar.Items | Where-Object { $_.Id -eq $initialConfig.DefectDojo.SonarQubeTestId }
                if ($sel) { $cmbDDTestSonar.SelectedItem = $sel }
            } catch {
                Write-GuiMessage "Failed to prepopulate DefectDojo SonarQube test: $_" 'ERROR'
            }
        }
        if ($initialConfig.DefectDojo.BurpSuiteTestId) {
            try {
                $sel = $cmbDDTestBurp.Items | Where-Object { $_.Id -eq $initialConfig.DefectDojo.BurpSuiteTestId }
                if ($sel) { $cmbDDTestBurp.SelectedItem = $sel }
            } catch {
                Write-GuiMessage "Failed to prepopulate DefectDojo BurpSuite test: $_" 'ERROR'
            }
        }
    }
    
    # Show form
    [void]$form.ShowDialog()

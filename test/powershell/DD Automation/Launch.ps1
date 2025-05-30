    <#
    .SYNOPSIS
        DD Automation GUI Launcher
    .DESCRIPTION
        Provides a graphical interface to select tools, file paths, and debug mode for DD Automation.
    #>
    
    Param()
    
    $scriptDir = $PSScriptRoot

    # I know dot source is not best practice, but im lazy
    . (Join-Path $scriptDir 'modules\Logging.ps1')
    . (Join-Path $scriptDir 'modules\Config.ps1')
    . (Join-Path $scriptDir 'TenableWAS.ps1')
    . (Join-Path $scriptDir 'EnvValidator.ps1')



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
    $form.Size = New-Object System.Drawing.Size(620, 500)
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
    $txtBurp.Size = New-Object System.Drawing.Size(460, 20)
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
    $chkDebug = New-Object System.Windows.Forms.CheckBox
    $chkDebug.Text = 'Debug Mode'
    $chkDebug.AutoSize = $true
    $chkDebug.Location = New-Object System.Drawing.Point(10, 150)
    $form.Controls.Add($chkDebug)
    
    # TenableWAS Scan ID entry
    $lblTenable = New-Object System.Windows.Forms.Label
    $lblTenable.Text = 'TenableWAS Scan ID:'
    $lblTenable.AutoSize = $true
    $lblTenable.Location = New-Object System.Drawing.Point(10, 180)
    $form.Controls.Add($lblTenable)

    $txtTenable = New-Object System.Windows.Forms.TextBox
    $txtTenable.Size = New-Object System.Drawing.Size(460, 20)
    $txtTenable.Location = New-Object System.Drawing.Point(150, 178)
    $form.Controls.Add($txtTenable)
    
    # Status ListBox
    $lstStatus = New-Object System.Windows.Forms.ListBox
    $lstStatus.Size = New-Object System.Drawing.Size(580, 170)
    $lstStatus.Location = New-Object System.Drawing.Point(10, 210)
    $form.Controls.Add($lstStatus)
    
    # Buttons
    $btnLaunch = New-Object System.Windows.Forms.Button
    $btnLaunch.Text = 'Launch'
    $btnLaunch.Location = New-Object System.Drawing.Point(420, 390)
    $btnLaunch.Size = New-Object System.Drawing.Size(80, 30)
    $form.Controls.Add($btnLaunch)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(520, 390)
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
            Write-GuiMessage "Debug Mode: $($config.Debug)"
    
            # Expose to session
            Set-Variable -Name Config -Scope Global -Value $config

            if ($config.Tools.TenableWAS) {
                Write-GuiMessage "Starting TenableWAS scan export (Scan ID: $($config.TenableWAS.ScanId))"
                try {
                    $exportedFile = Export-TenableWASScan -ScanId $config.TenableWAS.ScanId
                    Start-Sleep -Seconds 5
                    Write-GuiMessage "TenableWAS scan export completed: $exportedFile"
                } catch {
                    Write-GuiMessage "TenableWAS scan export failed: $_" 'ERROR'
                }
            }

            #TODO - Implement save to config
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
    
    # Show form
    [void]$form.ShowDialog()

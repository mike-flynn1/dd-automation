# Pester tests for Logging module
$moduleDir = Join-Path $PSScriptRoot '../modules'
. (Join-Path $moduleDir 'Logging.ps1')

Describe 'Initialize-Log' {
    It 'Creates log file with header' {
        $tempDir = New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot '../logs/tempLog') -Force
        Initialize-Log -LogDirectory $tempDir.FullName -LogFileName 'testlog.txt' -Overwrite
        $logFile = Join-Path $tempDir.FullName 'testlog.txt'
        Test-Path $logFile | Should -BeTrue
        $content = Get-Content $logFile
        $content | Should -Match '===== Log started at '
    }
}

Describe 'Write-Log' {
    BeforeAll {
        $tempDir = New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot '../logs/tempLog2') -Force
        Initialize-Log -LogDirectory $tempDir.FullName -LogFileName 'testlog2.txt' -Overwrite
        $logFile = Join-Path $tempDir.FullName 'testlog2.txt'
    }
    It 'Appends INFO log entry to file' {
        Write-Log -Message 'Hello World' -Level 'INFO'
        $lines = Get-Content $logFile
        $lastLine = $lines[-1]
        $lastLine | Should -Match 'INFO'
        $lastLine | Should -Match 'Hello World'
    }
    It 'Throws error if log not initialized' {
        Remove-Variable -Scope Script -Name LogFilePath -ErrorAction SilentlyContinue
        . (Join-Path $moduleDir 'Logging.ps1')
        { Write-Log -Message 'Test' } | Should -Throw 'Log file not initialized. Call Initialize-Log before writing logs.'
    }
}

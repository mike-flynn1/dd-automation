# Pester tests for Logging module

Describe 'Initialize-Log' {
    BeforeAll {
        $testDirectory = Split-Path -Parent $PSCommandPath
        $repoRoot = Split-Path -Parent $testDirectory
        $modulePath = Join-Path $repoRoot 'modules/Logging.ps1'
        . $modulePath
    }

    It 'Creates log file with header' {
        $logDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Initialize-Log -LogDirectory $logDirectory -LogFileName 'testlog.txt' -Overwrite

        $logFile = Join-Path $logDirectory 'testlog.txt'
        Test-Path $logFile | Should -BeTrue
        $content = Get-Content -Path $logFile -Raw
        $content | Should -Match '===== Log started at '
    }
}

Describe 'Write-Log' {
    BeforeAll {
        $testDirectory = Split-Path -Parent $PSCommandPath
        $repoRoot = Split-Path -Parent $testDirectory
        $modulePath = Join-Path $repoRoot 'modules/Logging.ps1'
        . $modulePath
    }

    Context 'Log initialized' {
        BeforeEach {
            $script:logDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            Initialize-Log -LogDirectory $script:logDirectory -LogFileName 'testlog2.txt' -Overwrite
            $script:logFile = Join-Path $script:logDirectory 'testlog2.txt'
        }

        AfterEach {
            Remove-Variable -Scope Script -Name LogFilePath -ErrorAction SilentlyContinue
        }

        It 'Appends INFO log entry to file' {
            Write-Log -Message 'Hello World' -Level 'INFO'
            $lines = Get-Content $script:logFile
            $lastLine = $lines[-1]
            $lastLine | Should -Match 'INFO'
            $lastLine | Should -Match 'Hello World'
        }
    }

    Context 'Log not initialized' {
        BeforeEach {
            Remove-Variable -Scope Script -Name LogFilePath -ErrorAction SilentlyContinue
            Mock Write-Host {}
        }

        It 'Throws and notifies the user when log is not initialized' {
            { Write-Log -Message 'Test' } | Should -Throw
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -match 'Log file not initialized' }
        }
    }
}

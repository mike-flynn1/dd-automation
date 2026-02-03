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

    It 'Rotates existing log files up to MaxLogFiles' {
        $logDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $logDirectory -ItemType Directory | Out-Null

        $base = Join-Path $logDirectory 'rotate.log'
        'first'  | Out-File -FilePath $base -Encoding utf8
        'second' | Out-File -FilePath "$base.1" -Encoding utf8
        'third'  | Out-File -FilePath "$base.2" -Encoding utf8

        Initialize-Log -LogDirectory $logDirectory -LogFileName 'rotate.log' -MaxLogFiles 3

        Test-Path "$base.2" | Should -BeTrue
        (Get-Content "$base.2" -Raw) | Should -Match 'second'
        Test-Path "$base.1" | Should -BeTrue
        (Get-Content "$base.1" -Raw) | Should -Match 'first'
        Test-Path $base | Should -BeTrue
        (Get-Content $base -Raw) | Should -Match '===== Log started at '
    }

    It 'Does not rotate when MaxLogFiles is 1' {
        $logDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $logDirectory -ItemType Directory | Out-Null

        $base = Join-Path $logDirectory 'single.log'
        'keep' | Out-File -FilePath $base -Encoding utf8

        Initialize-Log -LogDirectory $logDirectory -LogFileName 'single.log' -MaxLogFiles 1

        Test-Path "$base.1" | Should -BeFalse
        (Get-Content $base -Raw) | Should -Match 'keep'
        (Get-Content $base -Raw) | Should -Match '===== Log started at '
    }

    It 'Overwrite skips rotation and recreates file' {
        $logDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $logDirectory -ItemType Directory | Out-Null

        $base = Join-Path $logDirectory 'overwrite.log'
        'old' | Out-File -FilePath $base -Encoding utf8
        'prior' | Out-File -FilePath "$base.1" -Encoding utf8

        Initialize-Log -LogDirectory $logDirectory -LogFileName 'overwrite.log' -MaxLogFiles 3 -Overwrite

        Test-Path "$base.1" | Should -BeTrue
        (Get-Content "$base.1" -Raw) | Should -Match 'prior'
        (Get-Content $base -Raw) | Should -Match '===== Log started at '
        (Get-Content $base -Raw) | Should -Not -Match 'old'
    }

    It 'Continues logging initialization when rotation encounters file lock errors' {
        $logDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $logDirectory -ItemType Directory | Out-Null

        $base = Join-Path $logDirectory 'locked.log'
        'existing' | Out-File -FilePath $base -Encoding utf8
        'archived' | Out-File -FilePath "$base.1" -Encoding utf8

        # Mock Move-Item to simulate file lock error on first call, but succeed on subsequent calls
        $callCount = 0
        $originalMoveItem = Get-Command Move-Item
        Mock Move-Item {
            $callCount++
            if ($callCount -eq 1) {
                throw [System.IO.IOException]"The process cannot access the file because it is being used by another process."
            }
            & $originalMoveItem @PSBoundParameters
        } -ParameterFilter { $Path -like "$base*" }

        # Should not throw despite Move-Item error
        { Initialize-Log -LogDirectory $logDirectory -LogFileName 'locked.log' -MaxLogFiles 2 } | Should -Not -Throw

        # New log file should still be created
        Test-Path $base | Should -BeTrue
        (Get-Content $base -Raw) | Should -Match '===== Log started at '
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

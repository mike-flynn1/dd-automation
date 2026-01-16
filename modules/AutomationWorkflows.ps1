<#
.SYNOPSIS
    Contains the core orchestration logic for the automation tools.
    Separated from Launch.ps1 to allow CLI usage.
#>

. (Join-Path $PSScriptRoot 'Logging.ps1')
. (Join-Path $PSScriptRoot 'DefectDojo.ps1')
. (Join-Path $PSScriptRoot 'TenableWAS.ps1')
. (Join-Path $PSScriptRoot 'Sonarqube.ps1')
. (Join-Path $PSScriptRoot 'BurpSuite.ps1')
. (Join-Path $PSScriptRoot 'GitHub.ps1')
. (Join-Path $PSScriptRoot 'Uploader.ps1')

function Invoke-Workflow-TenableWAS {
    param([hashtable]$Config)

    if (-not $Config.TenableWASSelectedScans -or $Config.TenableWASSelectedScans.Count -eq 0) {
        Write-Log -Message "No TenableWAS scans selected in configuration." -Level 'WARNING'
        return
    }

    # Initialize DefectDojo-specific variables if DefectDojo is enabled
    if ($Config.Tools.DefectDojo) {
        $engagementId = $Config.DefectDojo.EngagementId
        if (-not $engagementId) {
            Write-Log -Message "No DefectDojo engagement ID configured; cannot create TenableWAS tests." -Level 'ERROR'
            return
        }

        try {
            $tenableTestTypeId = Get-DefectDojoTestType -TestTypeName 'Tenable Scan'
        } catch {
            Write-Log -Message "Failed to lookup 'Tenable Scan' test type: $_" -Level 'ERROR'
            return
        }

        $existingTests = @(Get-DefectDojoTests -EngagementId $engagementId)
    }

    $uploadErrors = 0
    $totalScans = $Config.TenableWASSelectedScans.Count

    foreach ($scan in $Config.TenableWASSelectedScans) {
        # Handle scan object vs string (CLI might pass objects if loaded from JSON, or strings if from simple config)
        # Assuming $scan is an object with Name and Id as per Launch.ps1 usage
        if ($scan -is [string]) {
             # Fallback if just a name is passed.
             Write-Log -Message "Scan config is string, expected object. Skipping $scan" -Level 'ERROR'
             continue
        }

        Write-Log -Message "Starting TenableWAS scan export (Scan: $($scan.Name) - ID: $($scan.Id))"
        try {
            $exportedFile = Export-TenableWASScan -ScanName $scan.Name
            Write-Log -Message "TenableWAS scan export completed: $exportedFile"

            if ($Config.Tools.DefectDojo) {
                Write-Log -Message "Processing TenableWAS scan for DefectDojo upload..."

                $serviceName = "$($scan.Name) (Tenable WAS)"
                $existingTest = $existingTests | Where-Object {
                    $_.Title -in @($serviceName, $scan.Name, "$($scan.Name) (Tenable)")
                } | Select-Object -First 1

                if (-not $existingTest) {
                    Write-Log -Message "Creating new DefectDojo test: $serviceName"
                    try {
                        $newTest = New-DefectDojoTest -EngagementId $engagementId -TestName $serviceName -TestType $tenableTestTypeId
                        Write-Log -Message "Test created successfully: $serviceName (ID: $($newTest.Id))"
                        $existingTests += $newTest
                        $testId = $newTest.Id
                    } catch {
                        Write-Log -Message "Failed to create test ${serviceName}: $_" -Level 'ERROR'
                        $uploadErrors++
                        continue
                    }
                } else {
                    Write-Log -Message "Using existing DefectDojo test: $($existingTest.Title) (ID: $($existingTest.Id))"
                    $testId = $existingTest.Id
                }

                $filePathString = ([string]$exportedFile).Trim()
                Upload-DefectDojoScan -FilePath $filePathString -TestId $testId -ScanType 'Tenable Scan' -CloseOldFindings $Config.DefectDojo.CloseOldFindings
                Write-Log -Message "TenableWAS scan report uploaded successfully to DefectDojo test: $serviceName"
            }
        } catch {
            $uploadErrors++
            Write-Log -Message "TenableWAS processing failed for $($scan.Name): $_" -Level 'ERROR'
        }
    }
}

function Invoke-Workflow-SonarQube {
    param([hashtable]$Config)
    Write-Log -Message "Processing SonarQube scan..."
    try {
        $apiScanConfigId = $Config.DefectDojo.APIScanConfigId
        $testId = $Config.DefectDojo.SonarQubeTestId

        if (-not $apiScanConfigId -or -not $testId) {
            Write-Log -Message "SonarQube processing requires APIScanConfigId and SonarQubeTestId in DefectDojo config." -Level 'ERROR'
            return
        }

        Invoke-SonarQubeProcessing -ApiScanConfiguration $apiScanConfigId -Test $testId
        Write-Log -Message "SonarQube processing completed."
    } catch {
        Write-Log -Message "SonarQube processing failed: $_" -Level 'ERROR'
    }
}

function Invoke-Workflow-BurpSuite {
    param([hashtable]$Config)
    Write-Log -Message "Starting BurpSuite XML report processing..."
    try {
        $xmlFiles = Get-BurpSuiteReports -FolderPath $Config.Paths.BurpSuiteXmlFolder

        if (-not $xmlFiles -or $xmlFiles.Count -eq 0) {
            Write-Log -Message "No BurpSuite XML files found in folder: $($Config.Paths.BurpSuiteXmlFolder)" -Level 'WARNING'
            return
        }

        Write-Log -Message "Found $($xmlFiles.Count) BurpSuite XML report(s)"

        if ($Config.Tools.DefectDojo) {
            $burpTestId = $Config.DefectDojo.BurpSuiteTestId
            if (-not $burpTestId) {
                Write-Log -Message "No BurpSuite test ID configured for DefectDojo upload" -Level 'WARNING'
                return
            }

            $xmlFile = $xmlFiles[0]
            $fileName = [System.IO.Path]::GetFileName($xmlFile)

            if ($xmlFiles.Count -gt 1) {
                Write-Log -Message "Multiple XML files found. Uploading only: $fileName" -Level 'WARNING'
            }

            try {
                Write-Log -Message "Uploading $fileName to DefectDojo test ID: $burpTestId"
                $filePathString = ([string]$xmlFile).Trim()
                Upload-DefectDojoScan -FilePath $filePathString -TestId $burpTestId -ScanType 'Burp Scan' -CloseOldFindings $Config.DefectDojo.CloseOldFindings
                Write-Log -Message "Successfully uploaded $fileName"
            } catch {
                Write-Log -Message "Failed to upload $fileName : $_" -Level 'ERROR'
            }
        }
    } catch {
        Write-Log -Message "BurpSuite processing failed: $_" -Level 'ERROR'
    }
}

function Invoke-Workflow-GitHubCodeQL {
    param([hashtable]$Config)
    Write-Log -Message "Starting GitHub CodeQL download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-Log -Message "No GitHub organizations configured. Skipping GitHub processing." -Level 'WARNING'
            return
        }

        GitHub-CodeQLDownload -Owners $orgs
        Write-Log -Message "GitHub CodeQL download completed."

        if ($Config.Tools.DefectDojo) {
            Write-Log -Message "Uploading GitHub CodeQL reports to DefectDojo..."
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubCodeScanning'
            $sarifFiles = Get-ChildItem -Path $downloadRoot -Filter '*.sarif' -Recurse | Select-Object -ExpandProperty FullName
            $uploadErrors = 0

            $engagementId = $Config.DefectDojo.EngagementId
            if (-not $engagementId) {
                Write-Log -Message "No DefectDojo engagement ID configured; skipping GitHub uploads." -Level 'WARNING'
                return
            }
            $existingTests = @(Get-DefectDojoTests -EngagementId $engagementId)
            
            foreach ($file in $sarifFiles) {
                try {
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)
                    $baseServiceName = $fileName -replace '-\d+$', ''
                    $repoNameOnly = $baseServiceName
                    if ($baseServiceName -match '^(?<org>[^-]+)-(?<repo>.+)$') {
                        $repoNameOnly = $Matches['repo']
                    }

                    $serviceNameCore = $repoNameOnly
                    $serviceName = "$serviceNameCore (CodeQL)"

                    $existingTest = $existingTests | Where-Object { $_.title -in @($serviceName, $serviceNameCore, $repoNameOnly) } | Select-Object -First 1

                    if (-not $existingTest) {
                        Write-Log -Message "Creating new test: $serviceName"
                        try {
                            $newTest = New-DefectDojoTest -EngagementId $engagementId -TestName $serviceName -TestType 20
                            Write-Log -Message "Test created successfully: $serviceName (ID: $($newTest.Id))"
                            $existingTests += $newTest
                            $testId = $newTest.Id
                        } catch {
                            Write-Log -Message "Failed to create test $serviceName : $_" -Level 'ERROR'
                            continue
                        }
                    } else {
                        Write-Log -Message "Using existing test: $($existingTest.Title) (ID: $($existingTest.Id))"
                        $testId = $existingTest.Id
                    }

                    Upload-DefectDojoScan -FilePath $file -TestId $testId -ScanType 'SARIF' -CloseOldFindings $Config.DefectDojo.CloseOldFindings
                } catch {
                    $uploadErrors++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }
            
            # Cleanup
            if (Test-Path $downloadRoot) { Remove-Item -Path $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log -Message "GitHub CodeQL processing failed: $_" -Level 'ERROR'
    }
}

function Invoke-Workflow-GitHubSecretScanning {
    param([hashtable]$Config)
    Write-Log -Message "Starting GitHub Secret Scanning download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-Log -Message 'No GitHub organizations configured.' -Level 'WARNING'
            return
        }

        GitHub-SecretScanDownload -Owners $orgs
        Write-Log -Message "GitHub Secret Scanning download completed."

        if ($Config.Tools.DefectDojo) {
            Write-Log -Message "Uploading GitHub Secret Scanning reports to DefectDojo..."
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubSecretScanning'
            $jsonFiles = Get-ChildItem -Path $downloadRoot -Filter '*-secrets.json' -Recurse | Select-Object -ExpandProperty FullName
            $uploadErrors = 0
            
            $engagementId = $Config.DefectDojo.EngagementId
            $existingTests = Get-DefectDojoTests -EngagementId $engagementId

            foreach ($file in $jsonFiles) {
                try {
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)
                    $repoName = $fileName -replace '-secrets$', ''
                    $baseServiceName = $repoName -replace '-\d+$', ''
                    $repoNameOnly = $baseServiceName
                    if ($baseServiceName -match '^(?<org>[^-]+)-(?<repo>.+)$') {
                        $repoNameOnly = $Matches['repo']
                    }

                    $serviceName = "$repoNameOnly (Secret Scanning)"
                    $existingTest = $existingTests | Where-Object {
                        $_.title -in @($serviceName, "$baseServiceName (Secret Scanning)", "$repoName (Secret Scanning)")
                    } | Select-Object -First 1

                    if (-not $existingTest) {
                        Write-Log -Message "Creating new test: $serviceName"
                        try {
                            $newTest = New-DefectDojoTest -EngagementId $engagementId -TestName $serviceName -TestType 215
                            Write-Log -Message "Test created successfully: $serviceName (ID: $($newTest.Id))"
                            $testId = $newTest.Id
                        } catch {
                            Write-Log -Message "Failed to create test $serviceName : $_" -Level 'ERROR'
                            continue
                        }
                    } else {
                        Write-Log -Message "Using existing test: $serviceName (ID: $($existingTest.Id))"
                        $testId = $existingTest.Id
                    }

                    Upload-DefectDojoScan -FilePath $file -TestId $testId -ScanType 'Universal Parser - GitHub Secret Scanning' -CloseOldFindings $Config.DefectDojo.CloseOldFindings
                } catch {
                    $uploadErrors++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }

            # Cleanup
            if (Test-Path $downloadRoot) { Remove-Item -Path $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log -Message "GitHub Secret Scanning processing failed: $_" -Level 'ERROR'
    }
}

function Invoke-Workflow-GitHubDependabot {
    param([hashtable]$Config)
    Write-Log -Message "Starting GitHub Dependabot download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-Log -Message 'No GitHub organizations configured.' -Level 'WARNING'
            return
        }

        $dependabotFiles = GitHub-DependabotDownload -Owners $orgs
        Write-Log -Message "GitHub Dependabot download completed."

        if (-not $dependabotFiles -or $dependabotFiles.Count -eq 0) {
            Write-Log -Message 'No open Dependabot alerts downloaded; skipping uploads.'
            return
        }

        if ($Config.Tools.DefectDojo) {
            $dependabotTestId = $Config.DefectDojo.GitHubDependabotTestId
            if (-not $dependabotTestId) {
                Write-Log -Message 'No DefectDojo Dependabot test ID configured; skipping uploads.' -Level 'WARNING'
                return
            }

            $uploadErrors = 0
            foreach ($file in $dependabotFiles) {
                try {
                    Upload-DefectDojoScan -FilePath $file -TestId $dependabotTestId -ScanType 'Universal Parser - GitHub Dependabot Aert5s' -CloseOldFindings $Config.DefectDojo.CloseOldFindings
                    Write-Log -Message "Uploaded Dependabot JSON: $([System.IO.Path]::GetFileName($file))"
                } catch {
                    $uploadErrors++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }
             # Cleanup
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubDependabot'
            if (Test-Path $downloadRoot) { Remove-Item -Path $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log -Message "GitHub Dependabot processing failed: $_" -Level 'ERROR'
    }
}

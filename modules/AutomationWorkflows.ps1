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

function Get-UploadTags {
    <#
    .SYNOPSIS
        Retrieves tags from config for DefectDojo uploads.
    .PARAMETER Config
        Configuration hashtable.
    .OUTPUTS
        Hashtable with Tags, ApplyTagsToFindings, ApplyTagsToEndpoints.
    #>
    param([hashtable]$Config)
    
    $result = @{
        Tags = @()
        ApplyTagsToFindings = $false
        ApplyTagsToEndpoints = $false
    }
    
    if ($Config.DefectDojo) {
        if ($Config.DefectDojo.Tags) {
            $result.Tags = @($Config.DefectDojo.Tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        if ($Config.DefectDojo.ApplyTagsToFindings) {
            $result.ApplyTagsToFindings = $Config.DefectDojo.ApplyTagsToFindings
        }
        if ($Config.DefectDojo.ApplyTagsToEndpoints) {
            $result.ApplyTagsToEndpoints = $Config.DefectDojo.ApplyTagsToEndpoints
        }
    }
    
    return $result
}

function Invoke-Workflow-TenableWAS {
    param([hashtable]$Config)

    $result = [PSCustomObject]@{
        Tool = 'TenableWAS'
        Success = 0
        Failed = 0
        Skipped = 0
        Total = 0
    }

    if (-not $Config.TenableWASSelectedScans -or $Config.TenableWASSelectedScans.Count -eq 0) {
        Write-Log -Message "No TenableWAS scans selected in configuration." -Level 'WARNING'
        $result.Skipped = 1
        return $result
    }

    # Initialize DefectDojo-specific variables if DefectDojo is enabled
    if ($Config.Tools.DefectDojo) {
        $engagementId = Get-EngagementIdForTool -Config $Config -Tool 'TenableWAS'
        if (-not $engagementId) {
            Write-Log -Message "No DefectDojo engagement ID configured; cannot create TenableWAS tests." -Level 'ERROR'
            $result.Failed = 1
            return $result
        }

        $existingTests = @(Get-DefectDojoTests -EngagementId $engagementId)
    }

    $result.Total = $Config.TenableWASSelectedScans.Count

    foreach ($scan in $Config.TenableWASSelectedScans) {
        # Handle scan object vs string (CLI might pass objects if loaded from JSON, or strings if from simple config)
        # Assuming $scan is an object with Name and Id as per Launch.ps1 usage
        if ($scan -is [string]) {
             # Fallback if just a name is passed.
             Write-Log -Message "Scan config is string, expected object. Skipping $scan" -Level 'ERROR'
             $result.Skipped++
             continue
        }

        Write-Log -Message "Starting TenableWAS scan export (Scan: $($scan.Name) - ID: $($scan.Id))"
        try {
            $exportedFile = Export-TenableWASScan -ScanName $scan.Name -ScanId $scan.Id
            Write-Log -Message "TenableWAS scan export completed: $exportedFile"

            if ($Config.Tools.DefectDojo) {
                Write-Log -Message "Processing TenableWAS scan for DefectDojo upload..."

                $serviceName = "$($scan.Name) (Tenable WAS)"
                $alternateNames = @($scan.Name, "$($scan.Name) (Tenable)")
                
                try {
                    $resolveResult = Resolve-DefectDojoTest -EngagementId $engagementId `
                                                           -TestName $serviceName `
                                                           -TestTypeName 'Tenable Scan' `
                                                           -ExistingTests $existingTests `
                                                           -AlternateNames $alternateNames
                    $testId = $resolveResult.TestId
                    $existingTests = $resolveResult.UpdatedTests
                } catch {
                    Write-Log -Message "Failed to resolve/create test ${serviceName}: $_" -Level 'ERROR'
                    $result.Failed++
                    continue
                }

                $filePathString = ([string]$exportedFile).Trim()
                $closeOldFindings = if ($Config.DefectDojo.CloseOldFindings -is [bool]) { $Config.DefectDojo.CloseOldFindings } else { $false }
                $tagParams = Get-UploadTags -Config $Config
                Upload-DefectDojoScan -FilePath $filePathString `
                                       -TestId $testId `
                                       -ScanType 'Tenable Scan' `
                                       -CloseOldFindings $closeOldFindings `
                                       -Tags $tagParams.Tags `
                                       -ApplyTagsToFindings $tagParams.ApplyTagsToFindings `
                                       -ApplyTagsToEndpoints $tagParams.ApplyTagsToEndpoints
                Write-Log -Message "TenableWAS scan report uploaded successfully to DefectDojo test: $serviceName"
            }
            $result.Success++
        } catch {
            $result.Failed++
            Write-Log -Message "TenableWAS processing failed for $($scan.Name): $_" -Level 'ERROR'
        }
    }
    
    return $result
}

function Invoke-Workflow-SonarQube {
    param([hashtable]$Config)
    
    $result = [PSCustomObject]@{
        Tool = 'SonarQube'
        Success = 0
        Failed = 0
        Skipped = 0
        Total = 1
    }
    
    Write-Log -Message "Processing SonarQube scan..."
    try {
        $apiScanConfigId = $Config.DefectDojo.APIScanConfigId
        $testId = $Config.DefectDojo.SonarQubeTestId

        if (-not $apiScanConfigId -or -not $testId) {
            Write-Log -Message "SonarQube processing requires APIScanConfigId and SonarQubeTestId in DefectDojo config." -Level 'ERROR'
            $result.Failed = 1
            return $result
        }

        Invoke-SonarQubeProcessing -ApiScanConfiguration $apiScanConfigId -Test $testId
        Write-Log -Message "SonarQube processing completed."
        $result.Success = 1
    } catch {
        Write-Log -Message "SonarQube processing failed: $_" -Level 'ERROR'
        $result.Failed = 1
    }
    
    return $result
}

function Invoke-Workflow-BurpSuite {
    param([hashtable]$Config)
    
    $result = [PSCustomObject]@{
        Tool = 'BurpSuite'
        Success = 0
        Failed = 0
        Skipped = 0
        Total = 0
    }
    
    Write-Log -Message "Starting BurpSuite XML report processing..."
    try {
        $xmlFiles = Get-BurpSuiteReports -FolderPath $Config.Paths.BurpSuiteXmlFolder

        if (-not $xmlFiles -or $xmlFiles.Count -eq 0) {
            Write-Log -Message "No BurpSuite XML files found in folder: $($Config.Paths.BurpSuiteXmlFolder)" -Level 'WARNING'
            $result.Skipped = 1
            return $result
        }

        Write-Log -Message "Found $($xmlFiles.Count) BurpSuite XML report(s)"
        $result.Total = 1  # Processing single file

        if ($Config.Tools.DefectDojo) {
            $burpTestId = $Config.DefectDojo.BurpSuiteTestId
            if (-not $burpTestId) {
                # No pre-configured TestId - try to auto-create under engagement
                $engagementId = Get-EngagementIdForTool -Config $Config -Tool 'BurpSuite'
                if (-not $engagementId) {
                    Write-Log -Message "No BurpSuite test ID or engagement ID configured for DefectDojo upload" -Level 'WARNING'
                    $result.Skipped = 1
                    return $result
                }
                
                # Look for existing test or create new one using helper
                $existingTests = @(Get-DefectDojoTests -EngagementId $engagementId)
                $testName = "BurpSuite Scan"
                
                try {
                    $resolveResult = Resolve-DefectDojoTest -EngagementId $engagementId `
                                                           -TestName $testName `
                                                           -TestTypeName 'Burp Scan' `
                                                           -ExistingTests $existingTests
                    $burpTestId = $resolveResult.TestId
                } catch {
                    Write-Log -Message "Failed to resolve/create BurpSuite test: $_" -Level 'ERROR'
                    $result.Failed = 1
                    return $result
                }
            }

            $xmlFile = $xmlFiles[0]
            $fileName = [System.IO.Path]::GetFileName($xmlFile)

            if ($xmlFiles.Count -gt 1) {
                Write-Log -Message "Multiple XML files found. Uploading only: $fileName" -Level 'WARNING'
            }

            try {
                Write-Log -Message "Uploading $fileName to DefectDojo test ID: $burpTestId"
                $filePathString = ([string]$xmlFile).Trim()
                $closeOldFindings = if ($Config.DefectDojo.CloseOldFindings -is [bool]) { $Config.DefectDojo.CloseOldFindings } else { $false }
                $tagParams = Get-UploadTags -Config $Config
                Upload-DefectDojoScan -FilePath $filePathString `
                                       -TestId $burpTestId `
                                       -ScanType 'Burp Scan' `
                                       -CloseOldFindings $closeOldFindings `
                                       -Tags $tagParams.Tags `
                                       -ApplyTagsToFindings $tagParams.ApplyTagsToFindings `
                                       -ApplyTagsToEndpoints $tagParams.ApplyTagsToEndpoints
                Write-Log -Message "Successfully uploaded $fileName"
                $result.Success = 1
            } catch {
                Write-Log -Message "Failed to upload $fileName : $_" -Level 'ERROR'
                $result.Failed = 1
            }
        }
    } catch {
        Write-Log -Message "BurpSuite processing failed: $_" -Level 'ERROR'
        $result.Failed = 1
    }
    
    return $result
}

function Invoke-Workflow-GitHubCodeQL {
    param([hashtable]$Config)
    
    $result = [PSCustomObject]@{
        Tool = 'GitHub CodeQL'
        Success = 0
        Failed = 0
        Skipped = 0
        Total = 0
    }
    
    Write-Log -Message "Starting GitHub CodeQL download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-Log -Message "No GitHub organizations configured. Skipping GitHub processing." -Level 'WARNING'
            $result.Skipped = 1
            return $result
        }

        GitHub-CodeQLDownload -Owners $orgs
            Write-Log -Message "GitHub CodeQL download completed."

            if ($Config.Tools.DefectDojo) {
                Write-Log -Message "Uploading GitHub CodeQL reports to DefectDojo..."
                $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubCodeScanning'
                $sarifFiles = Get-ChildItem -Path $downloadRoot -Filter '*.sarif' -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
                $result.Total = $sarifFiles.Count

                if ($sarifFiles.Count -eq 0) {
                    Write-Log -Message "GitHub CodeQL completed: No SARIF files found." -Level 'INFO'
                }

                $engagementId = Get-EngagementIdForTool -Config $Config -Tool 'CodeQL'
                if (-not $engagementId) {
                    Write-Log -Message "No DefectDojo engagement ID configured; skipping GitHub uploads." -Level 'WARNING'
                    $result.Skipped = $result.Total
                return $result
            }
            $existingTests = @(Get-DefectDojoTests -EngagementId $engagementId)
            
            $closeOldFindings = if ($Config.DefectDojo.CloseOldFindings -is [bool]) { $Config.DefectDojo.CloseOldFindings } else { $false }
            
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
                    $alternateNames = @($serviceNameCore, $repoNameOnly)

                    try {
                        $resolveResult = Resolve-DefectDojoTest -EngagementId $engagementId `
                                                               -TestName $serviceName `
                                                               -TestTypeName 'SARIF' `
                                                               -ExistingTests $existingTests `
                                                               -AlternateNames $alternateNames
                        $testId = $resolveResult.TestId
                        $existingTests = $resolveResult.UpdatedTests
                    } catch {
                        Write-Log -Message "Failed to resolve/create test $serviceName : $_" -Level 'ERROR'
                        $result.Failed++
                        continue
                    }

                    $tagParams = Get-UploadTags -Config $Config
                    Upload-DefectDojoScan -FilePath $file `
                                           -TestId $testId `
                                           -ScanType 'SARIF' `
                                           -CloseOldFindings $closeOldFindings `
                                           -Tags $tagParams.Tags `
                                           -ApplyTagsToFindings $tagParams.ApplyTagsToFindings `
                                           -ApplyTagsToEndpoints $tagParams.ApplyTagsToEndpoints
                    $result.Success++
                } catch {
                    $result.Failed++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }
            
            # Cleanup
            if (Test-Path $downloadRoot) { Remove-Item -Path $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log -Message "GitHub CodeQL processing failed: $_" -Level 'ERROR'
        $result.Failed = 1
    }
    
    return $result
}

function Invoke-Workflow-GitHubSecretScanning {
    param([hashtable]$Config)
    
    $result = [PSCustomObject]@{
        Tool = 'GitHub Secret Scanning'
        Success = 0
        Failed = 0
        Skipped = 0
        Total = 0
    }
    
    Write-Log -Message "Starting GitHub Secret Scanning download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-Log -Message 'No GitHub organizations configured.' -Level 'WARNING'
            $result.Skipped = 1
            return $result
        }

        GitHub-SecretScanDownload -Owners $orgs
        Write-Log -Message "GitHub Secret Scanning download completed."

        if ($Config.Tools.DefectDojo) {
            Write-Log -Message "Uploading GitHub Secret Scanning reports to DefectDojo..."
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubSecretScanning'
            $jsonFiles = Get-ChildItem -Path $downloadRoot -Filter '*-secrets.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            $result.Total = $jsonFiles.Count

            if ($jsonFiles.Count -eq 0) {
                Write-Log -Message "GitHub Secret Scanning completed: No alert files found." -Level 'INFO'
            }
            
            $engagementId = Get-EngagementIdForTool -Config $Config -Tool 'SecretScan'
            if (-not $engagementId) {
                Write-Log -Message "No DefectDojo engagement ID configured; skipping GitHub Secret Scanning uploads." -Level 'WARNING'
                $result.Skipped = $result.Total
                return $result
            }
            $existingTests = Get-DefectDojoTests -EngagementId $engagementId

            $closeOldFindings = if ($Config.DefectDojo.CloseOldFindings -is [bool]) { $Config.DefectDojo.CloseOldFindings } else { $false }

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
                    $alternateNames = @("$baseServiceName (Secret Scanning)", "$repoName (Secret Scanning)")

                    try {
                        $resolveResult = Resolve-DefectDojoTest -EngagementId $engagementId `
                                                               -TestName $serviceName `
                                                               -TestTypeName 'Universal Parser - GitHub Secret Scanning' `
                                                               -ExistingTests $existingTests `
                                                               -AlternateNames $alternateNames
                        $testId = $resolveResult.TestId
                        $existingTests = $resolveResult.UpdatedTests
                    } catch {
                        Write-Log -Message "Failed to resolve/create test $serviceName : $_" -Level 'ERROR'
                        $result.Failed++
                        continue
                    }

                    $tagParams = Get-UploadTags -Config $Config
                    Upload-DefectDojoScan -FilePath $file `
                                           -TestId $testId `
                                           -ScanType 'Universal Parser - GitHub Secret Scanning' `
                                           -CloseOldFindings $closeOldFindings `
                                           -Tags $tagParams.Tags `
                                           -ApplyTagsToFindings $tagParams.ApplyTagsToFindings `
                                           -ApplyTagsToEndpoints $tagParams.ApplyTagsToEndpoints
                    $result.Success++
                } catch {
                    $result.Failed++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }

            # Cleanup
            if (Test-Path $downloadRoot) { Remove-Item -Path $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log -Message "GitHub Secret Scanning processing failed: $_" -Level 'ERROR'
        $result.Failed = 1
    }
    
    return $result
}

function Invoke-Workflow-GitHubDependabot {
    param([hashtable]$Config)
    
    $result = [PSCustomObject]@{
        Tool = 'GitHub Dependabot'
        Success = 0
        Failed = 0
        Skipped = 0
        Total = 0
    }
    
    Write-Log -Message "Starting GitHub Dependabot download..."
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-Log -Message 'No GitHub organizations configured.' -Level 'WARNING'
            $result.Skipped = 1
            return $result
        }

        $dependabotFiles = GitHub-DependabotDownload -Owners $orgs
        Write-Log -Message "GitHub Dependabot download completed."

        if (-not $dependabotFiles -or $dependabotFiles.Count -eq 0) {
            Write-Log -Message 'No open Dependabot alerts downloaded; skipping uploads.'
            $result.Skipped = 1
            return $result
        }

        $result.Total = $dependabotFiles.Count

        if ($Config.Tools.DefectDojo) {
            $dependabotTestId = $Config.DefectDojo.GitHubDependabotTestId
            if (-not $dependabotTestId) {
                # No pre-configured TestId - try to auto-create under engagement
                $engagementId = Get-EngagementIdForTool -Config $Config -Tool 'Dependabot'
                if (-not $engagementId) {
                    Write-Log -Message 'No Dependabot test ID or engagement ID configured; skipping uploads.' -Level 'WARNING'
                    $result.Skipped = $result.Total
                    return $result
                }
                
                # Look for existing test or create new one using helper
                $existingTests = @(Get-DefectDojoTests -EngagementId $engagementId)
                $testName = "GitHub Dependabot"
                
                try {
                    $resolveResult = Resolve-DefectDojoTest -EngagementId $engagementId `
                                                           -TestName $testName `
                                                           -TestTypeName 'Universal Parser - GitHub Dependabot Aert5s' `
                                                           -ExistingTests $existingTests
                    $dependabotTestId = $resolveResult.TestId
                } catch {
                    Write-Log -Message "Failed to resolve/create Dependabot test: $_" -Level 'ERROR'
                    $result.Failed = 1
                    return $result
                }
            }

            $closeOldFindings = if ($Config.DefectDojo.CloseOldFindings -is [bool]) { $Config.DefectDojo.CloseOldFindings } else { $false }
            $tagParams = Get-UploadTags -Config $Config

            foreach ($file in $dependabotFiles) {
                try {
                    Upload-DefectDojoScan -FilePath $file `
                                           -TestId $dependabotTestId `
                                           -ScanType 'Universal Parser - GitHub Dependabot Aert5s' `
                                           -CloseOldFindings $closeOldFindings `
                                           -Tags $tagParams.Tags `
                                           -ApplyTagsToFindings $tagParams.ApplyTagsToFindings `
                                           -ApplyTagsToEndpoints $tagParams.ApplyTagsToEndpoints
                    Write-Log -Message "Uploaded Dependabot JSON: $([System.IO.Path]::GetFileName($file))"
                    $result.Success++
                } catch {
                    $result.Failed++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }
             # Cleanup
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubDependabot'
            if (Test-Path $downloadRoot) { Remove-Item -Path $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log -Message "GitHub Dependabot processing failed: $_" -Level 'ERROR'
        $result.Failed = 1
    }
    
    return $result
}

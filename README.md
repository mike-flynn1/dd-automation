# DefectDojo Automation Script Collection

## Overview

A comprehensive PowerShell-based automation toolset that orchestrates security findings export and import between multiple security scanning tools and DefectDojo for centralized vulnerability management. The solution features a modern GUI interface, CLI support for automation/scheduling, and extensive API integrations with security tools.

**Core Purpose**: Streamline the workflow of collecting security scan results from tools like Tenable WAS, SonarQube, GitHub Advanced Security, and BurpSuite, then automatically importing them into DefectDojo for unified vulnerability tracking and remediation management.

### Key Features

- **Multi-Tool Integration**: Tenable WAS, SonarQube, GitHub Advanced Security (CodeQL, Secret Scanning, Dependabot), BurpSuite
- **Dual Interface**: Interactive GUI (Launch.ps1) and headless CLI (Run-Automation.ps1) for scheduled tasks
- **Modular Architecture**: Extensible design using PowerShell dot-sourcing pattern for easy addition of new integrations
- **Automated Test Creation**: Dynamically creates DefectDojo tests per scan/repository when needed
- **Advanced Filtering**: Repository filtering with include/exclude patterns and wildcard support
- **Configuration Persistence**: User selections automatically saved to config file
- **Comprehensive Testing**: Full Pester 5+ test suite with GitHub Actions CI/CD integration
- **Webhook Notifications**: Power Automate/Teams notifications for scheduled automation runs with Adaptive Card support
- **DefectDojo CLI Integration**: Built-in launcher for manual uploads via DefectDojo CLI tool

### Supported Integrations

| Tool | Status | Features |
|------|--------|----------|
| **Tenable WAS** | Complete | Live scan list, batch processing, CSV export, automatic test creation |
| **SonarQube** | Complete | DefectDojo API Scan Configuration integration, direct API import |
| **GitHub CodeQL** | Complete | SARIF report download, per-repo test creation, latest analysis per category |
| **GitHub Secret Scanning** | Complete | JSON alert export, open alert filtering, automatic feature detection |
| **GitHub Dependabot** | Complete | Open alert export, configurable DefectDojo test target |
| **BurpSuite** | Complete | Local XML report scanning, batch upload |
| **DefectDojo** | Complete | Product/Engagement/Test management, API Scan Configurations, CLI launcher |

## Project Structure

```
dd-automation/
├── .github/
│   └── workflows/
│       └── test.yml                 # GitHub Actions CI/CD pipeline
├── config/
│   ├── config.psd1                  # User configuration (gitignored)
│   └── config.psd1.example          # Configuration template
├── logs/
│   ├── DDAutomationLauncher_Renewed.log  # GUI mode log file
│   └── DDAutomation_CLI.log         # CLI mode log file
├── modules/                         # Core functionality modules
│   ├── Config.ps1                   # Configuration loading/validation
│   ├── Logging.ps1                  # Logging framework
│   ├── EnvValidator.ps1             # Environment variable validation
│   ├── DefectDojo.ps1               # DefectDojo API wrapper
│   ├── TenableWAS.ps1               # Tenable WAS integration
│   ├── Sonarqube.ps1                # SonarQube integration
│   ├── GitHub.ps1                   # GitHub Advanced Security integration
│   ├── BurpSuite.ps1                # BurpSuite integration
│   ├── Uploader.ps1                 # File upload to DefectDojo
│   ├── Notifications.ps1            # Webhook notification system
│   ├── AutomationWorkflows.ps1      # Workflow orchestration logic
│   ├── defectdojo-cli.exe           # DefectDojo CLI tool (binary)
│   └── universal-importer.exe       # DefectDojo universal importer (binary)
├── Tests/                           # Pester 5+ test suite
│   ├── Config.Tests.ps1             # Configuration tests
│   ├── DefectDojo.Tests.ps1         # DefectDojo API tests
│   ├── EnvValidator.Tests.ps1       # Environment validation tests
│   ├── GitHub.Tests.ps1             # GitHub integration tests
│   ├── Logging.Tests.ps1            # Logging framework tests
│   ├── TenableWAS.Tests.ps1         # Tenable WAS tests
│   ├── BurpSuite.Tests.ps1          # BurpSuite tests
│   ├── Notifications.Tests.ps1      # Notification tests
│   └── AutomationWorkflows.Tests.ps1  # Workflow orchestration tests
├── Launch.ps1                       # GUI launcher (interactive mode)
├── Run-Automation.ps1               # CLI launcher (headless mode)
├── run.bat                          # Windows batch file wrapper
├── README.md                        # This file
├── CHANGELOG.md                     # Version history
└── .gitignore                       # Git ignore rules
```

## Prerequisites

### System Requirements
- **Operating System**: Windows 10 or Windows 11
- **PowerShell**: Version 7.2 or later (automatically prompted for installation if missing)
- **Network Access**: Connectivity to DefectDojo, Tenable WAS, GitHub, and SonarQube APIs
- **Pester Testing Framework**: Version 5+ (required only for local development; GitHub Actions runs tests automatically)

### Required Permissions
- **DefectDojo**: API token with permissions to create/update products, engagements, tests, and import scans
- **Tenable WAS**: API access and secret keys with scan read permissions
- **GitHub**: Personal Access Token (PAT) with `repo` and `security_events` scopes for all target organizations
- **SonarQube**: User token with project access (stored in DefectDojo API Scan Configuration)

## Installation

### 1. Clone the Repository
```powershell
git clone <repository-url>
cd dd-automation
```

### 2. Install PowerShell 7.2+ (if needed)
The launcher script will automatically detect and offer to install PowerShell 7.2+ via Winget if not present.

Manual installation:
```powershell
winget install --id Microsoft.PowerShell --source winget
```

Or download from: https://aka.ms/pscore

### 3. Set Environment Variables

Configure the following environment variables with your API credentials:

| Variable | Description | Required For |
|----------|-------------|--------------|
| `DOJO_API_KEY` | DefectDojo API token | All DefectDojo uploads; auto-synced to `DD_CLI_API_TOKEN` |
| `TENWAS_ACCESS_KEY` | Tenable WAS API access key | Tenable WAS scan exports |
| `TENWAS_SECRET_KEY` | Tenable WAS API secret key | Tenable WAS scan exports |
| `GITHUB_PAT` | GitHub Personal Access Token | GitHub Advanced Security integrations |
| `DD_CLI_API_TOKEN` | DefectDojo CLI token | Auto-created from `DOJO_API_KEY` (do not set manually) |

**Setting Environment Variables** (PowerShell):
```powershell
# User-level (persistent across sessions)
[System.Environment]::SetEnvironmentVariable('DOJO_API_KEY', 'your-key-here', [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('TENWAS_ACCESS_KEY', 'your-key-here', [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('TENWAS_SECRET_KEY', 'your-secret-here', [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('GITHUB_PAT', 'your-pat-here', [System.EnvironmentVariableTarget]::User)

# Restart PowerShell to load new environment variables
```

**Environment Validation**: The tool automatically validates environment variables on startup and prompts for missing values with a user-friendly GUI or console interface.

### 4. Create Configuration File

Copy the example configuration and customize for your environment:

```powershell
Copy-Item .\config\config.psd1.example .\config\config.psd1
```

**Important**: The `config\config.psd1` file is gitignored to protect your personal settings. Edit this file to configure API base URLs, tool selections, and DefectDojo test IDs.

## Configuration

### Configuration File Structure

The `config\config.psd1` file uses PowerShell data file format (hashtable) for easy editing:

```powershell
@{
    # Tool enable/disable flags
    Tools = @{
        TenableWAS = $true
        SonarQube  = $false
        BurpSuite  = $false
        DefectDojo = $true
        GitHub = @{
            CodeQL         = $true   # Enable GitHub CodeQL SARIF downloads
            SecretScanning = $false  # Enable GitHub Secret Scanning JSON
            Dependabot     = $false  # Enable GitHub Dependabot alerts
        }
    }

    # API base URLs for all integrations
    ApiBaseUrls = @{
        DefectDojo = 'https://defectdojo.example.com/api/v2'
        TenableWAS = 'https://fedcloud.tenable.com/'
        SonarQube  = 'https://sonarqube.example.com/api'
        GitHub     = 'https://api.github.com'
    }

    # File paths for local tool inputs
    Paths = @{
        BurpSuiteXmlFolder = 'C:\SecurityScans\BurpSuite\'
    }

    # TenableWAS scan selection (persisted from GUI)
    TenableWASScanNames = @(
        'Production Web App Scan'
        'Staging Environment Scan'
    )

    # DefectDojo configuration (IDs auto-populated from GUI selections)
    DefectDojo = @{
        ProductId              = 123
        EngagementId           = 456
        SonarQubeTestId        = 789
        BurpSuiteTestId        = 790
        GitHubDependabotTestId = 791
        MinimumSeverity        = 'Low'
        APIScanConfigId        = 1
        CloseOldFindings       = $false
    }

    # GitHub configuration
    GitHub = @{
        Orgs = @(
            'your-org-name'
            'another-org-name'
        )

        # Repository filtering (all optional)
        SkipArchivedRepos = $true  # Skip archived repos (default: true)
        
        IncludeRepos = @(
            # 'production-*'    # Whitelist: only process these patterns
            # 'critical-app'
        )
        
        ExcludeRepos = @(
            # 'test-*'          # Blacklist: skip these patterns
            # '*-demo'
        )
    }

    # Webhook notifications for CLI automation (optional)
    Notifications = @{
        WebhookUrl  = 'https://prod-123.westus.logic.azure.com:443/workflows/YOUR/WEBHOOK/URL'
        WebhookType = 'PowerAutomate'  # Options: 'PowerAutomate' (default), 'Teams'
    }
}
```

### Configuration Options Explained

#### Tools Section
- Controls which integrations are enabled/disabled
- GitHub tools use nested hashtable for granular feature control
- GUI checkboxes automatically update these values

#### ApiBaseUrls Section
- Base URLs for all API integrations
- Must include `/api/v2` suffix for DefectDojo
- Tenable WAS uses cloud endpoint `https://fedcloud.tenable.com/` (or your regional endpoint)

#### Paths Section
- File system paths for tools requiring local inputs (BurpSuite)
- Folder path for XML report scanning

#### TenableWAS Configuration
- **TenableWASScanNames**: Array of scan names selected in GUI (automatically persisted)
- Scan names retrieved via API from Tenable WAS (no manual GUID management required)

#### DefectDojo Configuration
- **ProductId**: Target DefectDojo product ID (auto-populated from GUI dropdown)
- **EngagementId**: Target engagement ID (auto-populated from GUI dropdown)
- **SonarQubeTestId**: Pre-selected test for SonarQube imports
- **BurpSuiteTestId**: Pre-selected test for BurpSuite uploads
- **GitHubDependabotTestId**: Pre-selected test for Dependabot alerts
- **MinimumSeverity**: Severity threshold (`Info`, `Low`, `Medium`, `High`, `Critical`)
- **APIScanConfigId**: DefectDojo API Scan Configuration ID for SonarQube
- **CloseOldFindings**: When `$true`, old findings are closed on reimport; when `$false`, previous findings preserved

#### GitHub Repository Filtering

The GitHub integration supports flexible repository filtering to control which repositories are processed:

**Skip Archived Repositories** (default: enabled)
```powershell
GitHub = @{
    SkipArchivedRepos = $true  # Skip archived repos
}
```

**Include-Only Filter (Whitelist)**  
When specified, ONLY repositories matching these patterns will be processed:
```powershell
IncludeRepos = @(
    'production-*'     # All repos starting with 'production-'
    'critical-app'     # Exact match
    '*-api'            # All repos ending with '-api'
    '*security*'       # Any repo containing 'security'
)
```

**Exclude Filter (Blacklist)**  
Repositories matching these patterns will be skipped (applied after include filter):
```powershell
ExcludeRepos = @(
    'test-*'           # Skip all test repos
    '*-demo'           # Skip all demo repos
    'archived-*'       # Skip repos starting with 'archived-'
    'old-legacy-app'   # Skip specific repo
)
```

**Pattern Matching Rules:**
- Supports PowerShell wildcards: `*` (any characters), `?` (single character)
- Case-insensitive matching
- Filter order: Archived → Include → Exclude
- All filtering decisions logged to `logs/DDAutomationLauncher_Renewed.log`

## Usage

### GUI Mode (Interactive)

The GUI provides an intuitive interface for configuring and running automation workflows.

**Launch the GUI**:
```powershell
.\Launch.ps1
```

**GUI Features**:
1. **Tool Selection**: Check/uncheck tools to enable/disable integrations
2. **TenableWAS Controls**:
   - Multi-select checklist with live scan names from API
   - Real-time search/filter box
   - Refresh button to reload scan list
3. **GitHub Organizations**: Comma-separated list of organizations (editable textbox)
4. **BurpSuite Folder**: Browse to folder containing XML reports
5. **DefectDojo Configuration**:
   - Product dropdown (loads available products from API)
   - Engagement dropdown (loads engagements for selected product)
   - Test dropdowns for each tool (loads tests for selected engagement)
   - API Scan Configuration dropdown (for SonarQube)
   - Minimum severity selector
   - Close Old Findings checkbox
6. **Status Log**: Real-time progress display with timestamps
7. **DefectDojo CLI Launcher**: Opens DefectDojo CLI tool in interactive mode for manual uploads
8. **Action Buttons**: "GO" to start automation, "Close" to exit

**Workflow**:
1. Select tools to run via checkboxes (all have tooltips explaining functionality)
2. Configure tool-specific settings (scans, folders, organizations)
3. Select DefectDojo Product → Engagement → Tests (cascading dropdowns)
4. Click **GO** to start processing
5. Monitor progress in status log
6. Selections automatically saved to config file for next run

**Tooltips**: All controls have tooltips with detailed explanations (hover over checkboxes, buttons, and text fields)

### CLI Mode (Headless / Scheduled Tasks)

For CI/CD pipelines, Cron jobs, or Windows Task Scheduler, use the headless CLI script.

**Basic Execution** (uses default `config\config.psd1`):
```powershell
.\Run-Automation.ps1
```

**Custom Configuration File**:
```powershell
.\Run-Automation.ps1 -ConfigPath "C:\Configs\NightlyScan.psd1"
```

**Webhook Notifications**:
```powershell
.\Run-Automation.ps1 -WebhookUrl "https://prod-123.westus.logic.azure.com:443/workflows/YOUR/WEBHOOK/URL"
```

Or configure webhooks permanently in `config.psd1`:
```powershell
Notifications = @{
    WebhookUrl  = 'https://prod-123.westus.logic.azure.com:443/workflows/...'
    WebhookType = 'PowerAutomate'  # Options: 'PowerAutomate' (default), 'Teams'
}
```

**Supported Webhook Types**:
- **PowerAutomate** (default): Sends Adaptive Card format compatible with Power Automate workflows
- **Teams**: Sends MessageCard format compatible with Microsoft Teams incoming webhooks

Webhook notifications include:
- Automation completion status (Success/Error)
- Execution timestamp
- List of tools executed
- Color-coded status indicator

**CLI Behavior**:
- Loads configuration from specified file (or default)
- Validates environment variables (non-interactive mode)
- Executes all enabled workflows in sequence
- Sends webhook notification on completion or error
- Logs to `logs\DDAutomation_CLI.log`

**Windows Task Scheduler Example**:
```
Program: C:\Program Files\PowerShell\7\pwsh.exe
Arguments: -NoProfile -ExecutionPolicy Bypass -File "C:\dd-automation\Run-Automation.ps1"
Working Directory: C:\dd-automation
```

### Manual Upload (DefectDojo CLI)

The GUI includes an integrated launcher for the DefectDojo CLI tool for specialized manual upload scenarios.

**Purpose**: Enables manual uploads for custom file formats or operations not handled by automated workflows.

**How to Use**:
1. Click **Launch DefectDojo CLI** button in GUI
2. DefectDojo CLI opens in a new PowerShell window in interactive mode
3. Use menu-driven interface for manual operations
4. Console window remains open after operations complete

**Behavior**:
- Automatically synchronizes `DOJO_API_KEY` to `DD_CLI_API_TOKEN` (user-level environment variable)
- Launches `modules\defectdojo-cli.exe` from modules directory
- Runs in PowerShell 7 (`pwsh.exe`) with `-NoExit` flag

**Prerequisites**:
- `DOJO_API_KEY` environment variable must be set
- DefectDojo CLI executable must exist at `modules\defectdojo-cli.exe`

**Troubleshooting**:
- Error dialog appears if `DOJO_API_KEY` not set or CLI executable missing
- Check GUI status log and `logs\DDAutomationLauncher_Renewed.log` for detailed errors

## Integration Details

### Tenable WAS Integration

Exports vulnerability scan results from Tenable's Web Application Scanning cloud platform.

**Features**:
- Live scan list retrieval from API with automatic filtering (active, completed scans only)
- Scan name-based selection (no manual GUID management)
- Batch processing (select multiple scans)
- CSV report generation and download
- Automatic DefectDojo test creation per scan (naming: `{ScanName} (Tenable WAS)`)

**Configuration**:
```powershell
ApiBaseUrls = @{
    TenableWAS = 'https://fedcloud.tenable.com/'
}

TenableWASScanNames = @(
    'Production Web Scan'
    'Staging API Scan'
)

```

**API Workflow**:
1. `Get-TenableWASScanConfigs` retrieves all scan configurations
2. Filters to active scans with completed executions (`last_scan.scan_id`)
3. For each selected scan:
   - **PUT** `/was/v2/scans/{scanId}/report` - Initiate report
   - Sleep 2 seconds (report processing time)
   - **GET** `/was/v2/scans/{scanId}/report` - Download CSV
4. Upload to DefectDojo test (creates test if needed)

**File Locations**:
- Exported reports: `%TEMP%\{scanName}.csv`
- Log file: `logs\DDAutomationLauncher_Renewed.log`

**Limitations**:
- Only exports most recent scan per configuration (`last_scan.scan_id`)
- No historical scan selection
- 2-second delay hard-coded for report generation

### SonarQube Integration

Leverages DefectDojo's built-in SonarQube API Import feature for direct integration.

**Features**:
- API-based import (no file downloads)
- Uses DefectDojo Product API Scan Configuration system
- Re-import support (updates existing findings)
- Configurable severity filtering

**Configuration**:
```powershell
DefectDojo = @{
    APIScanConfigId   = 1
    SonarQubeTestId   = 456
    MinimumSeverity   = 'Low'
}
```

**Pre-requisites**:
1. Configure Product API Scan Configuration in DefectDojo:
   - Navigate to Product → Settings → API Scan Configurations
   - Create new configuration with:
     - **Tool Type**: SonarQube
     - **Service Key 1**: SonarQube project key
     - **API Key**: SonarQube user token
     - **Additional Fields**: SonarQube server URL

**Workflow**:
1. User selects API Scan Configuration from dropdown (shows project keys)
2. User selects target DefectDojo test
3. Tool posts to `/reimport-scan/` with:
   - `scan_type`: "SonarQube API Import"
   - `api_scan_configuration`: Configuration ID
   - `test`: Test ID
4. DefectDojo handles SonarQube API communication internally

**Advantages**:
- No credential management (stored in DefectDojo)
- No file handling (eliminates download/upload)
- Automatic updates (re-import vs duplicate findings)

**Limitations**:
- API Scan Configuration must be pre-configured in DefectDojo
- Cannot filter findings before import (all findings imported based on severity threshold)

### GitHub Advanced Security Integration

Automatically downloads security findings from GitHub Advanced Security features across multiple organizations.

#### GitHub CodeQL (Code Scanning)

**Features**:
- Downloads latest SARIF report per analysis category
- Filters out analyses with zero results
- Automatic DefectDojo test creation per repository (naming: `{repo-name} (CodeQL)`)
- Multi-organization support

**API Workflow**:
1. `Get-GitHubRepos` retrieves all repositories for configured organizations
2. Applies repository filtering (archived, include/exclude patterns)
3. For each repository:
   - **GET** `/repos/{owner}/{repo}/code-scanning/analyses` - List analyses
   - Select latest analysis per category with results
   - **GET** analysis SARIF URL - Download report
4. Save to `%TEMP%\GitHubCodeScanning\{repo-name}-{analysisId}.sarif`
5. Upload to DefectDojo with scan type "SARIF"

**Configuration**:
```powershell
Tools = @{
    GitHub = @{
        CodeQL = $true
    }
}

GitHub = @{
    Orgs = @('your-org-name')
    SkipArchivedRepos = $true
}
```

**Limitations**:
- Only processes latest analysis per category
- Requires GitHub Advanced Security enabled on repositories
- Analyses with zero results are filtered out

#### GitHub Secret Scanning

**Features**:
- Downloads open secret scanning alerts as JSON
- Automatic feature detection (gracefully handles repos without Secret Scanning)
- Automatic DefectDojo test creation per repository (naming: `{repo-name} (Secret Scanning)`)

**API Workflow**:
1. For each repository (after filtering):
   - **GET** `/repos/{owner}/{repo}/secret-scanning/alerts?state=open` - Open alerts
   - Save to `%TEMP%\GitHubSecretScanning\{repo-name}-secrets.json`
2. Upload to DefectDojo with scan type "Github Vulnerability Scan"

**Configuration**:
```powershell
Tools = @{
    GitHub = @{
        SecretScanning = $true
    }
}
```

**Limitations**:
- Only retrieves open alerts (not resolved/closed)
- Repos without Secret Scanning enabled logged as warnings and skipped

#### GitHub Dependabot

**Features**:
- Downloads open Dependabot alerts as JSON
- User-selectable DefectDojo test target (no automatic test creation)

**API Workflow**:
1. For each repository (after filtering):
   - **GET** `/repos/{owner}/{repo}/dependabot/alerts?state=open` - Open alerts
   - Save to `%TEMP%\GitHubDependabot\{repo-name}-dependabot.json`
2. Upload to user-selected DefectDojo test

**Configuration**:
```powershell
Tools = @{
    GitHub = @{
        Dependabot = $true
    }
}

DefectDojo = @{
    GitHubDependabotTestId = 791
}
```

**Limitations**:
- Requires manual test selection in GUI (no automatic test creation)
- Only retrieves open alerts

### BurpSuite Integration

Processes locally stored XML reports from BurpSuite Scanner (Professional or Enterprise).

**Features**:
- Local folder scanning for XML reports
- Batch upload (all XML files in folder)
- Direct DefectDojo upload with "Burp Scan" parser

**Configuration**:
```powershell
Paths = @{
    BurpSuiteXmlFolder = 'C:\SecurityScans\BurpSuite\'
}

DefectDojo = @{
    BurpSuiteTestId = 790
}
```

**Workflow**:
1. User specifies folder containing BurpSuite XML reports (via textbox or browse button)
2. `Get-BurpSuiteReports` scans folder for `*.xml` files
3. For each XML file:
   - Upload to DefectDojo test via `/reimport-scan/`
   - Uses scan type "Burp Scan"
4. Errors logged; processing continues with remaining files

**Limitations**:
- XML reports must be manually exported from BurpSuite (no API automation)
- Only XML format supported (JSON/HTML not supported)
- No automatic scan discovery
- All reports upload to same DefectDojo test
```

### Module Architecture

The project uses a modular architecture with PowerShell dot-sourcing pattern for maximum portability and testability:

**Core Modules**:
- **Config.ps1**: Loads configuration from PSD1 files, provides validation, and handles save operations
- **Logging.ps1**: Centralized logging with `Initialize-Log` and `Write-Log` functions
- **EnvValidator.ps1**: Validates required environment variables with user prompts (GUI or console fallback)
- **DefectDojo.ps1**: API wrapper with functions for products, engagements, tests, test types, and scan uploads
- **TenableWAS.ps1**: Scan configuration retrieval and CSV report export
- **Sonarqube.ps1**: DefectDojo API Scan Configuration integration
- **GitHub.ps1**: Repository retrieval, CodeQL SARIF download, Secret Scanning JSON, Dependabot alerts
- **BurpSuite.ps1**: Local XML file discovery
- **Uploader.ps1**: Multipart form-data file upload to DefectDojo `/reimport-scan/` endpoint
- **Notifications.ps1**: Webhook notification sender (Power Automate/Teams compatible with Adaptive Cards)
- **AutomationWorkflows.ps1**: Workflow orchestration logic (separated from GUI for CLI reuse)

**Design Patterns**:
- **Dot-sourcing**: All modules loaded via `. (Join-Path ...)` for portability
- **PSScriptRoot**: All modules use `$PSScriptRoot` for reliable path resolution (critical for Pester testing)
- **Config-driven**: Tool selections and API endpoints managed via PSD1 configuration
- **Event-driven GUI**: Windows Forms with cascading dropdown dependencies
- **API-first**: All integrations use REST APIs with proper authentication

## Continuous Integration

This project uses **GitHub Actions** to automatically run all Pester tests on every pull request.

### GitHub Actions Workflow

**Workflow File**: `.github\workflows\test.yml`

**Trigger**: Pull requests targeting `main` branch

**Platform**: `windows-latest` (required for Windows Forms assemblies)

**What It Does**:
1. Checks out the repository
2. Runs all tests in `Tests\` using Pester 5+ with detailed output
3. Exports test results in JUnit XML format
4. Uploads test results as downloadable artifact (30-day retention)
5. Publishes test results to PR "Checks" tab via `dorny/test-reporter`
6. Fails the workflow if any test fails

**Test Result Artifacts**:
- Available in workflow run under "Artifacts"
- File: `test-results.xml` (JUnit format)
- Retention: 30 days

**Viewing Test Results**:
- Test results appear in "Checks" tab of pull requests
- Detailed test output available in workflow logs
- Failed tests prevent PR merge when branch protection configured

### For Contributors

**Before Pushing**:
- Create applicable tests for all new code
- Run tests locally: `Invoke-Pester .\Tests\`
- Ensure all tests pass before creating PR

**Local Testing**:
```powershell
# Run all tests
Invoke-Pester .\Tests\

# Run with detailed output (matches CI verbosity)
Invoke-Pester .\Tests\ -Output Detailed

# Run specific test file
Invoke-Pester .\Tests\DefectDojo.Tests.ps1

# Run with code coverage
Invoke-Pester .\Tests\ -CodeCoverage .\modules\*.ps1
```

**Troubleshooting CI Failures**:
- Check workflow logs in PR "Checks" tab
- Download `test-results.xml` artifact for detailed failure information
- Reproduce locally using same test commands
- Ensure all mocks and environment variable preservation patterns correct

## Testing

The project maintains comprehensive test coverage with Pester 5+ test suite following consistent patterns for test isolation and environment preservation.

### Test Suite Overview

| Test File | Coverage | Key Features |
|-----------|----------|--------------|
| `Config.Tests.ps1` | Configuration loading/validation | Tests config file loading, template fallback, validation logic |
| `DefectDojo.Tests.ps1` | DefectDojo API integration | Unit tests with mocked API responses, integration tests for product/engagement/test retrieval |
| `EnvValidator.Tests.ps1` | Environment variable validation | Tests user prompts, API key input, environment variable setting across scopes |
| `GitHub.Tests.ps1` | GitHub Advanced Security | Tests repository filtering, CodeQL download, Secret Scanning, Dependabot |
| `Logging.Tests.ps1` | Logging framework | Tests log initialization, file creation, log entry writing |
| `TenableWAS.Tests.ps1` | Tenable WAS scan exports | Unit tests for error handling, integration tests for report generation |
| `BurpSuite.Tests.ps1` | BurpSuite XML processing | Tests folder scanning, file discovery, upload workflow |
| `Notifications.Tests.ps1` | Webhook notifications | Tests notification sending, payload formatting |
| `AutomationWorkflows.Tests.ps1` | Workflow orchestration | Tests workflow execution, error handling, config passing |

### Running Tests Locally

**All Tests**:
```powershell
Invoke-Pester .\Tests\
```

**Specific Test File**:
```powershell
Invoke-Pester .\Tests\DefectDojo.Tests.ps1
```

**With Detailed Output**:
```powershell
Invoke-Pester .\Tests\ -Output Detailed
```




## Troubleshooting

### Common Issues

**Issue**: PowerShell version mismatch  
**Solution**: Install PowerShell 7.2+ via Winget or from https://aka.ms/pscore

**Issue**: Environment variables not found  
**Solution**: The tool will prompt for missing variables. Alternatively, set manually and restart PowerShell.

**Issue**: API authentication failures  
**Solution**: Verify API keys are correct and have required permissions. Check DefectDojo user permissions include test creation/import rights.

**Issue**: TenableWAS scan list empty  
**Solution**: Ensure scans have completed at least once (`last_scan.scan_id` must exist). Check API credentials have read access to scans.

**Issue**: GitHub repositories not appearing  
**Solution**: Verify PAT has `repo` and `security_events` scopes. Check organization membership and repository access. Review filtering rules (`IncludeRepos`, `ExcludeRepos`).

**Issue**: DefectDojo CLI button shows error  
**Solution**: Ensure `DOJO_API_KEY` environment variable is set. Verify `modules\defectdojo-cli.exe` exists.

**Issue**: SonarQube integration fails  
**Solution**: Create Product API Scan Configuration in DefectDojo first (Product → Settings → API Scan Configurations). Verify SonarQube credentials in configuration.

### Log Files

All operations logged to timestamped files in `logs\` directory:

- **GUI Mode**: `logs\DDAutomationLauncher_Renewed.log`
- **CLI Mode**: `logs\DDAutomation_CLI.log`

Log entries include timestamp, level (INFO/WARNING/ERROR), and detailed messages for troubleshooting.


## Roadmap


### Future Enhancements

**Near-Term**:
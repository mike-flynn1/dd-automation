 # DefectDojo Automation Script Collection

 ## Overview
 This PowerShell-based toolset automates the export and import of security findings between various tools:
 - Tenable WAS → Defect Dojo
 - SonarQube → Defect Dojo (reimport direct from Defect Dojo)
 - GitHub CodeQL SARIF reports → Defect Dojo (Implemented)
 - GitHub Secret Scanning JSON → Defect Dojo (Implemented)
 - GitHub Dependabot → Defect Dojo (not Implemented)
 - Burp Suite XML report parsing → Defect Dojo (not Implemented)

 The solution is modular, extensible, and designed for easy addition of new tools.

 ## Prerequisites
 - Windows 10 or 11
 - PowerShell 7.2 or later
 - Network access to APIs (Defect Dojo, Tenable WAS)
 - Environment variables set for API keys and credentials
 - Pester >5.0 if running tests (DOES NOT CURRENTLY WORK, blocked by AV)
 - Tool Knowledge 


 ## Installation
 1. Clone this repository to your local machine.
 2. Ensure you have set the following environment variables:
- `DOJO_API_KEY` for Defect Dojo
- `TENWAS_ACCESS_KEY` for Tenable WAS (Access Key)
- `TENWAS_SECRET_KEY` for Tenable WAS (Secret Key)
- `GITHUB_PAT` for GitHub repos 
 3.Create a custom `config\yourconfig.psd1` file with tool-specific settings / URLs.

 ## Configuration
 ### Environment Variables
 | Variable            | Description                    |
 |---------------------|--------------------------------|
 | DOJO_API_KEY        | API key for Defect Dojo        |
 | TENWAS_API_KEY      | API access key for Tenable WAS |
 | TENWAS_API_SECRET   | API secret key for Tenable WAS |
 | GITHUB_PAT          | API Key for GitHub             |

 ## Config File
 Manual Inputs: 
     - Scan ID for Tenable WAS scan (Add where can be found) (possible future feature add to grab this from scan list)
     - Burp Scan #? to export from API?

 ### PowerShell Config
 An example configuration file is provided at `config/config.psd1.example`. Copy it to `config\\config.psd1` and update the values as needed. This file is ignored by Git, allowing personal overrides. 
 
## Folder Structure
 ```
 ├── config/         # User-specific config PSD1 files
 ├── logs/           # Timestamped log files
 ├── modules/        # Individual function .ps1 files
 ├── Examples/       # Example input files (ignored by Git)
 ├── Tests/          # Test files (CURRENTLY NONFUNCTIONAL)
 ├── .gitignore
 └── README.md       # Project documentation
```

## Usage

 1. Set appropriate values in your personal config.psd1
 2. Open PowerShell with appropriate execution policy.
 3. Launch the script using .\Launch.ps1
 4. A GUI prompt will launch to select tools and input files/folders.
 5. All checkboxes have tooltips to display their functionality. 
 6. Press Go.
 7. Monitor progress in the console and GUI; detailed logs are written to `logs/DDAutomationLauncher.log`.

## Tenable WAS Integration

The Tenable WAS (Web Application Scanning) integration exports vulnerability scan results from Tenable's cloud-based platform and optionally uploads them to DefectDojo for centralized vulnerability management.

### Features
- **Automated Report Generation**: Initiates report generation via Tenable WAS API for a specified scan
- **CSV Export**: Downloads scan results in CSV format suitable for DefectDojo import
- **Direct DefectDojo Upload**: Automatically uploads exported scan reports to a designated DefectDojo test when DefectDojo integration is enabled
- **Configurable Scan Selection**: Supports scan ID specification via GUI input or configuration file

### How It Works
1. When the Tenable WAS checkbox is selected in the GUI, the user must provide a Scan ID from the Tenable WAS website (GUID format)
2. The tool makes a two-step API request to Tenable WAS:
   - **PUT request** to `/was/v2/scans/{scanId}/report` to initiate report generation
   - **GET request** to the same endpoint (after 2-second delay) to download the generated CSV report
3. The CSV file is temporarily saved to the system temp directory with naming convention: `{scanId}-report.csv`
4. If the DefectDojo checkbox is also selected:
   - The tool uploads the CSV report to the specifically selected Tenable WAS test in DefectDojo
   - Uses the "Tenable Scan" scan type for proper parsing by DefectDojo
   - Upload is performed via DefectDojo's `/reimport-scan/` endpoint

### Configuration
**Environment Variables** (Required):
- `TENWAS_ACCESS_KEY`: Your Tenable WAS API access key
- `TENWAS_SECRET_KEY`: Your Tenable WAS API secret key
- `DOJO_API_KEY`: DefectDojo API token (only required if uploading to DefectDojo)

**Config File** (`config/config.psd1`):
```powershell
ApiBaseUrls = @{
    TenableWAS = 'https://fedcloud.tenable.com/'  # Tenable cloud endpoint
}

TenableWASScanId = '0a514d9e-7e2f-4bd5-9e22-e5044e94bc77'  # Optional: Default scan ID

DefectDojo = @{
    TenableWASTestId = 123  # Optional: Pre-selected test ID for uploads
}
```

**GUI Inputs**:
- **Tenable WAS Scan ID**: Required field in the GUI to specify which scan to export
- **DD Test (Tenable WAS)**: Dropdown to select the specific DefectDojo test for upload (populated from selected engagement)

### File Locations
- **Exported Reports**: `%TEMP%\{scanId}-report.csv` (Windows temporary directory)
- **API Endpoint**: `https://fedcloud.tenable.com/was/v2/scans/{scanId}/report`

### Finding Scan IDs
Tenable WAS Scan IDs can be found in the Tenable.io web interface:
1. Navigate to Tenable.io > Web Application Scanning
2. Select your scan from the list
3. The Scan ID (GUID format) appears in the URL

### Limitations
- Only exports completed scans (cannot export in-progress scans)
- Scan ID must be manually specified for each export (no automatic scan list retrieval yet)

## SonarQube Integration

The SonarQube integration leverages DefectDojo's built-in SonarQube API Import feature to directly import code quality and security findings from SonarQube without manual file downloads. This integration uses DefectDojo's Product API Scan Configuration system.

### Features
- **API-based Import**: Uses DefectDojo's native "SonarQube API Import" scan type for direct API integration
- **No File Downloads Required**: Bypasses manual export/import workflow by using DefectDojo's API scan configuration
- **Re-import Support**: Updates existing test results with latest SonarQube findings via DefectDojo's `/reimport-scan/` endpoint
- **Configurable Severity Filtering**: Honors minimum severity settings from configuration

### How It Works
1. **Pre-requisite**: A Product API Scan Configuration must be created in DefectDojo first
   - In DefectDojo UI: Product > Settings > API Scan Configurations
   - Configure with SonarQube project key, API token, and endpoint URL
   - The tool retrieves available configurations via `/product_api_scan_configurations/` endpoint
2. When the SonarQube checkbox is selected in the GUI:
   - User selects a pre-configured API Scan Configuration from the dropdown (shows SonarQube project keys)
   - User selects the target DefectDojo test for import
3. The tool posts to DefectDojo's `/reimport-scan/` endpoint with:
   - `scan_type`: "SonarQube API Import"
   - `api_scan_configuration`: The selected configuration ID
   - `test`: The target test ID
   - `minimum_severity`: From configuration (default: "Low")
4. DefectDojo handles the SonarQube API communication and finding import internally

### Configuration
**Environment Variables** (Required):
- `DOJO_API_KEY`: DefectDojo API token with permissions to reimport scans

**Config File** (`config/config.psd1`):
```powershell
ApiBaseUrls = @{
    DefectDojo = 'https://defect-dojo.internal.example.com/api/v2'
}

DefectDojo = @{
    MinimumSeverity = 'Low'  # Minimum severity for imported findings
    APIScanConfigId = 1      # Optional: Pre-selected API scan configuration ID
    SonarQubeTestId = 456    # Optional: Pre-selected test ID for imports
}
```

**DefectDojo Setup** (Required before first use):
1. In DefectDojo, navigate to the target Product
2. Go to Settings > Product API Scan Configurations
3. Create a new configuration with:
   - **Tool Configuration Name**: Descriptive name
   - **Tool Type**: SonarQube
   - **Service Key 1**: SonarQube project key (e.g., "my-project-key")
   - **API Key**: SonarQube user token with project access
   - **Additional Fields**: SonarQube server URL if required

**GUI Inputs**:
- **DD API Scan Configuration**: Dropdown showing available SonarQube configurations
- **DD Test (SonarQube)**: Dropdown to select the specific DefectDojo test for import (populated from selected engagement)

### Technical Notes
- This integration does NOT use the `Sonarqube.ps1` module to call SonarQube APIs directly
- Instead, it uses the `Invoke-SonarQubeProcessing` function which delegates API communication to DefectDojo
- DefectDojo's API Scan Configuration stores SonarQube credentials securely server-side
- The tool only orchestrates the reimport request; DefectDojo handles authentication and data retrieval

### Advantages Over Manual Export
- **No credential management**: SonarQube API tokens stored securely in DefectDojo
- **No file handling**: Eliminates download/upload workflow and temporary file storage
- **Automatic updates**: Re-import updates existing findings rather than creating duplicates
- **Built-in parsing**: Uses DefectDojo's native SonarQube parser for reliable result processing

### Limitations
- API Scan Configuration must be pre-configured in DefectDojo before using this tool
- Cannot selectively filter findings before import (all findings for the configured project are imported based on severity threshold)

## GitHub Integration

The GitHub integration automatically downloads and processes security findings from GitHub Advanced Security features:

### Features
- **CodeQL SARIF Reports**: Downloads the latest CodeQL code scanning analyses for all repositories in configured organizations
- **Secret Scanning JSON**: Downloads open secret scanning alerts for all repositories with Secret Scanning enabled

### How It Works
1. When the GitHub checkbox is selected in the GUI, the tool iterates through all repositories in the configured GitHub organization(s)
2. For each repository:
   - Downloads the latest CodeQL SARIF report (if CodeQL is enabled and has results)
   - Downloads open Secret Scanning alerts as JSON (if Secret Scanning is enabled)
3. Creates separate DefectDojo tests for each scan type with naming convention:
   - CodeQL tests: `repository-name (CodeQL)`
   - Secret Scanning tests: `repository-name (Secret Scanning)`
4. Files are temporarily stored in system temp directories before upload:
   - CodeQL: `%TEMP%\GitHubCodeScanning\`
   - Secret Scanning: `%TEMP%\GitHubSecretScanning\`

### Configuration
- Set the `GITHUB_PAT` environment variable with a Personal Access Token that has access to all configured organizations
- Configure organization names in `config/config.psd1` under the `GitHub.org` property (array of strings for multiple orgs)
- The tool automatically handles repositories without Advanced Security enabled by logging warnings and skipping

### Limitations
- Dependabot integration is not yet implemented (May implement via Dependabot integration with DD)
- Only processes the latest analysis per CodeQL category
- Only retrieves open secret scanning alerts (not resolved/closed)
- Requires GitHub Advanced Security features to be enabled on target repositories

## Modules

 | Module        | Status  | Description                                        |
 |---------------|---------|----------------------------------------------------|
 | Config        | Done    | Load and validate configuration                    |
 | Logging       | Done    | Logging framework (Initialize-Log, Write-Log)      |
 | EnvValidator  | Done    | Validate required environment variables            |
 | TenableWAS    | Done    | Export findings from Tenable WAS                   |
 | SonarQube     | Done    | Fetch issues via SonarQube API - or use existing DD Integration                    |
 | BurpSuite     | Pending | Retrieve Burp XML reports via Local API            |
 | GitHub        | Done    | Download GitHub CodeQL SARIF and Secret Scanning JSON for all repos in configured organizations |
 | DefectDojo    | Done    | Fetch and list products, engagements, tests, and product API scan configurations via API       |
 | Local Copy    | Pending | Copy all local docs to proper share                |
 | Uploader      | Done    | Upload all files to DD via API                     |

 ## Roadmap / Next Steps
 1. Implement core function scaffolds in `modules/`.
 2. Implement individual tool functions and test.
 3. Update this README.md after each development step.

 ###
 - Current tasks:
 - Future:
   - Implement GitHub Dependabot integration
   - Revisit BurpSuite folder picker necessity based on Burp module
   - Reupload burp scan given directory (or use external tooling)
   - Revisit local file uploads via command line tool use

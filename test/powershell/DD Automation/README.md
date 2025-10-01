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
- `TENWAS_API_KEY` for Tenable WAS (Access Key)
- `TENWAS_API_SECRET` for Tenable WAS (Secret Key)
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

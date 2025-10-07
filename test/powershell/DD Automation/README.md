 # DefectDojo Automation Script Collection

 ## Overview
 This PowerShell-based toolset automates the export and import of security findings between various tools:
 - Tenable WAS → Defect Dojo
 - SonarQube → Defect Dojo (reimport direct from Defect Dojo)
 - Burp Suite XML report parsing → Defect Dojo (not Implemented)
 - GitHub CodeQL, Secret Scanning, DependaBot → Defect Dojo (not Implemented)

 The solution is modular, extensible, and designed for easy addition of new tools (e.g., GitHub).

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
 | DOJO_API_KEY        | API key for Defect Dojo (automatically synced to DD_CLI_API_TOKEN when launching CLI) |
 | TENWAS_API_KEY      | API access key for Tenable WAS |
 | TENWAS_API_SECRET   | API secret key for Tenable WAS |
 | GITHUB_PAT          | API Key for GitHub             |
 | DD_CLI_API_TOKEN    | DefectDojo CLI token (auto-created from DOJO_API_KEY, do not set manually) |

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

### Manual Upload (DefectDojo CLI)

This feature allows you to launch the DefectDojo CLI tool in interactive mode for manual uploads that don't conform to the standard automation template.

**Purpose**: Enables manual uploads for specialized scenarios or custom file formats not handled by the automated workflows.

**Prerequisites**:
- `DOJO_API_KEY` environment variable must be set
- The CLI executable must exist at `modules\defectdojo-cli.exe`

**How to use**:
1. Click the "Launch DefectDojo CLI" button in the GUI
2. Use the window that opens the interactive DefectDojo CLI interface for your upload needs
3. The console window remains open after you complete your operations

**Behavior**:
- **API Token Synchronization**: Your `DOJO_API_KEY` is automatically synchronized to `DD_CLI_API_TOKEN` as a persistent user-level environment variable. This ensures the DefectDojo CLI can authenticate without additional configuration.
- **Interactive Mode**: The CLI launches in interactive mode, providing a menu-driven interface for manual operations
- **PowerShell 7**: The CLI is launched in a new PowerShell 7 (`pwsh.exe`) window with `-NoExit` flag to keep the console open
- **Working Directory**: The CLI runs from the `modules\` directory
- Independent of the main automation workflow

**Troubleshooting**:
- If clicking the button shows an error dialog, ensure:
  - `DOJO_API_KEY` is set in your environment variables
  - The EXE is present at `modules\defectdojo-cli.exe`
- Check the status log in the GUI and `logs/DDAutomationLauncher_Renewed.log` for detailed error messages


## Modules

 | Module        | Status  | Description                                        |
 |---------------|---------|----------------------------------------------------|
 | Config        | Done    | Load and validate configuration                    |
 | Logging       | Done    | Logging framework (Initialize-Log, Write-Log)      |
 | EnvValidator  | Done    | Validate required environment variables            |
 | TenableWAS    | Done    | Export findings from Tenable WAS                   |
 | SonarQube     | Done    | Fetch issues via SonarQube API - or use existing DD Integration                    |
 | BurpSuite     | Pending | Retrieve Burp XML reports via Local API            |
 | GitHub        | Work IP | Download all GH scan files for all repos (based on key) | 
 | DefectDojo    | Done    | Fetch and list products, engagements, tests, and product API scan configurations via API       |
 | Local Copy    | Pending | Copy all local docs to proper share                |
 | Uploader      | Done    | Upload all files to DD via API                     |

 ## Roadmap / Next Steps
 1. Implement core function scaffolds in `modules/`.
 2. Implement individual tool functions and test.
 3. Update this README.md after each development step.

 ### 
 - Current tasks: 
 - Future: guide user through adding env variables to user $PATH, revisit burpsuite folder picker neccessity based on Burp module, reupload burp scan given directory (or use DefectDojo CLIing), revisit secret scanning when DD Pro is up.

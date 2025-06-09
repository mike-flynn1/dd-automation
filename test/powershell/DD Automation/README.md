 # DefectDojo Automation Script Collection

 ## Overview
 This PowerShell-based toolset automates the export and import of security findings between various tools:
 - Tenable WAS → Defect Dojo
 - SonarQube → Defect Dojo
 - Burp Suite XML report parsing → Defect Dojo

 The solution is modular, extensible, and designed for easy addition of new tools (e.g., GitHub).

 ## Prerequisites
 - Windows 10 or 11
 - PowerShell 5.1 or later
 - Network access to APIs (Defect Dojo, Tenable WAS, SonarQube)
 - Environment variables set for API keys and credentials
 - Pester >5.0 if running tests (DOES NOT CURRENTLY WORK, blocked by AV)
 - Tool Knowledge 


 ## Installation
 1. Clone this repository to your local machine.
 2. Ensure you have set the following environment variables:
- `DOJO_API_KEY` for Defect Dojo
- `TENWAS_API_KEY` for Tenable WAS (Access Key)
- `TENWAS_API_SECRET` for Tenable WAS (Secret Key)
- `SONARQUBE_API_TOKEN` for SonarQube
 3.Create a custom `config\yourconfig.psd1` file with tool-specific settings / URLs.

 ## Configuration
 ### Environment Variables
 | Variable            | Description                    |
 |---------------------|--------------------------------|
 | DOJO_API_KEY        | API key for Defect Dojo        |
 | TENWAS_API_KEY      | API access key for Tenable WAS |
 | TENWAS_API_SECRET   | API secret key for Tenable WAS |
 | SONARQUBE_API_TOKEN | API token for SonarQube        |

 ## Config File
 Manual Inputs: 
     - Scan ID for Tenable WAS scan (Add where can be found) (possible future feature add to grab this from scan list)
     - Burp Scan #? to export from API?
     - DefectDojo Product + Engagment + Test integers to fill in config files (possible future feature to ask user if not set + grab from API)

 ### PowerShell Config
 An example configuration file is provided at `config/config.psd1.example`. Copy it to `config\\config.psd1` and update the values as needed. This file is ignored by Git, allowing personal overrides. 
 
## Folder Structure
 ```
 ├── config/         # User-specific config PSd1 files
 ├── logs/           # Timestamped log files
 ├── modules/        # Individual function .ps1 files
 ├── Examples/       # Example input files (ignored by Git)
 ├── Tests/          # Test files (CURRENTLY NONFUNCTIONAL)
 ├── .gitignore
 └── README.md       # Project documentation
```

## Usage

 1. Open PowerShell with appropriate execution policy.
 2. Launch the script using .\Launch.ps1
 3. A GUI prompt will launch to select tools and input files/folders.
 4. Monitor progress in the console and GUI; detailed logs are written to `logs/`.


## Modules

 | Module        | Status  | Description                                        |
 |---------------|---------|----------------------------------------------------|
 | Config        | Done    | Load and validate configuration                    |
 | Logging       | Done    | Logging framework (Initialize-Log, Write-Log)      |
 | EnvValidator  | Done    | Validate required environment variables            |
 | TenableWAS    | Done    | Export findings from Tenable WAS                   |
 | SonarQube     | Pending | Fetch issues via SonarQube API - or use existing DD Integration                    |
 | BurpSuite     | Pending | Retrieve Burp XML reports via Local API            |
 | DefectDojo    | Done    | Fetch and list products, engagements, and tests via API       |
 | Local Copy    | Pending | Copy all local docs to proper share                |
 | Uploader      | Work IP | Upload all files to DD via API                     |

 ## Roadmap / Next Steps
 1. Implement core function scaffolds in `modules/`.
 2. Implement individual tool functions and test.
 3. Update this README.md after each development step.

 ###
 - Current tasks: scaffold updater starting with Tenable WAS., fix save-config function
 - Future: Remove debug mode (doing in local ps1 files), clean up log file logic, revisit burpsuite folder picker neccessity based on Burp module, refactor Tenable module to be a dropdown of scans like DD, test file for uploader.ps1 when finished
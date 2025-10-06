 # DefectDojo Automation Script Collection

 ## Overview
 This PowerShell-based toolset automates the export and import of security findings between various tools:
 - Tenable WAS → Defect Dojo
 - SonarQube → Defect Dojo (reimport direct from Defect Dojo)
 - Burp Suite XML report parsing → Defect Dojo (not Implemented)
 - GitHub CodeQL, Secret Scanning, DependaBot → Defect Dojo (not Implemented)

 The solution is modular, extensible, and designed for easy addition of new tools (e.g., GitHub).

 Detailed help article in the Cyber Engineering Wiki [here](https://bamtech.visualstudio.com/BAM-IT/_wiki/wikis/BAM-IT.wiki/2729/DefectDojo-PowerShell-Tool-Overview). 

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
An example configuration file is provided at `config/config.psd1.example`. Copy it to `config\config.psd1` and update the values as needed. This file is ignored by Git, allowing personal overrides. 

### GitHub Configuration
- Populate `GitHub = @{ Orgs = @('your-org-1','your-org-2') }` in your config file.
- Supply one organization for single-tenant use or add multiple entries to process each org sequentially when `GitHub` is selected in the GUI.
- Ensure `GITHUB_PAT` has access to every listed organization (CodeQL/Secret Scanning permissions as required).
- The launcher exposes a `GitHub Orgs` textbox populated from the config; update the comma-separated list there to override and persist organizations without editing the PSD1 manually.

#### Repository Filtering
The GitHub integration supports flexible repository filtering to control which repositories are processed:

**Skip Archived Repositories** (default: enabled)
```powershell
GitHub = @{
    SkipArchivedRepos = $true  # Skip archived repos (default: true)
}
```

**Include-Only Filter** (whitelist)
When specified, ONLY repositories matching these patterns will be processed:
```powershell
GitHub = @{
    IncludeRepos = @(
        'production-*'     # All repos starting with 'production-'
        'critical-app'     # Exact match
        '*-api'            # All repos ending with '-api'
        '*security*'       # Any repo containing 'security'
    )
}
```

**Exclude Filter** (blacklist)
Repositories matching these patterns will be skipped (applied after include filter):
```powershell
GitHub = @{
    ExcludeRepos = @(
        'test-*'           # Skip all test repos
        '*-demo'           # Skip all demo repos
        'archived-*'       # Skip repos starting with 'archived-'
        'old-legacy-app'   # Skip specific repo
    )
}
```

**Pattern Matching:**
- Supports PowerShell wildcards: `*` (matches any characters), `?` (matches single character)
- Patterns are case-insensitive
- Examples:
  - `production-*` matches: `production-app`, `production-api`, `production-web`
  - `*-test` matches: `myapp-test`, `api-test`, `frontend-test`
  - `*security*` matches: `security-tools`, `app-security`, `security`

**Filter Order:**
1. Skip archived repos (if enabled)
2. Apply include filter (if specified)
3. Apply exclude filter (if specified)

**Logging:**
All filtering decisions are logged to `logs/DDAutomationLauncher_Renewed.log` for transparency, showing which repos were skipped and why.

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


## Modules

 | Module        | Status  | Description                                        |
 |---------------|---------|----------------------------------------------------|
 | Config        | Done    | Load and validate configuration                    |
 | Logging       | Done    | Logging framework (Initialize-Log, Write-Log)      |
 | EnvValidator  | Done    | Validate required environment variables            |
 | TenableWAS    | Done    | Export findings from Tenable WAS                   |
 | SonarQube     | Done    | Fetch issues via SonarQube API - or use existing DD Integration                    |
 | BurpSuite     | Pending | Retrieve Burp XML reports via Local API            |
 | GitHub        | Work IP | Download GitHub scans for every org configured in `GitHub.Orgs`. These scans will eventually include CodeQL (Done), Secret Scanning (Work IP), and Dependabot (TODO) | 
 | DefectDojo    | Done    | Fetch and list products, engagements, tests, and product API scan configurations via API       |
 | Local Copy    | Pending | Copy all local docs to proper share                |
 | Uploader      | Done    | Upload all files to DD via API                     |

 ## Roadmap / Next Steps
 1. Update individual tool functionality as new tools are added / tweaked. 
 2. Update this README.md after each development step.

 ### 
 - Current tasks: 
 - Future: guide user through adding env variables to user $PATH, revisit burpsuite folder picker neccessity based on Burp module, reupload burp scan given directory (or use external tooling), revisit secret scanning when DD Pro is up.

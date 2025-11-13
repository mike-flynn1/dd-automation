# DD-Automation Prompt Templates

This directory contains prompt templates for generating security reports using DefectDojo MCP server data.

## Available Templates

- **cybersecurity-vulnerability-report** - Generates executive vulnerability reports from DefectDojo

## How to Use

### Quick Example

Copy and paste this into the VS Code chat:

```
Use the cybersecurity-vulnerability-report template to generate a report for today's date
```

### Template Format

```
Use the [template-name] template to generate a report for [date/timeframe]
```

## What Happens Automatically

When you use a template, the AI will:

1. **Connect to DefectDojo** - Pull current vulnerability data
2. **Filter Data** - Get findings for SBIR DTK and OnePASS products
3. **Calculate Metrics** - Count vulnerabilities by severity and timeframes
4. **Generate Report** - Create a professional HTML report

## Data Sources

The templates automatically pull from DefectDojo:

| Data Type | What It Gets | Used For |
|-----------|--------------|----------|
| Findings | Active vulnerabilities by severity | CAT I/II/III counts |
| Time Filters | Recent findings (30/180 days) | Trending analysis |
| Products | Repository and asset data | Asset discovery metrics |
| Metadata | Project information | Report context |

## Output

The AI will generate a professional HTML report with current DefectDojo data that you can save and share.

## Tips

- Just specify the template name and date
- The AI handles all data collection automatically
- No manual data entry required
- Reports always use live DefectDojo data
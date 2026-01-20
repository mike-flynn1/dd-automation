# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Power Automate webhook integration with Adaptive Card support for scheduled automation notifications
- NonInteractive parameter to `Validate-Environment` for headless CLI execution
- Notifications section preservation in `Save-Config` function (WebhookUrl and WebhookType)
- Comprehensive test coverage for notification system (9 tests)
- Test coverage for NonInteractive environment validation (4 tests)

### Changed
- Webhook system refactored to support PowerAutomate (default) and Teams formats
- Webhook payload now uses Adaptive Card schema v1.4 for Power Automate compatibility
- Removed Slack webhook support (not needed)
- Updated README with Power Automate documentation and webhook configuration examples

### Fixed
- Fixed `-NonInteractive` parameter bug in Run-Automation.ps1 (parameter did not exist in Validate-Environment)
- Fixed Power Automate webhook error: "the result of the evaluation of 'foreach' expression '@triggerOutputs()?['body']?['attachments']' is of type 'Null'"
- Config file now properly preserves Notifications section when saving GUI selections

## [1.1.0] - 2025-12-24

### Added
- Initial changelog creation.
- GitHub Dependabot integration features.

### Changed
- Updated `config.psd1` structure to support nested GitHub tools settings.

### Fixed
- Various bug fixes including getting all repos instead of maxing out at 100 from GitHub.

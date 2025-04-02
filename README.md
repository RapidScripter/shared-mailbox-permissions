# Microsoft 365 Shared Mailbox Permission Report

![PowerShell](https://img.shields.io/badge/PowerShell-%235391FE.svg?style=for-the-badge&logo=powershell&logoColor=white)
![Microsoft Exchange](https://img.shields.io/badge/Microsoft_Exchange-0078D4?style=for-the-badge&logo=microsoft-exchange&logoColor=white)

A PowerShell script to audit and report on shared mailbox permissions in Microsoft 365/Exchange Online.

## Features

- 🔍 **Comprehensive Permission Reporting**:
  - Full Access permissions
  - Send As permissions
  - Send On Behalf permissions
- 🔐 **Multiple Authentication Methods**:
  - Interactive login (MFA supported)
  - Device code flow for non-interactive sessions
  - Basic authentication for automation
- 📊 **Flexible Filtering**:
  - Report on all shared mailboxes or specific mailboxes
  - Filter by permission type
- 📁 **CSV Export**:
  - Clean, formatted output
  - Automatic file opening option

## Prerequisites

- PowerShell 5.1 or later
- Exchange Online PowerShell V2 module
- Appropriate admin permissions in Exchange Online

## Installation

1. Clone the repository:
   ```powershell
   git clone https://github.com/RapidScripter/shared-mailbox-permissions.git
   cd shared-mailbox-permissions
   ```

2. Install the required module:
   ```powershell
   Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
   ```

## Usage

### Basic Commands

```powershell
# Interactive MFA authentication (shows all permissions)
.\GetSharedMailboxPermissions.ps1 -MFA

# Device code flow (for VS Code/automation)
.\GetSharedMailboxPermissions.ps1 -MFA -DeviceAuth

# Report only Full Access permissions
.\GetSharedMailboxPermissions.ps1 -FullAccess

# Report specific permission types
.\GetSharedMailboxPermissions.ps1 -FullAccess -SendAs
```

### Advanced Options

| Parameter          | Description                          | Example                          |
|--------------------|--------------------------------------|----------------------------------|
| `-MBNamesFile`     | Path to CSV with specific mailboxes  | `-MBNamesFile .\mailboxes.csv`   |
| `-UserName`        | Admin username for automation        | `-UserName admin@domain.com`     |
| `-Password`        | Password for automation              | `-Password "yourpassword"`       |
| `-OutputPath`      | Custom output directory              | `-OutputPath "C:\Reports"`       |

### Input File Format

For `-MBNamesFile`, create a CSV with one column header "Identity":
```
Identity
shared1@domain.com
shared2@domain.com
shared3@domain.com
```

## Output

The script generates a CSV report with these columns:

- **Display Name**: Mailbox display name
- **User Principal Name**: Mailbox UPN
- **Primary SMTP Address**: Primary email address
- **Access Type**: Permission type (FullAccess/SendAs/SendOnBehalf)
- **User With Access**: User/group with permission
- **Email Aliases**: All email aliases
- **Permission Source**: How permission was granted

Sample output filename: `SharedMBPermissionReport_2023-08-15_143022.csv`

## Example Output

| Display Name | User Principal Name | Primary SMTP Address | Access Type | User With Access | Email Aliases | Permission Source |
|--------------|---------------------|-----------------------|-------------|------------------|---------------|-------------------|
| Finance Team | finance@domain.com | finance@domain.com | FullAccess | jane.doe@domain.com | finance-team@domain.com | Direct |
| HR Shared | hr@domain.com | hr@domain.com | SendAs | john.smith@domain.com | hr-team@domain.com | Direct |

## Troubleshooting

| Error/Symptom | Solution |
|--------------|----------|
| "Window handle must be configured" | Use `-DeviceAuth` parameter |
| "Cannot connect to Exchange Online" | Verify admin permissions |
| "No shared mailboxes found" | Check your filters |
| Slow performance | Process fewer mailboxes at once |

## Best Practices

1. **Regular Audits**: Run monthly to detect permission creep
2. **Least Privilege**: Review unnecessary permissions
3. **Documentation**: Keep reports for compliance
4. **Automation**: Schedule with certificate auth

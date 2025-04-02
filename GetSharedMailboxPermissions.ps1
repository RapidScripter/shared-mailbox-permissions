<#
=============================================================================================
Name:           Get Shared Mailbox Permission Report 
Version:        3.0
Description:    Generates comprehensive reports of shared mailbox permissions in Exchange Online
============================================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$MFA,
    
    [Parameter(Mandatory = $false)]
    [switch]$DeviceAuth,
    
    [Parameter(Mandatory = $false)]
    [switch]$FullAccess,
    
    [Parameter(Mandatory = $false)]
    [switch]$SendAs,
    
    [Parameter(Mandatory = $false)]
    [switch]$SendOnBehalf,
    
    [Parameter(Mandatory = $false)]
    [string]$MBNamesFile,
    
    [Parameter(Mandatory = $false)]
    [string]$UserName,
    
    [Parameter(Mandatory = $false)]
    [string]$Password,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "."
)

Begin {
    # Initialize variables
    $ErrorActionPreference = "Stop"
    $ScriptStartTime = Get-Date
    $ExportCSV = Join-Path $OutputPath "SharedMBPermissionReport_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
    $Results = @()
    $ProcessedCount = 0
    $FilterPresent = $FullAccess.IsPresent -or $SendAs.IsPresent -or $SendOnBehalf.IsPresent

    # Cleanup function
    function Cleanup {
        try {
            Write-Host "Disconnecting Exchange Online session..." -ForegroundColor Cyan
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            Write-Warning "Error disconnecting from Exchange Online: $_"
        }
    }

    # Function to resolve DN to UPN
    function Resolve-DNtoUPN {
        param([string]$DistinguishedName)
        try {
            $mailbox = Get-Mailbox -Identity $DistinguishedName -ErrorAction Stop
            return $mailbox.UserPrincipalName
        }
        catch {
            Write-Warning "Could not resolve $DistinguishedName to UPN"
            return $DistinguishedName
        }
    }
}

Process {
    try {
        # Check and install EXO module if needed
        if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
            Write-Host "Exchange Online PowerShell V2 module is not available" -ForegroundColor Yellow
            $Confirm = Read-Host "Do you want to install the module? [Y] Yes [N] No"
            
            if ($Confirm -match "[yY]") {
                Write-Host "Installing Exchange Online PowerShell module..." -ForegroundColor Cyan
                Install-Module ExchangeOnlineManagement -Repository PSGallery -AllowClobber -Force -Scope CurrentUser
                Import-Module ExchangeOnlineManagement -Force
            }
            else {
                Write-Host "EXO V2 module is required. Please install using: Install-Module ExchangeOnlineManagement" -ForegroundColor Red
                exit 1
            }
        }

        # Connect to Exchange Online
        Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
        
        if ($DeviceAuth -or ($MFA -and -not [Environment]::UserInteractive)) {
            Write-Host "Using device code authentication..." -ForegroundColor Cyan
            Connect-ExchangeOnline -Device -ShowBanner:$false -ErrorAction Stop
        }
        elseif ($MFA) {
            Write-Host "Using interactive authentication..." -ForegroundColor Cyan
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        }
        elseif ($UserName -and $Password) {
            $SecuredPassword = ConvertTo-SecureString -AsPlainText $Password -Force
            $Credential = New-Object System.Management.Automation.PSCredential($UserName, $SecuredPassword)
            Connect-ExchangeOnline -Credential $Credential -ShowBanner:$false -ErrorAction Stop
        }
        else {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        }

        Write-Host "Connected successfully" -ForegroundColor Green

        # Get mailboxes to process
        $Mailboxes = @()
        
        if ($MBNamesFile -and (Test-Path $MBNamesFile)) {
            Write-Host "Processing mailboxes from input file..." -ForegroundColor Cyan
            $Mailboxes = Import-Csv -Header "Identity" $MBNamesFile | ForEach-Object { $_.Identity }
        }
        else {
            Write-Host "Retrieving all shared mailboxes..." -ForegroundColor Cyan
            $Mailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited | Select-Object -ExpandProperty UserPrincipalName
        }

        $TotalMailboxes = $Mailboxes.Count
        if ($TotalMailboxes -eq 0) {
            Write-Host "No shared mailboxes found matching the specified criteria" -ForegroundColor Yellow
            return
        }

        Write-Host "Found $TotalMailboxes shared mailboxes to process" -ForegroundColor Cyan

        # Process each mailbox
        foreach ($UPN in $Mailboxes) {
            $ProcessedCount++
            Write-Progress -Activity "Processing shared mailboxes" -Status "$ProcessedCount of $TotalMailboxes" -CurrentOperation $UPN -PercentComplete (($ProcessedCount / $TotalMailboxes) * 100)

            try {
                $MBDetails = Get-Mailbox -Identity $UPN -ErrorAction Stop
                
                # Skip if not a shared mailbox (when using input file)
                if ($MBDetails.RecipientTypeDetails -ne "SharedMailbox") {
                    Write-Warning "$UPN is not a shared mailbox (Type: $($MBDetails.RecipientTypeDetails))"
                    continue
                }

                # Get email aliases
                $EmailAliases = ($MBDetails.EmailAddresses | Where-Object { $_ -clike "smtp:*" }) -replace "smtp:","" -join ","

                # Process Full Access permissions
                if (-not $FilterPresent -or $FullAccess) {
                    $FullAccessPermissions = (Get-MailboxPermission -Identity $UPN | 
                        Where-Object { 
                            $_.AccessRights -contains "FullAccess" -and 
                            $_.IsInherited -eq $false -and 
                            $_.User -notmatch "NT AUTHORITY|S-1-5-21"
                        }).User | Where-Object { $_ -ne $null }
                    
                    if ($FullAccessPermissions) {
                        foreach ($Permission in $FullAccessPermissions) {
                            $Results += [PSCustomObject]@{
                                'Display Name' = $MBDetails.DisplayName
                                'User Principal Name' = $UPN
                                'Primary SMTP Address' = $MBDetails.PrimarySmtpAddress
                                'Access Type' = 'FullAccess'
                                'User With Access' = $Permission
                                'Email Aliases' = $EmailAliases
                                'Permission Source' = 'Direct'
                            }
                        }
                    }
                }

                # Process SendAs permissions
                if (-not $FilterPresent -or $SendAs) {
                    $SendAsPermissions = (Get-RecipientPermission -Identity $UPN | 
                        Where-Object { 
                            $_.Trustee -notmatch "NT AUTHORITY|S-1-5-21" -and 
                            $_.AccessRights -contains "SendAs"
                        }).Trustee | Where-Object { $_ -ne $null }
                    
                    if ($SendAsPermissions) {
                        foreach ($Permission in $SendAsPermissions) {
                            $Results += [PSCustomObject]@{
                                'Display Name' = $MBDetails.DisplayName
                                'User Principal Name' = $UPN
                                'Primary SMTP Address' = $MBDetails.PrimarySmtpAddress
                                'Access Type' = 'SendAs'
                                'User With Access' = $Permission
                                'Email Aliases' = $EmailAliases
                                'Permission Source' = 'Direct'
                            }
                        }
                    }
                }

                # Process SendOnBehalf permissions
                if (-not $FilterPresent -or $SendOnBehalf) {
                    $SendOnBehalfPermissions = $MBDetails.GrantSendOnBehalfTo | Where-Object { $_ -ne $null }
                    
                    if ($SendOnBehalfPermissions) {
                        foreach ($PermissionDN in $SendOnBehalfPermissions) {
                            $PermissionUPN = Resolve-DNtoUPN $PermissionDN
                            $Results += [PSCustomObject]@{
                                'Display Name' = $MBDetails.DisplayName
                                'User Principal Name' = $UPN
                                'Primary SMTP Address' = $MBDetails.PrimarySmtpAddress
                                'Access Type' = 'SendOnBehalf'
                                'User With Access' = $PermissionUPN
                                'Email Aliases' = $EmailAliases
                                'Permission Source' = 'Direct'
                            }
                        }
                    }
                }
            }
            catch {
                Write-Warning "Error processing mailbox $UPN : $_"
                continue
            }
        }

        # Export results
        if ($Results.Count -gt 0) {
            $Results | Export-Csv -Path $ExportCSV -NoTypeInformation -Encoding UTF8
            Write-Host "`nReport generated successfully!" -ForegroundColor Green
            Write-Host "Processed $ProcessedCount shared mailboxes" -ForegroundColor Cyan
            Write-Host "Found $($Results.Count) permission entries" -ForegroundColor Cyan
            Write-Host "Output file: $ExportCSV" -ForegroundColor Yellow

            # Offer to open the file
            $OpenFile = Read-Host "Do you want to open the output file now? [Y] Yes [N] No"
            if ($OpenFile -match "[yY]") {
                Start-Process $ExportCSV
            }
        }
        else {
            Write-Host "No permissions found matching your criteria." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "`nERROR: $_" -ForegroundColor Red
        Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        if ($_.Exception -like "*window handle*") {
            Write-Host "`nSOLUTION: Rerun with -DeviceAuth parameter" -ForegroundColor Yellow
            Write-Host "Example: .\GetSharedMailboxPermissions.ps1 -MFA -DeviceAuth"
        }
    }
    finally {
        Cleanup
        Write-Host "`nScript execution completed in $((Get-Date).Subtract($ScriptStartTime).TotalMinutes.ToString('0.0')) minutes" -ForegroundColor Cyan
    }
}
# This script automates the process of changing a password for a specified account managed by CyberArk PAS.
# It performs the following actions:
# 1. Installs the psPAS module from the PowerShell Gallery if it's not already installed.
# 2. Sets the execution policy to allow the running of scripts (requires admin privileges).
# 3. Imports the psPAS module.
# 4. Retrieves credentials for CyberArk PAS authentication via a REST API call.
# 5. Establishes a new session with the CyberArk PAS API using the retrieved credentials.
# 6. Retrieves the account details for a specified account.
# 7. Extracts the AccountID from the account details.
# 8. Invokes a password change operation on the account using the AccountID.
# 9. Checks for a new password by comparing the retrieved password against a new call to the REST API, waiting one minute between checks, and performing up to 4 checks.
# 10. Ends the session with the CyberArk PAS API.

# Install the psPAS module from the PowerShell Gallery if it's not already installed
if (-not (Get-Module -ListAvailable -Name psPAS)) {
    Install-Module -Name psPAS -Scope CurrentUser -Force
}

# Set the execution policy to allow the running of scripts (requires admin privileges)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force

# Import the psPAS module
Import-Module psPAS

# Function to retrieve the account password
function Get-AccountPassword {
    param (
        [string]$Uri,
        [System.Management.Automation.PSCredential]$Credential
    )
    $response = Invoke-RestMethod -Method Get -Uri $Uri -ContentType "application/json" -Credential $Credential
    return $response.Content
}

# Retrieve credentials for CyberArk PAS authentication via a REST API call
$uri = "https://cyberark.example.com/api/Accounts?AppID=APP-ID&Safe=SAFE-NAME&UserName=account_name"
$response = Invoke-RestMethod -Method Get -Uri $uri -ContentType "application/json" -UseDefaultCredentials
$username = $response.UserName
$password = $response.Content | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($username, $password)

# Establish a new session with the CyberArk PAS API using the retrieved credentials
$baseuri = "https://cyberark.example.com"
New-PASSession -BaseURI $baseuri -Credential $cred -type LDAP

# Retrieve the account details for the specified account
$accountDetails = Get-PASAccount -Search 'account_name'

# Check if account details were retrieved successfully
if ($accountDetails) {
    # Extract the AccountID (id property) from the account details
    $accountID = $accountDetails.id

    # Invoke a password change operation using the extracted AccountID
    Invoke-PASCPMOperation -AccountID $accountID -ChangeTask
    Write-Host "Password change operation invoked for AccountID: $accountID"

    # Wait and check for a new password
    $attempts = 0
    $maxAttempts = 4
    $passwordChanged = $false
    while (-not $passwordChanged -and $attempts -lt $maxAttempts) {
        Start-Sleep -Seconds 60  # Wait for 1 minute
        $newPassword = Get-AccountPassword -Uri $uri -Credential $cred
        if ($newPassword -ne $password) {
            Write-Host "Password has changed."
            $passwordChanged = $true
        } else {
            Write-Host "Password has not changed yet. Attempting again..."
            $attempts++
        }
    }
    if (-not $passwordChanged) {
        Write-Host "Password did not change after $maxAttempts attempts."
    }
} else {
    Write-Host "Failed to retrieve account details for 'account_name'."
}

# End the session with the CyberArk PAS API
Close-PASSession

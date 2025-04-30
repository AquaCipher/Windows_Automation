# This script automates the process of changing a password for a specified account managed by CyberArk PAS
# and updates the Credential Profile in AdTempus with the new password.  

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
    $maxAttempts = 5
    $passwordChanged = $false
    $newPassword = ""
    while (-not $passwordChanged -and $attempts -lt $maxAttempts) {
        Start-Sleep -Seconds 90  # Wait for 1 minute 30 seconds
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
        exit 1
    }
} else {
    Write-Host "Failed to retrieve account details for 'account_name'."
    exit 1
}

# End the session with the CyberArk PAS API
Close-PASSession

# Update the Credential Profile in AdTempus with the new password
# Reference for adTempus 4
# add-type -path "c:\program files\arcana development\adtempus\4.0\ArcanaDevelopment.adTempus.Client.dll"

# For adTempus 5 use one of these instead:
# if running on an adTempus server:
add-type -path "c:\program files\arcana development\adtempus\instances\default\bin\ArcanaDevelopment.adTempus.Client.dll"
# if only the Console is installed:
# add-type -path "c:\program files\arcana development\adtempus\5.0\Console\ArcanaDevelopment.adTempus.Client.dll"

try {
    $adtempus = [ArcanaDevelopment.adTempus.Client.Scheduler]::Connect(".", [ArcanaDevelopment.adTempus.Shared.LoginAuthenticationType]::Windows, "", "")
}
catch {
    $_
    exit 8
}

try {
    $context = $adtempus.NewDataContext()
    $profile = $context.GetCredentialProfile("domain\account_name", $null, $null)
    if ($profile -eq $null) {
        Write-Output "Profile not found"
        exit 8
    }

    $profile.SetPassword($newPassword)
    $profile.Save()

    Write-Output "Password updated"
}
catch {
    $_
    exit 8
}
finally {
    $context.Dispose()
    $adTempus.Dispose()
}

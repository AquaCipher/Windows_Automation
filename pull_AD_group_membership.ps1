# Initialize an array to store the data
$groupData = @()

# Define the output CSV and log file paths
$serverName = $env:COMPUTERNAME
$date = Get-Date -Format "yyyyMMdd"
$csvPath = "\\fileshare\GroupMemberships\GroupMemberships_$serverName_$date.csv"
$logPath = "\\fileshare\GroupMemberships\GroupMemberships_$serverName_$date.log"

# Function to write messages to the log file
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logPath -Append
}

# Function to detect the OS version
function Get-OSVersion {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    return $os.Version
}

# Get the OS version
$osVersion = Get-OSVersion

# Determine the method based on OS version
if ($osVersion -ge "10.0") {
    # Use Get-LocalGroup and Get-LocalGroupMember for Windows 10 and Server 2016+
    $groups = Get-LocalGroup
    foreach ($group in $groups) {
        try {
            $groupMembers = Get-LocalGroupMember -Group $group.Name
            foreach ($member in $groupMembers) {
                $groupData += [PSCustomObject]@{
                    ServerName = $env:COMPUTERNAME
                    GroupName  = $group.Name
                    MemberName = $member.Name
                    MemberType = $member.ObjectClass
                    Source     = "PowerShell"
                }
            }
        } catch {
            $groupData += [PSCustomObject]@{
                ServerName = $env:COMPUTERNAME
                GroupName  = $group.Name
                MemberName = "Error: $($_.Exception.Message)"
                MemberType = "Error"
                Source     = "PowerShell"
            }
            $netLocalGroupOutput = net localgroup $group.Name
            $netLocalGroupMembers = $netLocalGroupOutput -match "^\s{4}\S+"
            foreach ($netMember in $netLocalGroupMembers) {
                $groupData += [PSCustomObject]@{
                    ServerName = $env:COMPUTERNAME
                    GroupName  = $group.Name
                    MemberName = $netMember.Trim()
                    MemberType = "Unknown"
                    Source     = "NetLocalGroup - Investigate"
                }
            }
        }
    }
} else {
    # Use WMI and net localgroup for older versions
    $groups = Get-WmiObject -Query "SELECT * FROM Win32_Group"
    foreach ($group in $groups) {
        try {
            $members = Get-WmiObject -Query "ASSOCIATORS OF {Win32_Group.Domain='$($group.Domain)',Name='$($group.Name)'} WHERE AssocClass=Win32_GroupUser"
            foreach ($member in $members) {
                $groupData += [PSCustomObject]@{
                    ServerName = $env:COMPUTERNAME
                    GroupName  = $group.Name
                    MemberName = $member.PartComponent
                    MemberType = "WMI"
                    Source     = "WMI"
                }
            }
        } catch {
            $groupData += [PSCustomObject]@{
                ServerName = $env:COMPUTERNAME
                GroupName  = $group.Name
                MemberName = "Error: $($_.Exception.Message)"
                MemberType = "Error"
                Source     = "WMI"
            }
            $netLocalGroupOutput = net localgroup $group.Name
            $netLocalGroupMembers = $netLocalGroupOutput -match "^\s{4}\S+"
            foreach ($netMember in $netLocalGroupMembers) {
                $groupData += [PSCustomObject]@{
                    ServerName = $env:COMPUTERNAME
                    GroupName  = $group.Name
                    MemberName = $netMember.Trim()
                    MemberType = "Unknown"
                    Source     = "NetLocalGroup - Investigate"
                }
            }
        }
    }
}

# Flag to track if any validation issues are detected
$validationIssuesDetected = $false

# Perform data validation checks
foreach ($entry in $groupData) {
    # Check for presence of required fields
    if (-not $entry.ServerName -or -not $entry.GroupName -or -not $entry.MemberName) {
        Write-Log "Validation Error: Missing required fields in entry."
        $validationIssuesDetected = $true
    }

    # Check for data type validation
    if ($entry.MemberType -isnot [string]) {
        Write-Log "Validation Error: MemberType is not a string."
        $validationIssuesDetected = $true
    }

    # Check for consistency in Source values
    if ($entry.Source -ne "PowerShell" -and $entry.Source -ne "NetLocalGroup - Investigate") {
        Write-Log "Validation Error: Unexpected Source value."
        $validationIssuesDetected = $true
    }
}

# Check for duplicate entries
$uniqueEntries = $groupData | Select-Object -Unique
if ($uniqueEntries.Count -ne $groupData.Count) {
    Write-Log "Validation Warning: Duplicate entries detected."
    $validationIssuesDetected = $true
}

# Export the data to a CSV file
$groupData | Export-Csv -Path $csvPath -NoTypeInformation

# Log successful export only if validation issues were detected
if ($validationIssuesDetected) {
    Write-Log "Group membership data exported to $csvPath"
}

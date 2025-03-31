# Initialize an array to store the data
$groupData = @()

# Get all local groups
$groups = Get-LocalGroup

# Iterate over each group and attempt to list its members
foreach ($group in $groups) {
    try {
        $groupMembers = Get-LocalGroupMember -Group $group.Name
        foreach ($member in $groupMembers) {
            # Add each member's data to the array
            $groupData += [PSCustomObject]@{
                ServerName = $env:COMPUTERNAME
                GroupName  = $group.Name
                MemberName = $member.Name
                MemberType = $member.ObjectClass
                Source     = "PowerShell"
            }
        }
    } catch {
        # Log the error for the group
        $groupData += [PSCustomObject]@{
            ServerName = $env:COMPUTERNAME
            GroupName  = $group.Name
            MemberName = "Error: $($_.Exception.Message)"
            MemberType = "Error"
            Source     = "PowerShell"
        }

        # Attempt to retrieve group members using net localgroup
        $netLocalGroupOutput = net localgroup $group.Name
        $netLocalGroupMembers = $netLocalGroupOutput -match "^\s{4}\S+"

        foreach ($netMember in $netLocalGroupMembers) {
            # Add each member's data to the array with a flag for investigation
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

# Export the data to a CSV file
$csvPath = "C:\Path\To\Output\GroupMemberships.csv"
$groupData | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "Group membership data exported to $csvPath"

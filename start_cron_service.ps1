# Define the task name and description
$taskName = "StartCronService"
$taskDescription = "Start cron service at system startup"

# Define the action to run WSL with the specified arguments
$action = New-ScheduledTaskAction -Execute "C:\Windows\System32\wsl.exe" -Argument "sudo /usr/sbin/service cron start"

# Define the trigger to run the task at system startup
$trigger = New-ScheduledTaskTrigger -AtStartup

# Define the principal to run the task with highest privileges
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Create the scheduled task
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Description $taskDescription

# Register the scheduled task
Register-ScheduledTask -TaskName $taskName -InputObject $task

# Run the scheduled task immediately
Start-ScheduledTask -TaskName $taskName

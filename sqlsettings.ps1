Install-WindowsFeature RSAT-AD-PowerShell 
Install-ADServiceAccount -Identity "accountToReplace" 
Test-ADServiceAccount -Identity "accountToReplace"
sc.exe --% config "MSSQLSERVER" obj="prod\accountToReplace$" type= own 
sc.exe --% config "SQLSERVERAGENT" obj="prod\accountToReplace$" type= own 
Set-Service -Name SQLSERVERAGENT -StartupType Automatic
Stop-Service -Name 'MSSQLSERVER' -Force
Start-Service -Name 'MSSQLSERVER'
Stop-Service -Name 'SQLSERVERAGENT'

Try
{
    Start-Service -Name 'SQLSERVERAGENT'
    Write-Host "Starting SQLSERVERAGENT"
}
Catch
{
    Write-Host "check SQLSERVERAGENT"
}

SetSPN -s "MSSQLSvc/serverToReplace.prod.cloud" "prod\accountToReplace$"
SetSPN -s "MSSQLSvc/serverToReplace.prod.cloud:1433" "prod\accountToReplace$"
setSPN -L "prod\accountToReplace$"

##########################################################################
#  Import SQLServer Module
#  file move
##########################################################################
$SQLServiceAccount = "accountToReplace"
Import-Module -Name SQLPS
#Install-module sqlserver
$Server = hostname
$iName = hostname
IF ($SQLServiceAccount -eq $SQLServiceAgtAccount) {
        Add-LocalGroupMember -Group "Administrators" -Member $SQLServiceAccount
} ELSE {
}


try{
    Add-LocalGroupMember -Group "Administrators" -Member $SQLServiceAccount -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "Administrators" -Member $SQLServiceAgtAccount -ErrorAction SilentlyContinue
    Write-Host "Starting SQLSERVERAGENT"
}
Catch
{
    Write-Host "check SQLSERVERAGENT"
}


$Server = hostname
$iName = hostname
$ins = Invoke-Command -ComputerName $Server -ScriptBlock { Get-Item -path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' | Select-Object -ExpandProperty Property }

if($ins -ne "MSSQLSERVER")
{ $SQLService = "MSSQL$" + $ins; $agt1 = "SQLAgent$" + $ins;}
else { $SQLService = "MSSQLSERVER"; $agt1 = "SQLSERVERAGENT" ;}
###########################################################################
##  Get and Add SQL Service\SQL Agent service to admins group will
##  completing file move
###########################################################################
$SQLServiceAccount = Get-WmiObject win32_service -computer $Server | Where-Object {$_.name -eq $SQLService} | select -ExpandProperty StartName
$SQLServiceAgtAccount = Get-WmiObject win32_service -computer $Server | Where-Object {$_.name -eq $agt1} | select -ExpandProperty StartName
IF ($SQLServiceAccount -eq $SQLServiceAgtAccount) {
        Add-LocalGroupMember -Group "Administrators" -Member $SQLServiceAccount -ErrorAction SilentlyContinue
} ELSE {
}


###########################################################################
##  Set Variables for the Master, msdb, and model databases
##
###########################################################################
$s = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server $iName
$sourcelogpath = $s.Databases["Master"].LogFiles.FileName.TrimEnd("\mastlog.ldf")
$targetlogpath = $sourcelogpath.Replace("C:\","E:\")
$targetlogpath = $targetlogpath.TrimEnd("\")
$sourcedatapath = $s.Databases["Master"].Filegroups.Files.FileName.TrimEnd("\master.mdf")
$targetdatapath = $sourcedatapath.Replace("C:\","E:\")
$targetdatapath = $targetdatapath.TrimEnd("\")
$masterTlog = $s.Databases["Master"].LogFiles.FileName
$masterData = $s.Databases["Master"].Filegroups.Files.FileName


$sblock = [scriptblock]::Create("get-ItemProperty -path ""HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$ins\MSSQLServer\Parameters"" -Name SQLArg1 | select -ExpandProperty SQLArg1")
$ErrorlogLocationStartupParam = invoke-command -computername $Server -ScriptBlock $sblock
$TargetErrorlogLocationStartupParam = $ErrorlogLocationStartupParam.Replace("C:\","E:\")
$ErrorlogLocation = $ErrorlogLocationStartupParam.TrimStart('-e')
$TargetErrorlogLocation = $TargetErrorlogLocationStartupParam.TrimStart('-e')
$ErrorlogLocation = $ErrorlogLocation.TrimEnd('\ERRORLOG')
$TargetErrorlogLocation = $TargetErrorlogLocation.TrimEnd('\ERRORLOG')
$sblock = [scriptblock]::Create("get-ItemProperty -path ""HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$ins\CPE"" -Name ErrorDumpDir | select -ExpandProperty ErrorDumpDir")
$SQLServerDumpLocation = invoke-command -computername $Server -ScriptBlock $sblock
$TargetSQLServerDumpLocation = $SQLServerDumpLocation.Replace("C:\","E:\")

$DefaultDataLocation = $s | Select -ExpandProperty DefaultFile
$DefaultLogLocation = $s | Select -ExpandProperty DefaultLog
$DefaultBackupDirectory = $s | Select -ExpandProperty BackupDirectory
$DefaultBackupDirectory = $DefaultBackupDirectory.Replace("C:\","E:\")
$UserDBDataDefaultLocation = 'F:\SQL_Data'
$UserDBLogDefaultLocation = 'G:\SQL_Logs'
$TempDBTargetLocation = 'T:\SQL_TempDB'
##################################################


###########################################################################
## Create Directories on the GPT\64K formatted drives
## ###########################################################################
 New-Item -ItemType Directory -Force -Path $DefaultDataLocation
 New-Item -ItemType Directory -Force -Path $DefaultLogLocation
 New-Item -ItemType Directory -Force -Path $DefaultBackupDirectory
 New-Item -ItemType Directory -Force -Path $TargetErrorlogLocation
 New-Item -ItemType Directory -Force -Path $targetdatapath
 New-Item -ItemType Directory -Force -Path $UserDBDataDefaultLocation
 New-Item -ItemType Directory -Force -Path $UserDBLogDefaultLocation
 New-Item -ItemType Directory -Force -Path $TempDBTargetLocation


###########################################################################
## Move SQL Server Agent Error log file and Default backup directory
##
###########################################################################
$SQLAgentERRORLogLocation = $s.jobserver.ErrorLogFile
$SQLAgentERRORLogLocation = $SQLAgentERRORLogLocation.Replace("C:\","E:\")
$s.jobserver.ErrorLogFile = $SQLAgentERRORLogLocation
$s.jobserver.Alter();
$s.DefaultFile = $UserDBDataDefaultLocation
$s.Alter();

$s.DefaultLog = $UserDBLogDefaultLocation
$s.Alter();

$s.BackupDirectory = $DefaultBackupDirectory
$s.Alter();

###########################################################################
##  Update model and msdb files.  Stop services and update master startup
##  params
###########################################################################
if ($sourcelogpath -ne $targetlogpath -or $sourcedatapath -ne $targetdatapath)
{
echo "`r`nMoving the Database Files and Transaction Log files for Master, Model and MSDB
databases to the default user db directories : `r`n$targetdatapath`r`n$targetlogpath "
$masterData = $masterData.Replace("$sourcedatapath","$targetdatapath")
$masterTlog = $masterTlog.Replace("$sourcelogpath","$targetlogpath")
$('model','msdb')|
        ForEach-Object {$Db = $s.databases[$PSItem]
                foreach ($fg in $Db.FileGroups)
                        {foreach ($fl in $fg.Files) {$fl.FileName = $fl.FileName.Replace("$sourcedatapath","$targetdatapath")}}
                foreach ($fl in $Db.LogFiles) {$fl.FileName = $fl.FileName.Replace("$sourcedatapath","$targetdatapath")}
                $s.databases[$PSItem].Alter()
}
$('tempdb')|
        ForEach-Object {$Db = $s.databases[$PSItem]
                foreach ($fg in $Db.FileGroups)
                        {foreach ($fl in $fg.Files) {$fl.FileName = $fl.FileName.Replace("$sourcedatapath","$TempDBTargetLocation")}}
                foreach ($fl in $Db.LogFiles) {$fl.FileName = $fl.FileName.Replace("$source
datapath","$TempDBTargetLocation")}
$s.databases[$PSItem].Alter()
}

###########################################################################
##  Stopping sql server services to move all necessary files and setting
##  sql server agent services to automatic
###########################################################################
echo "`r`nStopping and starting SQL services."
Get-Service -Name $SQLService -ComputerName $Server | Stop-Service -Force
Get-Service -Name $agt1 -ComputerName $Server | Stop-Service -Force
Set-Service -Name $agt1 -ComputerName $Server -StartupType Automatic
$sblock = [scriptblock]::Create("Set-ItemProperty -path ""HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$ins\MSSQLServer\Parameters"" -Name SQLArg0 -Value (""-d" + $masterData + """)")
invoke-command -computername $Server -ScriptBlock $sblock
$sblock = [scriptblock]::Create("Set-ItemProperty -path ""HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$ins\MSSQLServer\Parameters"" -Name SQLArg2 -Value (""-l" + $masterTlog + """)")
invoke-command -computername $Server -ScriptBlock $sblock

###########################################################################
## Update error log startup parameters and sql server dump location
##
###########################################################################

if ($ErrorlogLocationStartupParam -ne $TargetErrorlogLocationStartupParam)
{
echo "`r`nMoving the SQL Server Error Log : `r` $TargetErrorlogLocationStartupParam "

$sblock = [scriptblock]::Create("Set-ItemProperty -path ""HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$ins\MSSQLServer\Parameters"" -Name SQLArg1 -Value (""$TargetErrorlogLocationStartupParam"")")
invoke-command -computername $Server -ScriptBlock $sblock
}

if ($SQLServerDumpLocation -ne $TargetSQLServerDumpLocation)
{
echo "`r`nMoving the SQL Server Dump Location : `r` $TargetSQLServerDumpLocation "
$sblock = [scriptblock]::Create("Set-ItemProperty -path ""HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$ins\CPE"" -Name ErrorDumpDir -Value (""$TargetSQLServerDumpLocation"")")
invoke-command -computername $Server -ScriptBlock $sblock
}

###########################################################################
## Moves all mdf\ldf files and sql log files to new location
##
###########################################################################
$sblock = [scriptblock]::Create("Move-Item -Path ""$sourcelogpath" + "\*.ldf"" -Destination ""$targetlogpath" + "\""")
$xyz1 = invoke-command -computername $Server -ScriptBlock $sblock
$sblock = [scriptblock]::Create("Move-Item -Path ""$sourcedatapath" + "\*.mdf"" -Destination ""$targetdatapath" + "\""")
$xyz1 = invoke-command -computername $Server -ScriptBlock $sblock
$sblock = [scriptblock]::Create("Move-Item -Path ""$sourcedatapath" + "\*.ndf"" -Destination ""$targetdatapath" + "\""")
$xyz1 = invoke-command -computername $Server -ScriptBlock $sblock
$sblock = [scriptblock]::Create("Move-Item -Path ""$ErrorlogLocation" + "\*.*"" -Destination ""$TargetErrorlogLocation" + "\""")
$xyz1 = invoke-command -computername $Server -ScriptBlock $sblock

###########################################################################
##  Restart services
##
###########################################################################
Get-Service -Name $SQLService -ComputerName $Server | Start-Service
Get-Service -Name $agt1 -ComputerName $Server | Start-Service
}
###########################################################################
##  Remove SQL Service\SQL Agent service to admins group
##
###########################################################################
IF ($SQLServiceAccount -eq $SQLServiceAgtAccount) {
} ELSE {
}
Remove-LocalGroupMember -Group "Administrators" -Member $SQLServiceAccount
Remove-LocalGroupMember -Group "Administrators" -Member $SQLServiceAccount
Remove-LocalGroupMember -Group "Administrators" -Member $SQLServiceAgtAccount
###########################################################################
##  Grant Necessary permissions to locations SQL Server needs to access
##  ******Move under file creation
###########################################################################
$Installlocation = 'E:\Program Files\Microsoft SQL Server'
#$APILoglocation = 'C:\windows\system32\LogFiles'    ##probably a bad idea here... dont
think its needed
#New-Item -Path $path -ItemType directory
$acl = Get-Acl -Path $Installlocation
$permission = $SQLServiceAccount, 'FullControl', 'ContainerInherit, ObjectInherit', 'None','Allow'
$permission2 = $SQLServiceAgtAccount, 'FullControl', 'ContainerInherit, ObjectInherit','None', 'Allow'
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission
$rule2 = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission2
$acl.SetAccessRule($rule)
$acl.SetAccessRule($rule2)
$acl | Set-Acl -Path $Installlocation
#$acl | Set-Acl -Path $APILoglocation 

#(new-object net.webclient).DownloadFile('http://10.18.129.72/packages/lab/hardening.zip','C:\hardening.zip')


 

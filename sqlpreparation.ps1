

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [string] $ServiceAccount
)

Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | ConvertTo-Json -Depth 64 >c:\meta.json

$a = Get-Content C:\meta.json | ConvertFrom-Json

$subscriptionId = $a.compute.subscriptionId
$location = $a.compute.location
$resourceGroup = $a.compute.resourceGroupName
$resourceId = $a.compute.resourceId
$name = $a.compute.name
$storageDetails = $a.compute.storageProfile.dataDisks
$sku = $a.compute.sku
$userData = $a.compute.userData
$customData = $a.compute.customData
$vmSize = $a.compute.vmSize

#
$privateIpAddress = $a.network.interface.ipv4.ipAddress.publicIpAddress
$privateIpAddress = $a.network.interface.ipv4.ipAddress.privateIpAddress

#networking
$subnet = ($a.network.interface.ipv4.subnet |select address).address
$mask = ($a.network.interface.ipv4.subnet |select prefix).prefix

$count = $storageDetails.count

Try
{
    $drv = Get-WmiObject win32_volume -filter 'DriveLetter = "E:"'
    $drv.DriveLetter = "Z:"
    $drv.Put() | out-null
    Write-Host "Changing CDROM to Z"
}
Catch
{
    Write-Host "An error occurred changing CDROM letter"
}


function InitializeDisk($disk){
    Try
    {
        Initialize-Disk -Number $disk -PartitionStyle GPT -ErrorAction SilentlyContinue

        Write-Host "Initializing disk $disk"
        sleep 5
    }
    Catch
    {
        Write-Host "An error occurred Initializing $disk"
    }

}

$i=2
while($i -lt 6){
    InitializeDisk($i)
    $i=$i+1
}


New-Volume -DiskNumber 2 -FriendlyName 'SQL-System' -DriveLetter E -AllocationUnitSize 64KB -ErrorAction SilentlyContinue
New-Volume -DiskNumber 3 -FriendlyName 'SQL-Data' -DriveLetter F -AllocationUnitSize 64KB -ErrorAction SilentlyContinue 
New-Volume -DiskNumber 4 -FriendlyName 'SQL-Logs' -DriveLetter G -AllocationUnitSize 64KB -ErrorAction SilentlyContinue
New-Volume -DiskNumber 5 -FriendlyName 'SQL-TempDB' -DriveLetter T -AllocationUnitSize 64KB -ErrorAction SilentlyContinue

(new-object net.webclient).DownloadFile('https://raw.githubusercontent.com/MauroTamariz/testing/main/sqlsettings.ps1','C:\sqlsettings.ps1')

$ServerName = hostname

if ($ServiceAccount){
    try{
        ADD-ADGroupMember $ServiceAccount -members $ServerName'$'
    }
    Catch
    {
        Write-Host "check add group name " $ServerName 
    }

    (gc C:\sqlsettings.ps1) -replace 'accountToReplace', $ServiceAccount | Out-File -encoding ASCII C:\sqlsettings.ps1
    sleep 5
    (gc C:\sqlsettings.ps1) -replace 'serverToReplace', $ServerName | Out-File -encoding ASCII C:\sqlsettings.ps1
    Restart-Computer
}


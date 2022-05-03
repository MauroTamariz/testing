[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [string] $ServiceAccount
)
(new-object net.webclient).DownloadFile('https://raw.githubusercontent.com/MauroTamariz/testing/main/sqlsettings.ps1','C:\sqlsettings.ps1')
if ($ServiceAccount){
    (gc C:\sqlsettings.ps1) -replace 'accountToReplace', $ServiceAccount | Out-File -encoding ASCII C:\sqlsettings.ps1
    cd C:\
    ./sqlsettings.ps1
}



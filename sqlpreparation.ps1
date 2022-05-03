
(new-object net.webclient).DownloadFile('https://raw.','local.ps1')./local.ps1


powershell -Command "(gc sqlsettings.ps1) -replace 'accountToReplace', 'service_account' | Out-File -encoding ASCII sqlsettings.ps1"

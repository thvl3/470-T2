# install-splunk-forwarder-windows-iis.ps1
# Purpose: Install and configure Splunk Universal Forwarder on IIS web servers.

param(
    [string]$SplunkServer = "192.168.90.20",
    [string]$SplunkPort = "9997",
    [string]$MsiPath = "C:\Temp\splunkforwarder.msi",
    [string]$SplunkAdminUser = "admin",
    [string]$SplunkAdminPassword = "password!23",
    [string]$WindowsIndex = "wineventlog",
    [string]$IisIndex = "iis"
)

$ErrorActionPreference = "Stop"

Write-Host "[+] Splunk Universal Forwarder IIS install starting..."

if (!(Test-Path $MsiPath)) {
    Write-Host "[!] MSI not found at $MsiPath"
    Write-Host "    Download/copy splunkforwarder.msi to that path, or pass -MsiPath."
    exit 1
}

$SplunkHome = "C:\Program Files\SplunkUniversalForwarder"
$SplunkExe = "$SplunkHome\bin\splunk.exe"

if (!(Test-Path $SplunkExe)) {
    Write-Host "[+] Installing Splunk Universal Forwarder..."

    $Args = @(
        "/i `"$MsiPath`"",
        "AGREETOLICENSE=Yes",
        "SPLUNKUSERNAME=$SplunkAdminUser",
        "SPLUNKPASSWORD=$SplunkAdminPassword",
        "RECEIVING_INDEXER=`"$SplunkServer`:$SplunkPort`"",
        "/quiet"
    ) -join " "

    Start-Process msiexec.exe -ArgumentList $Args -Wait -NoNewWindow
} else {
    Write-Host "[+] Splunk Universal Forwarder already installed."
}

Write-Host "[+] Creating local config directories..."
New-Item -ItemType Directory -Force -Path "$SplunkHome\etc\system\local" | Out-Null

Write-Host "[+] Writing outputs.conf..."
@"
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = $SplunkServer`:$SplunkPort

[tcpout-server://$SplunkServer`:$SplunkPort]
"@ | Set-Content -Path "$SplunkHome\etc\system\local\outputs.conf" -Encoding ASCII

Write-Host "[+] Writing inputs.conf for IIS and Windows logs..."
@"
[WinEventLog://Security]
disabled = 0
index = $WindowsIndex
sourcetype = WinEventLog:Security
renderXml = true

[WinEventLog://System]
disabled = 0
index = $WindowsIndex
sourcetype = WinEventLog:System
renderXml = true

[WinEventLog://Application]
disabled = 0
index = $WindowsIndex
sourcetype = WinEventLog:Application
renderXml = true

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = 0
index = $WindowsIndex
sourcetype = WinEventLog:PowerShell:Operational
renderXml = true

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = 0
index = sysmon
sourcetype = XmlWinEventLog:Microsoft-Windows-Sysmon/Operational
renderXml = true

[monitor://C:\inetpub\logs\LogFiles\W3SVC*\*.log]
disabled = 0
index = $IisIndex
sourcetype = ms:iis:auto
crcSalt = <SOURCE>
"@ | Set-Content -Path "$SplunkHome\etc\system\local\inputs.conf" -Encoding ASCII

Write-Host "[+] Opening local outbound firewall rule for Splunk forwarding..."
New-NetFirewallRule `
    -DisplayName "Allow Splunk UF Outbound TCP $SplunkPort" `
    -Direction Outbound `
    -Protocol TCP `
    -RemoteAddress $SplunkServer `
    -RemotePort $SplunkPort `
    -Action Allow `
    -ErrorAction SilentlyContinue | Out-Null

Write-Host "[+] Restarting Splunk Universal Forwarder..."
& $SplunkExe restart --accept-license --answer-yes --no-prompt

Write-Host "[+] Done. Test in Splunk:"
Write-Host "    index=$WindowsIndex host=$env:COMPUTERNAME"
Write-Host "    index=$IisIndex host=$env:COMPUTERNAME"

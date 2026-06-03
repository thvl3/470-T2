# install-splunk-forwarder-windows-dc.ps1
# Purpose: Install and configure Splunk Universal Forwarder on the Domain Controller.

param(
    [string]$SplunkServer = "192.168.90.20",
    [string]$SplunkPort = "9997",
    [string]$MsiPath = "C:\Temp\splunkforwarder.msi",
    [string]$SplunkAdminUser = "admin",
    [string]$SplunkAdminPassword = "password!23",
    [string]$Index = "wineventlog"
)

$ErrorActionPreference = "Stop"

Write-Host "[+] Splunk Universal Forwarder DC install starting..."

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

Write-Host "[+] Writing inputs.conf for DC logs..."
@"
[WinEventLog://Security]
disabled = 0
index = $Index
sourcetype = WinEventLog:Security
renderXml = true

[WinEventLog://System]
disabled = 0
index = $Index
sourcetype = WinEventLog:System
renderXml = true

[WinEventLog://Application]
disabled = 0
index = $Index
sourcetype = WinEventLog:Application
renderXml = true

[WinEventLog://Directory Service]
disabled = 0
index = $Index
sourcetype = WinEventLog:DirectoryService
renderXml = true

[WinEventLog://DNS Server]
disabled = 0
index = $Index
sourcetype = WinEventLog:DNS
renderXml = true

[WinEventLog://Windows PowerShell]
disabled = 0
index = $Index
sourcetype = WinEventLog:PowerShell
renderXml = true

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = 0
index = $Index
sourcetype = WinEventLog:PowerShell:Operational
renderXml = true

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = 0
index = sysmon
sourcetype = XmlWinEventLog:Microsoft-Windows-Sysmon/Operational
renderXml = true
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
Write-Host "    index=$Index host=$env:COMPUTERNAME"
Write-Host "    index=sysmon host=$env:COMPUTERNAME"

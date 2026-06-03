Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-splunk-forwarder-windows-dc.ps1 -MsiPath C:\Temp\splunkforwarder.msi

Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-splunk-forwarder-windows-iis.ps1 -MsiPath C:\Temp\splunkforwarder.msi

chmod +x install-splunk-forwarder-linux-haproxy.sh
./install-splunk-forwarder-linux-haproxy.sh


DC01 192.168.90.10         -> Splunk 192.168.90.20 TCP/9997
WEB01 192.168.70.10        -> Splunk 192.168.90.20 TCP/9997
WEB02 192.168.70.11        -> Splunk 192.168.90.20 TCP/9997
LB01 192.168.70.5          -> Splunk 192.168.90.20 TCP/9997

5. Splunk searches to prove it works

After running the scripts, search:

index=wineventlog
index=iis
index=haproxy

Host-specific:

index=wineventlog host=DC01
index=iis host=WEB01 OR host=WEB02
index=haproxy host=loadbalancer

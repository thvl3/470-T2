#!/bin/bash
# install-splunk-forwarder-linux-haproxy.sh
# Purpose: Configure HAProxy logging and forward logs to Splunk.

set -euo pipefail

SPLUNK_SERVER="192.168.90.20"
SPLUNK_PORT="9997"
SPLUNK_DEB="/root/splunkforwarder.deb"
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_USER="admin"
SPLUNK_PASSWORD="password!23"

echo "[+] Starting HAProxy Splunk forwarder setup..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[!] Run this script as root."
  exit 1
fi

echo "[+] Ensuring required packages exist..."
apt update
apt install -y rsyslog haproxy

echo "[+] Configuring HAProxy logging..."

if ! grep -q "log /dev/log local0" /etc/haproxy/haproxy.cfg; then
  sed -i '/^global/a\    log /dev/log local0\n    log /dev/log local1 notice' /etc/haproxy/haproxy.cfg
fi

if ! grep -q "option httplog" /etc/haproxy/haproxy.cfg; then
  sed -i '/^defaults/a\    log global\n    mode http\n    option httplog\n    option dontlognull' /etc/haproxy/haproxy.cfg
fi

echo "[+] Writing rsyslog config for HAProxy..."
cat >/etc/rsyslog.d/49-haproxy.conf <<'EOF'
local0.*    /var/log/haproxy.log
local1.*    /var/log/haproxy.log
& stop
EOF

touch /var/log/haproxy.log
chmod 640 /var/log/haproxy.log

echo "[+] Restarting rsyslog and HAProxy..."
systemctl restart rsyslog
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl restart haproxy
systemctl enable haproxy

echo "[+] Installing Splunk Universal Forwarder if needed..."
if [ ! -x "$SPLUNK_HOME/bin/splunk" ]; then
  if [ ! -f "$SPLUNK_DEB" ]; then
    echo "[!] Splunk forwarder .deb not found at $SPLUNK_DEB"
    echo "    Copy it there first or edit SPLUNK_DEB in this script."
    exit 1
  fi

  dpkg -i "$SPLUNK_DEB" || apt -f install -y
else
  echo "[+] Splunk Universal Forwarder already installed."
fi

echo "[+] Accepting license and setting admin credentials..."
"$SPLUNK_HOME/bin/splunk" start \
  --accept-license \
  --answer-yes \
  --no-prompt \
  --seed-passwd "$SPLUNK_PASSWORD" || true

echo "[+] Configuring forward server..."
"$SPLUNK_HOME/bin/splunk" add forward-server "$SPLUNK_SERVER:$SPLUNK_PORT" \
  -auth "$SPLUNK_USER:$SPLUNK_PASSWORD" || true

echo "[+] Configuring HAProxy log input..."
mkdir -p "$SPLUNK_HOME/etc/system/local"

cat >"$SPLUNK_HOME/etc/system/local/inputs.conf" <<EOF
[monitor:///var/log/haproxy.log]
disabled = 0
index = haproxy
sourcetype = haproxy
EOF

cat >"$SPLUNK_HOME/etc/system/local/outputs.conf" <<EOF
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = $SPLUNK_SERVER:$SPLUNK_PORT

[tcpout-server://$SPLUNK_SERVER:$SPLUNK_PORT]
EOF

echo "[+] Enabling Splunk forwarder at boot..."
"$SPLUNK_HOME/bin/splunk" enable boot-start -user root || true

echo "[+] Restarting Splunk forwarder..."
"$SPLUNK_HOME/bin/splunk" restart

echo "[+] Generating test HAProxy traffic..."
for i in 1 2 3 4 5; do
  wget -qO- http://192.168.70.5 >/dev/null || true
done

echo "[+] Last HAProxy log lines:"
tail -n 10 /var/log/haproxy.log || true

echo "[+] Done. Test in Splunk:"
echo "    index=haproxy host=$(hostname)"

#!/bin/bash
# Heizkalender Setup Script
# Automatische Installation auf Raspberry Pi Zero W 2
# Usage: curl https://raw.githubusercontent.com/HeldTorben/heizkalender_kalender/main/setup.sh | bash

set -e

GITHUB="https://raw.githubusercontent.com/HeldTorben/heizkalender_kalender/main"
USER=$(whoami)
WEBROOT="/var/www/kalender"
BACKEND="/home/$USER/kalender.py"

echo "================================================"
echo " Heizkalender Setup"
echo " User: $USER"
echo "================================================"

# ===== System Update =====
echo "[1/8] System wird aktualisiert..."
sudo apt update -y && sudo apt upgrade -y

# ===== Pakete installieren =====
echo "[2/8] Pakete werden installiert..."
sudo apt install nginx python3-pip -y
sudo pip3 install flask icalendar --break-system-packages

# ===== Ordner anlegen =====
echo "[3/8] Ordner wird angelegt..."
sudo mkdir -p $WEBROOT
sudo chown $USER:$USER $WEBROOT

# ===== Leere ICS Datei =====
echo "[4/8] ICS-Datei wird erstellt..."
cat > $WEBROOT/heizung.ics << EOF
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Heizkalender//DE
CALSCALE:GREGORIAN
METHOD:PUBLISH
END:VCALENDAR
EOF

# ===== Dateien von GitHub laden =====
echo "[5/8] Dateien werden von GitHub geladen..."
wget -q $GITHUB/kalender.py -O $BACKEND
wget -q $GITHUB/index.html -O $WEBROOT/index.html
wget -q $GITHUB/sperrtage.html -O $WEBROOT/sperrtage.html

# ===== nginx konfigurieren =====
echo "[6/8] nginx wird konfiguriert..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo bash -c "cat > /etc/nginx/sites-available/kalender << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    location /kalender/heizung.ics {
        proxy_pass http://127.0.0.1:5000/kalender/heizung.ics;
        proxy_set_header Host \$host;
    }

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
}
NGINXEOF"
sudo ln -sf /etc/nginx/sites-available/kalender /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# ===== Service anlegen =====
echo "[7/8] Service wird eingerichtet..."
sudo bash -c "cat > /etc/systemd/system/kalender.service << EOF
[Unit]
Description=Heizkalender Web
After=network.target

[Service]
ExecStart=/usr/bin/python3 $BACKEND
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF"
sudo systemctl daemon-reload
sudo systemctl enable kalender
sudo systemctl start kalender

# ===== Verifikation =====
echo "[8/8] Installation wird verifiziert..."
sleep 3

if sudo systemctl is-active --quiet kalender; then
    echo "✓ kalender.service läuft"
else
    echo "✗ kalender.service läuft NICHT"
    sudo systemctl status kalender
    exit 1
fi

if sudo systemctl is-active --quiet nginx; then
    echo "✓ nginx läuft"
else
    echo "✗ nginx läuft NICHT"
    exit 1
fi

ICS=$(curl -s http://localhost/kalender/heizung.ics)
if echo "$ICS" | grep -q "BEGIN:VCALENDAR"; then
    echo "✓ ICS-Datei erreichbar"
else
    echo "✗ ICS-Datei nicht erreichbar"
    exit 1
fi

IP=$(hostname -I | awk '{print $1}')
echo ""
echo "================================================"
echo " Installation erfolgreich!"
echo ""
echo " Web-UI:  http://$IP"
echo " ICS-URL: http://$IP/kalender/heizung.ics"
echo ""
echo " ICS-URL in CCU eintragen:"
echo " HK1-ICS-Url = http://$IP/kalender/heizung.ics"
echo "================================================"

#!/bin/bash
# =====================================================================
# Heizkalender Setup Script
# Automatische Installation auf Raspberry Pi Zero W 2
#
# Aufruf (zwei Zeilen, nicht per Pipe):
#   curl -fsSL https://raw.githubusercontent.com/HeldTorben/heizkalender_kalender/main/setup.sh -o setup.sh
#   bash setup.sh
#
# Mehrfach ausfuehrbar: bestehende Termine (heizung.ics) bleiben erhalten.
# =====================================================================

set -e
trap 'echo ""; echo "[FEHLER] Setup abgebrochen in Zeile $LINENO. Ausgabe oben pruefen und Script erneut starten."' ERR

# ===== Konfiguration =====
GITHUB="https://raw.githubusercontent.com/HeldTorben/heizkalender_kalender/main"
USER=$(whoami)
WEBROOT="/var/www/kalender"
BACKEND="/home/$USER/kalender.py"
export DEBIAN_FRONTEND=noninteractive

echo "================================================"
echo " Heizkalender Setup"
echo " User: $USER"
echo "================================================"

# ===== Schritt 1: System-Update =====
echo "[1/8] System wird aktualisiert..."
sudo apt-get update -y
sudo apt-get upgrade -y

# ===== Schritt 2: Pakete =====
echo "[2/8] Pakete werden installiert..."
sudo apt-get install -y nginx python3-pip
sudo pip3 install flask icalendar --break-system-packages

# ===== Schritt 3: Ordner =====
echo "[3/8] Ordner wird angelegt..."
sudo mkdir -p "$WEBROOT"
sudo chown "$USER:$USER" "$WEBROOT"

# ===== Schritt 4: ICS-Datei (nur wenn noch nicht vorhanden) =====
echo "[4/8] ICS-Datei wird geprueft..."
if [ ! -f "$WEBROOT/heizung.ics" ]; then
cat > "$WEBROOT/heizung.ics" << EOF
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Heizkalender//DE
CALSCALE:GREGORIAN
METHOD:PUBLISH
END:VCALENDAR
EOF
    echo "      Neue leere heizung.ics angelegt."
else
    echo "      heizung.ics vorhanden, bleibt unveraendert."
fi

# ===== Schritt 5: Dateien von GitHub =====
echo "[5/8] Dateien werden von GitHub geladen..."
download() {
    # $1 = Dateiname im Repo, $2 = Zielpfad
    if ! wget -q "$GITHUB/$1" -O "$2.tmp"; then
        rm -f "$2.tmp"
        echo "[FEHLER] Download von $1 fehlgeschlagen. Internet und GitHub-Repository (public, Datei vorhanden?) pruefen."
        exit 1
    fi
    mv "$2.tmp" "$2"
    echo "      $1 -> $2"
}
download kalender.py "$BACKEND"
download index.html "$WEBROOT/index.html"
download sperrtage.html "$WEBROOT/sperrtage.html"

# ===== Schritt 6: nginx =====
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
sudo ln -sf /etc/nginx/sites-available/kalender /etc/nginx/sites-enabled/kalender
sudo nginx -t
sudo systemctl restart nginx

# ===== Schritt 7: systemd-Service =====
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
sudo systemctl restart kalender

# ===== Schritt 8: Verifikation =====
echo "[8/8] Installation wird verifiziert (max. 40 Sekunden)..."

ICS_OK=0
for i in $(seq 1 20); do
    if curl -fs http://localhost/kalender/heizung.ics | grep -q "BEGIN:VCALENDAR"; then
        ICS_OK=1
        break
    fi
    sleep 2
done

if sudo systemctl is-active --quiet kalender; then
    echo "[OK] kalender.service laeuft"
else
    echo "[FEHLER] kalender.service laeuft NICHT"
    sudo systemctl status kalender --no-pager || true
    exit 1
fi

if sudo systemctl is-active --quiet nginx; then
    echo "[OK] nginx laeuft"
else
    echo "[FEHLER] nginx laeuft NICHT"
    exit 1
fi

if [ "$ICS_OK" = "1" ]; then
    echo "[OK] ICS-Datei erreichbar"
else
    echo "[FEHLER] ICS-Datei nicht erreichbar. Logs: journalctl -u kalender -n 20"
    exit 1
fi

UI_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/sperrtage-ui)
if [ "$UI_CODE" = "200" ]; then
    echo "[OK] Sperrtage-Seite erreichbar"
else
    echo "[FEHLER] Sperrtage-Seite liefert HTTP $UI_CODE"
    exit 1
fi

# ===== Abschluss =====
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "================================================"
echo " Installation erfolgreich!"
echo ""
echo " Web-UI:  http://$IP"
echo " ICS-URL: http://$IP/kalender/heizung.ics"
echo ""
echo " In der CCU eintragen:"
echo " HK1-ICS-Url = http://$IP/kalender/heizung.ics"
echo "================================================"

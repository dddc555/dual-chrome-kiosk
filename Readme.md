Put the kiosk.sh in home directory, and make it executable 

> chmod +x /home/dietpi/kiosk.sh

Run this command to add to auto start

```
mkdir -p /home/dietpi/.config/autostart
cat << 'EOF' > /home/dietpi/.config/autostart/kiosk.desktop
[Desktop Entry]
Type=Application
Name=Dual Chromium Kiosk
Exec=/home/dietpi/kiosk.sh
EOF
```


ログを見る: cat /tmp/kiosk.log

止める: touch /tmp/kiosk-pause && pkill -f chromium

再開する: rm -f /tmp/kiosk-pause

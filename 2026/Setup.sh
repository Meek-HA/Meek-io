######--ADMIN CONTROL CENTER--################################################
apt update
apt install -y inotify-tools
apt install -y curl

echo -n "Admin page install"
mkdir /meek-io/nginx/config/www/admin
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/2026/index.php --output /meek-io/nginx/config/www/admin/index.php

mkdir /meek-io/meek/
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/2026/meek-action-handler.sh --output /meek-io/meek//meek-action-handler.sh
chmod +x /meek-io/meek/meek-action-handler.sh

cat > /etc/systemd/system/meek-action-handler.service <<'EOF'
[Unit]
Description=Meek.io Admin Page Action Handler
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
ExecStart=/meek-io/meek/meek-action-handler.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now meek-action-handler.service

chown -R 1000:1000 /meek-io/meek/commands
chmod 755 /meek-io/meek/commands
chmod 755 /meek-io/meek/commands/settings
chmod 644 /meek-io/meek/commands/settings/current-credentials.txt

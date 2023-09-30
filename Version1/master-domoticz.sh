#!/bin/bash

# 1) Create container in unpriviliged mode , MAX MBPS 3
# 2) Enable container -nesting- & -NFS-
# 3) apt-get install curl -y && curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/master-domoticz.sh --output domoticz.sh && chmod +rwx domoticz.sh && ./domoticz.sh
# 4) Domoticz : Hardware - " MQTT Gateway 127.0.0.1 " , " Autodiscovery Tasmota " , " MEEK DD - P1 port 1886 " Dummy "
#               Settings - " Location - MEEK-IO - Latitude : 51.49955 , Longtitude : 3.61480 " , " Enable Automatic Backup "
#               Security - Networks *.*.*.* , User change admin to Meek Meek
# 5) HomeBridge : install : "edomoticz plugin","homebridge-gsh","homebridge-alexa"

echo Update System
apt-get update -y
apt-get upgrade -y

echo Set TimZone to Europe/Amsterdam
timedatectl set-timezone Europe/Amsterdam

######--NFS Share certificates--################################################
echo NFS Share
apt install nfs-common -y
mkdir -p /mnt/certificate
mount 10.10.10.100:/etc/letsencrypt/archive/  /mnt/certificate

cat << EOF > /etc/fstab
10.10.10.100:/etc/letsencrypt/archive/  /mnt/certificate nfs  defaults 0 0
EOF

######--DOMOTICZ--################################################
echo Install Domoticz
mkdir /home/root
mkdir /home/root/domoticz
mkdir /home/root/domoticz/plugins
cd
wget http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.17_amd64.deb
dpkg -i libssl1.1_1.1.1f-1ubuntu2.17_amd64.deb
bash -c "$(curl -sSfL https://install.domoticz.com)"
#curl -sSfL https://install.domoticz.com --output domo.sh
#sed -i 's+http://www.domoticz.com/download.php?channel=release&type=release&system=${OS}&machine=${MACH}+https://releases.domoticz.com/releases/beta/domoticz_linux_x86_64.tgz+g' domo.sh
#chmod +rwx domo.sh
#./domo.sh
rm libssl1.1_1.1.1f-1ubuntu2.17_amd64.deb
#rm domo.sh

echo Domoticz Service without passwword
touch /etc/systemd/system/domoticz.service
cat << EOF > /etc/systemd/system/domoticz.service
[Unit]
       Description=domoticz_service
[Service]
       User=root
       Group=root
       ExecStart=/home/root/domoticz/domoticz -www 8080 -sslwww 443
       WorkingDirectory=/home/root/domoticz
       Restart=on-failure
       RestartSec=1m
[Install]
       WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable domoticz.service

######--MOSQUITTO--################################################
echo Install Mosquitto
apt-get install mosquitto -y

######--APACHE--################################################
echo Install Apache Webserver
apt-get install apache2 php php-xml php-curl libapache2-mod-php -y
systemctl restart apache2

######--DASHTICZ--################################################
echo Install Dashticz
cd /var/www/html
git clone https://github.com/Dashticz/dashticz

######--NODEJS--################################################
echo Install HomeBridge
curl -sL https://deb.nodesource.com/setup_18.x | sudo bash -
apt-get install -y nodejs gcc g++ make python net-tools
apt-get install -y nodejs git make g++ gcc

######--NODE-RED--################################################
echo Install Node-Red
npm install -g --unsafe-perm node-red node-red-admin
npm install -g pm2
pm2 start /usr/bin/node-red -- -v
pm2 save
pm2 startup systemd
pm2 start node-red

######--ZIGBEE2MQTT--################################################
echo Install/Setup Zigbee2MQTT
git clone https://github.com/Koenkk/zigbee2mqtt.git /opt/zigbee2mqtt
chown -R root:root /opt/zigbee2mqtt
cd /opt/zigbee2mqtt
npm ci

cat << EOF > /opt/zigbee2mqtt/data/configuration.yaml
mqtt:
  base_topic: zigbee2mqtt
  server: 'mqtt://localhost'
serial:
  port: /dev/z2m

advanced:
  network_key: GENERATE
  homeassistant: false
  permit_join: true
frontend:
  port: 9090
EOF

cat << EOF > /etc/systemd/system/zigbee2mqtt.service
[Unit]
Description=zigbee2mqtt
After=network.target
[Service]
ExecStart=/usr/bin/npm start
WorkingDirectory=/opt/zigbee2mqtt
StandardOutput=inherit
StandardError=inherit
Restart=always
RestartSec=10s
User=root
[Install]
WantedBy=multi-user.target
EOF

//systemctl enable zigbee2mqtt.service
//systemctl start zigbee2mqtt

######--ZIGBEE2MQTT DOMOTICZ PLUGIN--################################################
echo Install Domoticz Plugin Zigbee2MQTT
cd /home/root/domoticz/plugins
git clone https://github.com/stas-demydiuk/domoticz-zigbee2mqtt-plugin.git zigbee2mqtt

######--NGINX--################################################
echo Install Nginx
apt install nginx -y
unlink /etc/nginx/sites-enabled/default
systemctl start nginx

######--NGINX--################################################
echo Setup ReverseProxy referrals
cat <<'EOF'> /etc/nginx/sites-enabled/MEEK.conf
#Authorization procedure
server {
listen       81;
#Domoticz forward
location / {
auth_basic "User Login";
auth_basic_user_file /etc/nginx/.htpasswd;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_pass_header Authorization;
proxy_pass http://127.0.0.1:8080;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_buffering off;
client_max_body_size 0;
proxy_read_timeout 36000s;
proxy_redirect off;
}
#Dashticz subpath forwarding
location /dashticz {
auth_basic "User Login";
auth_basic_user_file /etc/nginx/.htpasswd;
proxy_pass_header Authorization;
proxy_pass http://127.0.0.1/dashticz;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_buffering off;
client_max_body_size 0;
proxy_read_timeout 36000s;
proxy_redirect off;
}
}
#Admin panel
server {
listen       82;
auth_basic "Admin Login";
auth_basic_user_file /etc/nginx/.admin;
#Admin subpath forwarding
location /admin {
proxy_pass_header Authorization;
proxy_pass http://127.0.0.1/admin;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_buffering off;
client_max_body_size 0;
proxy_read_timeout 36000s;
proxy_redirect off;
}
}
#Node-RED with Admin credentials
server {
listen 1881;
auth_basic "Admin Login";
auth_basic_user_file /etc/nginx/.admin;
location / {
proxy_pass_header Authorization;
proxy_pass http://127.0.0.1:1880;
proxy_http_version  1.1;
proxy_cache_bypass  $http_upgrade;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Port $server_port;
}
}

#Zigbee2MQTT Frontend with Admin credentials
server {
listen 9091;
auth_basic "Admin Login";
auth_basic_user_file /etc/nginx/.admin;
location / {
        proxy_pass http://127.0.0.1:9090/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
location /api {
        proxy_pass         http://127.0.0.1:9090/api;
        proxy_set_header Host $host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        }
}
EOF

######--ADMIN CONTROL CENTER--################################################
echo -n "Admin page install"
mkdir /var/www/html/admin
mkdir /var/www/html/admin/command
cd /var/www/html/admin
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/admin/index.php --output index.php
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/admin/capw.php --output capw.php
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/admin/cmqtpw.php --output cmqtpw.php
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/admin/cupw.php --output cupw.php
chown -R www-data:www-data /var/www/html/admin

echo -n "ADMIN Command Center for monitoring, controlling and update functions"
apt-get install -y inotify-tools

mkdir /root/MEEK
touch /root/MEEK/monitor.sh
cat << EOF > /root/MEEK/monitor.sh
#!/bin/bash
inotifywait -m -e create -e moved_to -e modify /var/www/html/admin/command|
while read path action file; do
bash /root/MEEK/update.sh
done
EOF

chmod +x /root/MEEK/monitor.sh
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/update.sh --output /root/MEEK/update.sh && chmod +rwx /root/MEEK/update.sh

echo -n "Create cronjob"
touch /root/MEEK/cron
cat << EOF > /root/MEEK/cron
@reboot /root/MEEK/monitor.sh
EOF
crontab /root/MEEK/cron

cat << EOF > /etc/systemd/system/admin.service
[Unit]
Description = Monitor admin directory for file manupilation
[Service]
ExecStart=/bin/bash /root/MEEK/monitor.sh
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable admin.service

######--DOMOTICZ AUTODISCOVERY--################################################
cd /home/root/domoticz/plugins
git clone https://github.com/joba-1/Tasmoticz.git

######--HOMEBRIDGE--################################################
curl -sSfL https://repo.homebridge.io/KEY.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/homebridge.gpg  > /dev/null
echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io stable main" | sudo tee /etc/apt/sources.list.d/homebridge.list > /dev/null
apt-get update -y
apt-get install homebridge -y

######--PYTHON DEV.--################################################
apt-get install python3-dev -y

######--SOCAT / VIRTUAL USB--################################################
apt-get install socat -y
touch /etc/systemd/system/z2m.service
cat << EOF > /etc/systemd/system/z2m.service
[Unit]
Description=Virtual USB Device on port xxxContainerxxx05 for Zigbee2MQTT as USBdevice /dev/z2m
[Service]
ExecStart=/usr/bin/socat pty,raw,echo=0,link=/dev/z2m,mode=777 tcp-listen:xxxContainerxxx05,keepalive,nodelay,reuseaddr,keepidle=1,keepintvl=1,keepcnt=100
Restart=on-failure
RestartSec=2s
[Install]
WantedBy=multi-user.target
EOF

######--DB Manipulation--################################################
apt-get install sqlite3 -y

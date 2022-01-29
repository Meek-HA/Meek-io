#!/bin/bash

# 1) Create container in unpriviliged mode
# 2) Enable container -nesting- & -NFS-
# 3) apt-get install curl -y && curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/server/master-domoticz.sh --output domoticz.sh && chmod +rwx domoticz.sh && ./domoticz.sh
# 4) Domoticz : Hardware - " MQTT Gateway 127.0.0.1 " , " Autodiscovery Tasmota " , " MEEK DD - P1 port 1886 "

echo Update System
apt-get update -y
apt-get upgrade -y

echo Set TimZone to Europe/Amsterdam
timedatectl set-timezone Europe/Amsterdam

######--NFS Share certificates--################################################
echo NFS Share
apt install nfs-common -y
mkdir -p /mnt/certificate
mount 10.10.10.100:/etc/letsencrypt/live/  /mnt/certificate

cat << EOF > /etc/fstab
10.10.10.100:/etc/letsencrypt/live/  /mnt/certificate nfs  defaults 0 0
EOF

######--DOMOTICZ--################################################
echo Install Domoticz
mkdir /home/root
mkdir /home/root/domoticz
mkdir /home/root/domoticz/plugins
curl -sSL install.domoticz.com | sudo bash

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
git clone https://github.com/Dashticz/dashticz --branch beta

######--HOMEBRIDGE--################################################
echo Install HomeBridge
curl -sL https://deb.nodesource.com/setup_14.x | sudo bash -
apt-get install -y nodejs gcc g++ make python net-tools
npm install -g --unsafe-perm homebridge homebridge-config-ui-x
hb-service install --user homebridge
echo Install HomeBridge edomoticz plugin
npm install -g homebridge-edomoticz
echo Install HomeBridge to Google Smart Home plugin
npm install -g homebridge-gsh
echo Install HomeBridge Alexa plugin
npm install -g homebridge-alexa
rm /var/lib/homebridge/config.json

######--NODE-RED--################################################
echo Install Node-Red
npm install -g --unsafe-perm node-red node-red-admin
npm install -g pm2
pm2 start /usr/bin/node-red -- -v
pm2 save
pm2 startup systemd
pm2 start node-red

##Tasmote MQTT-DSMR to Domoticz-P1-Lan
curl https://raw.githubusercontent.com/Meek-HA/Tasmota/main/DSMR-Parser.json --output /root/MEEK/DSMR-Parser.json
curl -X POST http://localhost:1880/flows -H 'content-type: application/json' -d @/root/MEEK/DSMR-Parser.json

######--ZIGBEE2MQTT--################################################
echo Install/Setup Zigbee2MQTT
apt-get install -y nodejs git make g++ gcc
git clone https://github.com/Koenkk/zigbee2mqtt.git /opt/zigbee2mqtt
chown -R root:root /opt/zigbee2mqtt
cd /opt/zigbee2mqtt
npm ci

cat << EOF > /opt/zigbee2mqtt/data/configuration.yaml
mqtt:
  base_topic: zigbee2mqtt
  server: 'mqtt://localhost'
serial:
  port: 'tcp://localhost:1775'
  
advanced:
  network_key: GENERATE
homeassistant: false
permit_join: true
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
User=root
[Install]
WantedBy=multi-user.target
EOF

systemctl enable zigbee2mqtt.service
systemctl start zigbee2mqtt

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
auth_basic "User Login";
auth_basic_user_file /etc/nginx/.htpasswd;
#Domoticz forward
location / {
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

#Proxywith Admin credentials
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
EOF

######--ADMIN CONTROL CENTER--################################################
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

echo -n "Create cronjob"
touch /root/MEEK/cron
cat << EOF > /root/MEEK/cron
@reboot /root/MEEK/monitor.sh
EOF
crontab /root/MEEK/cron

######--DOMOTICZ AUTODISCOVERY--################################################
cd /home/root/domoticz/plugins
git clone https://github.com/joba-1/Tasmoticz.git

######--PYTHON DEV.--################################################
apt-get install python3-dev -y

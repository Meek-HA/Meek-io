#!/bin/bash

# 1) Create container in unpriviliged mode
# 2) Enable container -nesting- & -NFS-

echo Update System
apt-get update -y
apt-get upgrade -y

echo Set TimZone to Europe/Amsterdam
timedatectl set-timezone Europe/Amsterdam

echo Install CurL
apt install curl -y

######--NFS Share certificates--################################################
echo NFS Share
apt install nfs-common -y
mkdir -p /mnt/certificate
mount reverseproxy:/mnt/certificate  /mnt/certificate

cat << EOF > /etc/fstab
reverseproxy:/mnt/certificate  /mnt/certificate nfs  defaults 0 0
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

######--ADMIN CONTROL CENTER--################################################
echo -n "ADMIN Command Center for monitoring, controlling and update functions"
apt-get install -y inotify-tools

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

apt-get install python3-dev -y

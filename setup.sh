#!/bin/bash

echo Update System
apt-get update -y
apt-get upgrade -y

echo Install CurL
apt install curl -y

echo Set TimZone to Europe/Amsterdam
timedatectl set-timezone Europe/Amsterdam

######--DOMOTICZ--################################################
echo Install Domoticz
mkdir /home/root
mkdir /home/root/domoticz
curl -sSL install.domoticz.com | sudo bash

######--MOSQUITTO--################################################
echo Install Mosquitto
apt-get install mosquitto -y
rm /etc/mosquitto/conf.d/default.conf
touch /etc/mosquitto/conf.d/default.conf
cat << EOF > /etc/mosquitto/conf.d/default.conf
per_listener_settings true
port 1883 localhost

listener 1884
allow_anonymous false
password_file /etc/mosquitto/passwd
certfile /etc/letsencrypt/live/$(hostname).meek-io.com/cert.pem
cafile /etc/letsencrypt/live/$(hostname).meek-io.com/chain.pem
keyfile /etc/letsencrypt/live/$(hostname).meek-io.com/privkey.pem
EOF

mkdir -p /etc/letsencrypt/live/$(hostname).meek-io.com
mkdir -p /root/MEEK
touch /root/MEEK/cert-sync.sh
cat << EOF > /root/MEEK/cert-sync.sh
curl http://reverseproxy:100/cert-sync/live/$(hostname).meek-io.com/cert.pem --output /etc/letsencrypt/live/$(hostname).meek-io.com/cert.pem
curl http://reverseproxy:100/cert-sync/live/$(hostname).meek-io.com/cert.pem --output /etc/letsencrypt/live/$(hostname).meek-io.com/chain.pem
curl http://reverseproxy:100/cert-sync/live/$(hostname).meek-io.com/cert.pem --output /etc/letsencrypt/live/$(hostname).meek-io.com/privkey.pem
EOF

chmod +rwx /root/MEEK/cert-sync.sh

######--HOMEBRIDGE--################################################
echo Install HomeBridge
curl -sL https://deb.nodesource.com/setup_12.x | sudo bash -
sudo apt-get install -y nodejs gcc g++ make python
npm install -g --unsafe-perm homebridge homebridge-config-ui-x
hb-service install --user homebridge
echo Install HomeBridge edomoticz plugin
npm install -g homebridge-edomoticz
echo Install HomeBridge to Google Smart Home plugin
npm install -g homebridge-gsh
echo Install HomeBridge Alexa plugin
npm install -g homebridge-alexa

######--APACHE--################################################
echo Install Apache Webserver
apt-get install apache2 php php-xml php-curl libapache2-mod-php -y
systemctl restart apache2

######--DASHTICZ--################################################
echo Install Dashticz
cd /var/www/html
git clone https://github.com/Dashticz/dashticz --branch beta
cd dashticz/custom/
cp CONFIG_DEFAULT.js CONFIG.js
sed -i "/domoticz_ip/c\config['domoticz_ip'] = 'https://$(hostname).meek-io.com';" CONFIG.js
cd

######--NODE-RED--################################################
echo Install Node-Red
npm install -g --unsafe-perm node-red node-red-admin
npm install -g pm2
pm2 start /usr/bin/node-red -- -v
pm2 save
pm2 startup systemd

######--ZIGBEE2MQTT--################################################
echo Install/Setup Zigbee2MQTT
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
apt-get install -y nodejs git make g++ gcc
git clone https://github.com/Koenkk/zigbee2mqtt.git /opt/zigbee2mqtt
chown -R root:root /opt/zigbee2mqtt
cd /opt/zigbee2mqtt
npm ci

cat << EOF > /opt/zigbee2mqtt/data/configuration.yaml
homeassistant: false
permit_join: true
mqtt:
base_topic: zigbee2mqtt
server: 'mqtt://localhost'
serial:
port: 'tcp://localhost:1775'
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
sed -i 's/80 default_server;/85 default_server;/g' /etc/nginx/sites-enabled/default
systemctl start nginx

######--CONFIGURATION--################################################
echo Configuration and Settings

echo Disable Domoticz caching
sed -i 's/<html manifest="html5.appcache">/<!-- <html manifest="html5.appcache"> -->/g' /home/root/domoticz/www/index.html

echo Configuration File for reverse Proxy into Domoticz & Dashticz
cat <<'EOF'> /etc/nginx/sites-enabled/MEEK.conf
# xxxxxx = subdomain

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
proxy_pass http://xxxxxx:1880;
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

hs=`hostname`
echo "Your hostname is:" $hs

echo -n "Enter username and password for user account:"
read NAME
echo "Your username is:" $NAME
rm /etc/nginx/.htpasswd
sh -c "echo -n "${NAME}:" >> /etc/nginx/.htpasswd"
sh -c "openssl passwd -apr1 >> /etc/nginx/.htpasswd"

echo -n "Enter username and password for admin account:"
read NAME
echo "Your username is:" $NAME
rm /etc/nginx/.admin
sh -c "echo -n "${NAME}:" >> /etc/nginx/.admin"
sh -c "openssl passwd -apr1 >> /etc/nginx/.admin"

sed -i -e "s/xxxxxx/$(hostname)/g" /etc/nginx/sites-enabled/MEEK.conf

echo -n "Enter username and password for Mosquitto:"
read NAME
echo "Your username is:" $NAME
mosquitto_passwd -c /etc/mosquitto/passwd $NAME

echo -n "Admin page"
git clone https://github.com/Meek-HA/Meek.io-admin.git /var/www/html/admin
chown -R www-data:www-data /var/www/html/admin

echo -n "Create cronjob"
touch /root/MEEK/cron
cat << EOF > cron
* * * * * /bin/sh /root/MEEK/update.sh
7 */12 * * * /bin/sh /root/MEEK/cert-sync.sh
EOF
crontab /root/MEEK/cron

curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/update.sh --output /root/MEEK/update.sh && chmod +rwx /root/MEEK/update.sh

echo -n "Reboot !:"
reboot

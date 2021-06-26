#!/bin/bash

echo Update System
apt-get update -y
apt-get upgrade -y

echo Install CurL
apt install curl -y

echo Set TimZone to Europe/Amsterdam
timedatectl set-timezone Europe/Amsterdam

######--Set Domain--################################################
echo Select Domain Name
prompt="Select Domain:"
options=("meek-io.com" "mymeek.org")
PS3="$prompt "
select opt in "${options[@]}" "Quit"; do
    case "$REPLY" in
    1) echo "You picked $opt which is option 1"; domn=$opt; break;;
    2) echo "You picked $opt which is option 2"; domn=$opt; break;;
    $((${#options[@]}+1))) echo "TOP!"; break;;
    *) echo "Invalid input. Try again!";continue;;
    esac
done

######--DOMOTICZ--################################################
echo Install Domoticz
mkdir /home/root
mkdir /home/root/domoticz
mkdir /home/root/domoticz/plugins
curl -sSL install.domoticz.com | sudo bash

######--MOSQUITTO--################################################
echo Install Mosquitto
apt-get install mosquitto -y
rm /etc/mosquitto/conf.d/default.conf
touch /etc/mosquitto/conf.d/default.conf
cat << EOF > /etc/mosquitto/conf.d/default.conf
per_listener_settings true
listener 1883 localhost
listener 1884
allow_anonymous false
password_file /etc/mosquitto/passwd
listener 1885
allow_anonymous false
password_file /etc/mosquitto/passwd
certfile /etc/mosquitto/certs/cert.pem
cafile /etc/mosquitto/certs/chain.pem
keyfile /etc/mosquitto/certs/privkey.pem
EOF

mkdir -p /root/MEEK
touch /root/MEEK/cert-sync.sh
cat << EOF > /root/MEEK/cert-sync.sh
curl http://reverseproxy:100/cert-sync/live/$(hostname).meek-io.com/cert.pem --output /etc/mosquitto/certs/cert.pem
curl http://reverseproxy:100/cert-sync/live/$(hostname).meek-io.com/chain.pem --output /etc/mosquitto/certs/chain.pem
curl http://reverseproxy:100/cert-sync/live/$(hostname).meek-io.com/privkey.pem --output /etc/mosquitto/certs/privkey.pem
EOF

chmod +rwx /root/MEEK/cert-sync.sh

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
sed -i 's/config/config"\n      },\n    {\n     "name": "Domoticz",\n   "server": "127.0.0.1",\n        "port": "8080",\n       "roomid": 0,\n  "mqtt": 0,\n    "ssl": false,\n "dimFix": 0,\n  "platform": "eDomoticz/g' /var/lib/homebridge/config.json


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
sed -i "/domoticz_ip/c\config['domoticz_ip'] = 'https://$(hostname)."$opt"';" /var/www/html/dashticz/custom/CONFIG.js
cd

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
# curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
# apt-get install -y nodejs git make g++ gcc
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
cat << EOF > /root/MEEK/cron
* * * * * /bin/sh /root/MEEK/update.sh
7 */12 * * * /bin/sh /root/MEEK/cert-sync.sh
EOF
crontab /root/MEEK/cron

curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/update.sh --output /root/MEEK/update.sh && chmod +rwx /root/MEEK/update.sh
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/MEEK-DD-TMP.json --output /root/MEEK/MEEK-DD-TMP.json
curl -X POST http://localhost:1880/flows -H 'content-type: application/json' -d @/root/MEEK/MEEK-DD-TMP.json

read -r -p "Make sure that on the Reverse Proxy server, the Letsencrypt certificates are available, after that press any key to sync the certificates." key
bash /root/MEEK/cert-sync.sh

apt-get install python3-dev -y

echo -n "Reboot !:"
reboot

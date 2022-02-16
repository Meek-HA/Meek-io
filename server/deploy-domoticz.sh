#!/bin/bash

# curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/server/deploy-domoticz.sh --output deploy-domoticz.sh && chmod +rwx deploy-domoticz.sh && ./deploy-domoticz.sh

######--Set Sub-Domain--################################################
echo -n "Enter Container-,Subdomain name : "
read NAME

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

######--MOSQUITTO--################################################
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
certfile /mnt/certificate/$NAME.$opt/cert.pem
cafile /mnt/certificate/$NAME.$opt/chain.pem
keyfile /mnt/certificate/$NAME.$opt/privkey.pem
EOF

touch /root/user
ip4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
echo $ip4 >> /root/user
echo "$NAME"."$opt" >> /root/user
mv /root/user /mnt/certificate/deploy/user

######--Homebridge--################################################
npm install -g --unsafe-perm homebridge homebridge-config-ui-x
hb-service install --user homebridge
echo Install HomeBridge edomoticz plugin
npm install -g homebridge-edomoticz
echo Install HomeBridge to Google Smart Home plugin
npm install -g homebridge-gsh
echo Install HomeBridge Alexa plugin
npm install -g homebridge-alexa
sed -i 's/config/config"\n      },\n    {\n     "name": "Domoticz",\n   "server": "127.0.0.1",\n        "port": "8080",\n       "roomid": 0,\n  "mqtt": 0,\n    "ssl": false,\n "dimFix": 0,\n  "platform": "eDomoticz/g' /var/lib/homebridge/config.json

######--Username & PasswordD Generation--################################################
echo -n "Enter username and password for user account:"
read NAME
echo "Your username is:" $NAME
rm -f /etc/nginx/.htpasswd
sh -c "echo -n "${NAME}:" >> /etc/nginx/.htpasswd"
sh -c "openssl passwd -apr1 >> /etc/nginx/.htpasswd"

echo -n "Enter username and password for admin account:"
read NAME
echo "Your username is:" $NAME
rm -f /etc/nginx/.admin
sh -c "echo -n "${NAME}:" >> /etc/nginx/.admin"
sh -c "openssl passwd -apr1 >> /etc/nginx/.admin"

echo -n "Enter username and password for Mosquitto:"
read NAME
echo "Your username is:" $NAME
mosquitto_passwd -c /etc/mosquitto/passwd $NAME

echo -n "In container -- Reverse Proxy --, execute  ./cert.sh  !"

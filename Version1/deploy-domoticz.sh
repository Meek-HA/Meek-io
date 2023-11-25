#!/bin/bash

# curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/deploy-domoticz.sh --output deploy-domoticz.sh && chmod +rwx deploy-domoticz.sh && ./deploy-domoticz.sh
apt-get update -y

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
allow_anonymous true
listener xxxContainerxxx01
allow_anonymous false
password_file /etc/mosquitto/passwd
listener xxxContainerxxx02
allow_anonymous false
password_file /etc/mosquitto/passwd
certfile /mnt/certificate/$NAME.$opt/cert1.pem
cafile /mnt/certificate/$NAME.$opt/chain1.pem
keyfile /mnt/certificate/$NAME.$opt/privkey1.pem
EOF

touch /root/user
ip4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
echo $ip4 >> /root/user
echo "$NAME"."$opt" >> /root/user
mv /root/user /mnt/certificate/deploy/user
Container="${ip4##*.}"
sed -i -e "s/xxxContainerxxx/$Container/g" /etc/mosquitto/conf.d/default.conf

######--Node-Red--################################################
pm2 start /usr/bin/node-red -- -v
pm2 save
pm2 startup systemd
pm2 start node-red

######--Socat Zigbee2MQTT--################################################
sed -i -e "s/xxxContainerxxx/$Container/g" /etc/systemd/system/z2m.service
sed -i -e "s/xxxContainerxxx/$Container/g" /etc/systemd/system/dsmr.service

######--Homebridge--################################################
rm /var/lib/homebridge/config.json
hb-service restart
wait
sleep 15
sed -i 's/config/config"\n      },\n    {\n     "name": "Domoticz",\n   "server": "127.0.0.1",\n        "port": "8080",\n       "roomid": 0,\n  "mqtt": true,\n    "ssl": false,\n "dimFix": 0,\n  "platform": "eDomoticz/g' /var/lib/homebridge/config.json

######--Username & PasswordD Generation--################################################
#-Update Admin center
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/admin/index.php --output /var/www/html/admin/index.php
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/admin/capw.php --output /var/www/html/admin/capw.php
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/admin/cmqtpw.php --output /var/www/html/admin/cmqtpw.php
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/admin/cupw.php --output /var/www/html/admin/cupw.php
chown -R www-data:www-data /var/www/html/admin
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/update.sh --output /root/MEEK/update.sh && chmod +rwx /root/MEEK/update.sh

echo -n "Enter username and password for USER account:"
echo
read NAMEU
echo "Your username is:" $NAMEU
read -s -p "Password: " PASSU; echo
rm /root/MEEK/cup
echo $NAMEU >> /root/MEEK/cup
echo $PASSU >> /root/MEEK/cup
mv /root/MEEK/cup /var/www/html/admin/command/cup

echo -n "Enter username and password for ADMIN account:"
echo
read NAMEA
echo "Your username is:" $NAMEA
read -s -p "Password: " PASSA; echo
rm /root/MEEK/cap
echo $NAMEA >> /root/MEEK/cap
echo $PASSA >> /root/MEEK/cap
mv /root/MEEK/cap /var/www/html/admin/command/cap

echo -n "Enter username and password for MQTT account:"
echo
read NAMEMQT
echo "Your username is:" $NAMEMQT
read -s -p "Password: " PASSMQT; echo
rm /root/MEEK/cmqtp
echo $NAMEMQT >> /root/MEEK/cmqtp
echo $PASSMQT >> /root/MEEK/cmqtp
mv /root/MEEK/cmqtp /var/www/html/admin/command/cmqtp

######--Tasmote MQTT-DSMR to Domoticz-P1-Lan--################################################
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/Meek.json --output /root/MEEK/Meek.json
echo .
echo ..
echo ...
echo ....
echo .....
echo ......
echo .......
echo ........
echo .........
echo ..........
sed -i -e "s/xxxContainerxxx/$Container/g" /root/MEEK/Meek.json
sed -i -e "s/zzzDomainzzz/$NAME.$opt/g" /root/MEEK/Meek.json
rm /root/MEEK/NRA
echo $(curl http://localhost:1880/auth/token --data 'client_id=node-red-admin&grant_type=password&scope=*&username='${NAMEA}'&password='$PASSA'') >> /root/MEEK/NRA
sed -e 's+{"access_token":"++g' -i /root/MEEK/NRA
sed -e 's+",".*++g' -i /root/MEEK/NRA
NRA="$(tail -1 /root/MEEK/NRA)"
curl -X POST http://localhost:1880/flows -H 'content-type: application/json' -H 'Authorization: Bearer '$NRA'' -d @/root/MEEK/Meek.json


##########----Admin MQTT port details
echo MQTT-Port : $(ip -o addr show dev "eth0" | awk '$3 == "inet" {print $4}' | sed -r 's!/.*!!; s!.*\.!!')01 >> /var/www/html/admin/port
echo MQTTS-Port : $(ip -o addr show dev "eth0" | awk '$3 == "inet" {print $4}' | sed -r 's!/.*!!; s!.*\.!!')02 >> /var/www/html/admin/port

echo -n "In container -- Reverse Proxy --, execute ./deploy-reverseproxy.sh and then ./cert.sh  !"

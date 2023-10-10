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

######--Socat Zigbee2MQTT--################################################
sed -i -e "s/xxxContainerxxx/$Container/g" /etc/systemd/system/z2m.service

######--Homebridge--################################################
rm /var/lib/homebridge/config.json
hb-service restart
wait
sleep 15
sed -i 's/config/config"\n      },\n    {\n     "name": "Domoticz",\n   "server": "127.0.0.1",\n        "port": "8080",\n       "roomid": 0,\n  "mqtt": true,\n    "ssl": false,\n "dimFix": 0,\n  "platform": "eDomoticz/g' /var/lib/homebridge/config.json

######--Node-Red--################################################
pm2 start /usr/bin/node-red -- -v
pm2 save
pm2 startup systemd
pm2 start node-red

######--Username & PasswordD Generation--################################################
echo -n "Enter username and password for user account:"
read NAMEU
echo "Your username is:" $NAMEU
read -s -p "Password: " PASSU; echo
rm -f /etc/nginx/.htpasswd
printf "${NAMEU}:$(openssl passwd -apr1 ${PASSU})\n" >> /etc/nginx/.htpasswd
##Set Domoticz Databse Username and Password
        authuser=$(echo -ne "$NAMEU" | base64);
        authpass=$(echo -ne "$PASSU" | md5sum | awk '{print $1}');
        sqlite3 /home/root/domoticz/domoticz.db 'DELETE FROM Users WHERE ROWID=1'
        sqlite3 /home/root/domoticz/domoticz.db 'INSERT INTO Users VALUES("1","1","'$authuser'","'$authpass'","","2","127","1");'


echo -n "Enter username and password for admin account:"
echo 
read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD; echo
printf "${USERNAME}:$(openssl passwd -apr1 ${PASSWORD})\n" >> /etc/nginx/.admin


echo -n "Enter username and password for Mosquitto:"
read NAME
echo "Your username is:" $NAME
mosquitto_passwd -c /etc/mosquitto/passwd $NAME

Echo Homebridge Admin Credentials update
                rm /var/lib/homebridge/auth.json
                echo .
                echo ..
                echo ...
                curl -X 'POST' \
                        'http://127.0.0.1:8581/api/setup-wizard/create-first-user' \
                        -H 'accept: */*' \
                        -H 'Content-Type: application/json' \
                        -d '{
                        "name": "Meek",
                        "username": "'$USERNAME'",
                        "admin": true,
                        "password": "'$PASSWORD'"
                        }'
                hb-service restart


##Tasmote MQTT-DSMR to Domoticz-P1-Lan
curl https://raw.githubusercontent.com/Meek-HA/Tasmota/main/Meek.json --output /root/MEEK/Meek.json
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
curl -X POST http://localhost:1880/flows -H 'content-type: application/json' -d @/root/MEEK/Meek.json
sed -i -e "s/xxxContainerxxx/$Container/g" /root/MEEK/Meek.json
sed -i -e "s/zzzDomainzzz/$NAME.$opt/g" /root/MEEK/Meek.json

echo -n "In container -- Reverse Proxy --, execute  ./cert.sh  !"

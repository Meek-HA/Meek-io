#!/bin/bash

#Check if file --updating-- exist for more than 4 min. If so, delete this file.
FILE=/var/www/html/admin/command/updating
if [ -f "$FILE" ];
        then
        if test `find "/var/www/html/admin/command/updating" -mmin +4`
        then
        echo $(date -u) "Deleting updating file" >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/updating
        fi
fi

#Check if file --updating-- exists and if so, than break this bash script.
FILE=/var/www/html/admin/command/updating
if [ -f "$FILE" ];
        then
        echo $(date -u) "Updating in progress, breaking bash." >> /root/MEEK/log.txt
        exit
fi

#Check if file --dashticz-- exists and if so, update dashticz.
FILE=/var/www/html/admin/command/dashticz-update
if [ -f "$FILE" ];
        then
        touch /var/www/html/admin/command/updating
        echo $(date -u) "dashticz exists." >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/dashticz-update
        echo $(date -u) "dashticz file deleted." >> /root/MEEK/log.txt
        cd /var/www/html/dashticz
        git pull
        cd
        rm /var/www/html/admin/command/updating
fi

#Check if file --zigbee2mqtt-- exists and if so, update zigbee2mqtt
FILE=/var/www/html/admin/command/zigbee2mqtt-update
if [ -f "$FILE" ];
        then
        touch /var/www/html/admin/command/updating
        echo $(date -u) "Zigbee2Mqtt exists." >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/zigbee2mqtt-update
        echo $(date -u) "Zigbee2Mqtt file deleted." >> /root/MEEK/log.txt
        systemctl stop zigbee2mqtt
        cd /opt/zigbee2mqtt
        cp -R data data-backup
        git checkout HEAD -- npm-shrinkwrap.json
        git pull
        npm ci
        cp -R data-backup/* data
        rm -rf data-backup
        systemctl start zigbee2mqtt
        cd
        rm /var/www/html/admin/command/updating
        echo $(date -u) "Zigbee2Mqtt has been updated to the latest version." >> /root/MEEK/log.txt
fi

#Check if file --cap-- exists and if so, update -ADMIN- credentials.
FILE=/var/www/html/admin/command/cap
if [ -f "$FILE" ];
         then
                rm /etc/nginx/.admin
                touch /etc/nginx/.admin
                sh -c "echo -n ":" >> /etc/nginx/.admin"
                changeusername="$(head -1 /var/www/html/admin/command/cap)"
                changepassword="$(tail -1 /var/www/html/admin/command/cap)"
                rm /var/www/html/admin/command/cap
                hashpass=$(echo $(openssl passwd -apr1 $changepassword))
                sed -i "/:/c\\$changeusername:$hashpass" /etc/nginx/.admin
              #Homebridge Admin Credentials update
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
                        "username": "'$changeusername'",
                        "admin": true,
                        "password": "'$changepassword'"
                        }'
                hb-service restart
               #Node-Red Admin Credentials update
                nodepass=$(echo $(node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 8));" $changepassword))
                sed -i '/password:/c\password: "'${nodepass}'",' /root/.node-red/settings.js
                sed -i '/username:/c\username: "'${changeusername}'",' /root/.node-red/settings.js
                pm2 restart node-red
              echo $(date -u) "Admin Credentiels are updated." >> /root/MEEK/log.txt
fi

#Check if file --cup-- exists and if so, update -USER- credentials.
FILE=/var/www/html/admin/command/cup
if [ -f "$FILE" ];
        then
        rm /etc/nginx/.htpasswd
        NAMEU="$(head -1 /var/www/html/admin/command/cup)"
        PASSU="$(tail -1 /var/www/html/admin/command/cup)"
        printf "${NAMEU}:$(openssl passwd -apr1 ${PASSU})\n" >> /etc/nginx/.htpasswd
        authuser=$(echo -ne "$NAMEU" | base64);
        authpass=$(echo -ne "$PASSU" | md5sum | awk '{print $1}');
        sqlite3 /home/root/domoticz/domoticz.db 'DELETE FROM Users WHERE ROWID=1'
        sqlite3 /home/root/domoticz/domoticz.db 'INSERT INTO Users VALUES("1","1","'$authuser'","'$authpass'","","2","127","1");'
        rm /var/www/html/admin/command/cup
        service domoticz restart
        echo $(date -u) "User Credentiels are updated." >> /root/MEEK/log.txt
fi

#Check if file --cmqtp-- exists and if so, update -MQTT- credentials.
FILE=/var/www/html/admin/command/cmqtp
if [ -f "$FILE" ];
        then
        mosquitto_passwd -U /var/www/html/admin/command/cmqtp
        rm /etc/mosquitto/passwd
        mv /var/www/html/admin/command/cmqtp /etc/mosquitto/passwd
        service mosquitto restart
        echo $(date -u) "MQTT Credentials are updated." >> /root/MEEK/log.txt
fi

#Check if file --domoticz-stop-- exists and if so, STOP Domoticz.
FILE=/var/www/html/admin/command/domoticz-stop
if [ -f "$FILE" ];
        then
        /etc/init.d/domoticz.sh stop
        echo $(date -u) "Stop Domoticz Service." >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/domoticz-stop
        echo $(date -u) "domoticz-stop file deleted." >> /root/MEEK/log.txt
fi

#Check if file --domoticz-start-- exists and if so, START Domoticz.
FILE=/var/www/html/admin/command/domoticz-start
if [ -f "$FILE" ];
        then
        /etc/init.d/domoticz.sh start
        echo $(date -u) "Start Domoticz Service." >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/domoticz-start
        echo $(date -u) "domoticz-start file deleted." >> /root/MEEK/log.txt
fi

#Check if file --domoticz-restart-- exists and if so, RESTART Domoticz.
FILE=/var/www/html/admin/command/domoticz-restart
if [ -f "$FILE" ];
        then
        /etc/init.d/domoticz.sh restart
        echo $(date -u) "Restart Domoticz Service." >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/domoticz-restart
        echo $(date -u) "domoticz-restart file deleted." >> /root/MEEK/log.txt
fi

#Check --Zigbee2mqtt-start--
FILE=/var/www/html/admin/command/Zigbee-Start
if [ -f "$FILE" ];
        then
        touch /var/www/html/admin/command/updating
        service z2m restart
        systemctl start zigbee2mqtt
        echo $(date -u) "zigbee2mqtt start." >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/Zigbee-Start
        rm /var/www/html/admin/command/updating
        echo $(date -u) "zigbee2mqtt-start file deleted." >> /root/MEEK/log.txt
fi

#Check --Zigbee2mqtt-stop--
FILE=/var/www/html/admin/command/Zigbee-Stop
if [ -f "$FILE" ];
        then
        touch /var/www/html/admin/command/updating
        systemctl stop zigbee2mqtt
        echo $(date -u) "zigbee2mqtt stop." >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/Zigbee-Stop
        rm /var/www/html/admin/command/updating
        echo $(date -u) "zigbee2mqtt-stop file deleted." >> /root/MEEK/log.txt
fi

#Check --System-Update--
FILE=/var/www/html/admin/command/System-Update
if [ -f "$FILE" ];
        then
        touch /var/www/html/admin/command/updating
        curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/update.sh --output /root/MEEK/update.sh && chmod +rwx /root/MEEK/update.sh
        echo $(date -u) "System-Update start." >> /root/MEEK/log.txt
        rm /var/www/html/admin/command/System-Update
        rm /var/www/html/admin/command/updating
        echo $(date -u) "System-Update completed." >> /root/MEEK/log.txt
fi

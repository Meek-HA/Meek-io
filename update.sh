#!/bin/bash

#Check if file --updating-- exist for more than 4 min. If so, delete this file.
FILE=/var/www/html/admin/command/updating
if [ -f "$FILE" ];
       then
              if test `find "/var/www/html/admin/command/updating" -mmin +4`
                     then
                     touch log.txt
                     echo $(date -u) "Deleting updating file" >> /root/MEEK/log.txt
                     rm /var/www/html/admin/command/updating
              fi
fi

#Check if file --updating-- exists and if so, than break this bash script.
FILE=/var/www/html/admin/command/updating
if [ -f "$FILE" ];
       then
              touch log.txt
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
              touch log.txt
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
              rm /etc/nginx/.htpasswd
              changeusername="$(head -1 /var/www/html/admin/command/cap)"
              echo "$changeusername"
              changepassword="$(tail -1 /var/www/html/admin/command/cap)"
              echo "$changepassword"
              sh -c "echo -n "$changeusername:" >> /etc/nginx/.htpasswd"
              sh -c "openssl passwd -apr1 $changepassword >> /etc/nginx/.htpasswd"
              rm /var/www/html/admin/command/cap
              echo $(date -u) "Admin Credentiels are updated." >> /root/MEEK/log.txt
fi

#Check if file --cup-- exists and if so, update -USER- credentials.
FILE=/var/www/html/admin/command/cup
if [ -f "$FILE" ];
         then
              rm /etc/nginx/.admin
              changeusername="$(head -1 /var/www/html/admin/command/cup)"
              echo "$changeusername"
              changepassword="$(tail -1 /var/www/html/admin/command/cup)"
              echo "$changepassword"
              sh -c "echo -n "$changeusername:" >> /etc/nginx/.admin"
              sh -c "openssl passwd -apr1 $changepassword >> /etc/nginx/.admin"
              rm /var/www/html/admin/command/cup
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
              touch log.txt
              echo $(date -u) "Stop Domoticz Service." >> /root/MEEK/log.txt
              rm /var/www/html/admin/command/domoticz-stop
              echo $(date -u) "domoticz-stop file deleted." >> /root/MEEK/log.txt
fi

#Check if file --domoticz-start-- exists and if so, START Domoticz.
FILE=/var/www/html/admin/command/domoticz-start
if [ -f "$FILE" ];
         then
              /etc/init.d/domoticz.sh start
              touch log.txt
              echo $(date -u) "Start Domoticz Service." >> /root/MEEK/log.txt
              rm /var/www/html/admin/command/domoticz-start
              echo $(date -u) "domoticz-start file deleted." >> /root/MEEK/log.txt
fi

#Check if file --domoticz-restart-- exists and if so, RESTART Domoticz.
FILE=/var/www/html/admin/command/domoticz-restart
if [ -f "$FILE" ];
       then
              /etc/init.d/domoticz.sh restart
              touch log.txt
              echo $(date -u) "Restart Domoticz Service." >> log.tx
              rm /var/www/html/admin/command/domoticz-restart
              echo $(date -u) "domoticz-restart file deleted." >> /root/MEEK/log.txtt
fi

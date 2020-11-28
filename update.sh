#!/bin/bash

#Check if file --updating-- exist for more than 4 min. If so, delete this file.
FILE=/var/www/html/admin/updating
if [ -f "$FILE" ];
then
if test `find "/var/www/html/dashticz/Update/updating" -mmin +4`
        then
        touch log.txt
        echo Deleting updating file >> log.txt
        rm /var/www/html/admin/updating
fi
fi

#Check if file --updating-- exists and if so, than break this bash script.
FILE=/var/www/html/admin/updating
if [ -f "$FILE" ];
         then
          touch log.txt
          echo "Updating in progress, breaking bash." >> log.txt
          exit
fi

#Check if file --dashticz-- exists and if so, update dashticz.
FILE=/var/www/html/admin/dashticz-update
if [ -f "$FILE" ];
         then
                touch /var/www/html/admin/updating
                echo "dashticz exists." >> log.txt
                rm /var/www/html/admin/dashticz-update
                echo "dashticz file deleted." >> log.txt
                cd /var/www/html/dashticz
                git pull
                cd
                rm /var/www/html/admin/updating
fi

#Check if file --zigbee2mqtt-- exists and if so, update zigbee2mqtt
FILE=/var/www/html/admin/zigbee2mqtt-update
if [ -f "$FILE" ];
        then
                touch /var/www/html/admin/updating
                echo "Zigbee2Mqtt exists." >> log.txt
                rm /var/www/html/admin/zigbee2mqtt-update
                touch log.txt
                echo "Zigbee2Mqtt file deleted." >> log.txt
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
                rm /var/www/html/admin/updating
                echo "Zigbee2Mqtt has been updated to the latest version." >> log.txt
fi

#Check if file --cap-- exists and if so, update -ADMIN- credentials.
FILE=/var/www/html/admin/cap
if [ -f "$FILE" ];
         then
                rm /etc/nginx/.htpasswd
                changeusername="$(head -1 /var/www/html/admin/cap)"
                echo "$changeusername"
                changepassword="$(tail -1 /var/www/html/admin/cap)"
                echo "$changepassword"
                sh -c "echo -n "$changeusername:" >> /etc/nginx/.htpasswd"
                sh -c "openssl passwd -apr1 $changepassword >> /etc/nginx/.htpasswd"
                rm /var/www/html/admin/cap
fi

#Check if file --cup-- exists and if so, update -USER- credentials.
FILE=/var/www/html/admin/cup
if [ -f "$FILE" ];
         then
                rm /etc/nginx/.admin
                changeusername="$(head -1 /var/www/html/admin/cup)"
                echo "$changeusername"
                changepassword="$(tail -1 /var/www/html/admin/cup)"
                echo "$changepassword"
                sh -c "echo -n "$changeusername:" >> /etc/nginx/.admin"
                sh -c "openssl passwd -apr1 $changepassword >> /etc/nginx/.admin"
                rm /var/www/html/admin/cup
fi


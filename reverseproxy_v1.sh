#!/bin/bash

echo -n "Enter subdomain name : "
read NAME

cat <<'EOF'> /etc/nginx/sites-enabled/$NAME.conf

# xxxxxx = subdomain

server {
listen 80;
server_name xxxxxx.meek-io.com;
return 301 https://$host$request_uri;
}

server {
listen       443 ssl http2;
server_name xxxxxx.meek-io.com;


#Domoticz server in de Root
location / {
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_pass_header Authorization;
proxy_pass http://xxxxxx:81;
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

location /nodered {
return 301 https://$host:1880;
}

location /homebridge {
return 301 https://$host:8581;
}

#Dashticz subpath forwardoing
location /dashticz {
proxy_pass_header Authorization;
proxy_pass http://xxxxxx:81/dashticz;
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

#Dashticz subpath forwardoing
location /admin {
proxy_pass_header Authorization;
proxy_pass http://xxxxxx:82/admin;
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


#Homebridge op specifik port in root
server {
listen 8581 ssl http2;
server_name xxxxxx.meek-io.com;
location / {
proxy_pass                  http://xxxxxx:8581;
proxy_http_version          1.1;
proxy_buffering             off;
proxy_set_header            Host $host;
proxy_set_header            Upgrade $http_upgrade;
proxy_set_header            Connection "Upgrade";
proxy_set_header            X-Real-IP $remote_addr;
proxy_set_header            X-Forward-For $proxy_add_x_forwarded_for;
}
ssl_certificate /etc/letsencrypt/live/xxxxxx.meek-io.com/fullchain.pem; # managed by Certbot
ssl_certificate_key /etc/letsencrypt/live/xxxxxx.meek-io.com/privkey.pem; # managed by Certbot
}

#proxy for node-red @ port :1880
server {
listen 1880 ssl http2;
server_name xxxxxx.meek-io.com;
location = /robots.txt {
add_header  Content-Type  text/plain;
return 200 "User-agent: *\nDisallow: /\n";
}
location / {
proxy_pass http://xxxxxx:1881;
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
ssl_certificate /etc/letsencrypt/live/xxxxxx.meek-io.com/fullchain.pem; # managed by Certbot
ssl_certificate_key /etc/letsencrypt/live/xxxxxx.meek-io.com/privkey.pem; # managed by Certbot
}

EOF

sed -i -e "s/xxxxxx/$NAME/g" /etc/nginx/sites-enabled/$NAME.conf

#Certbot
#apt install certbot python3-certbot-nginx
#certbot --nginx -d meek-io.com
certbot --nginx -d $NAME.meek-io.com

#echo -n "Cronjob for certificate publish RUN ONCE"
#mkdir /var/www/html/cert-sync
#mkdir /root/MEEK
#cd /root/MEEK
#touch certsync
#cat << EOF > certsync
#5 */12 * * * /bin/sh /root/MEEK/cert-sync.sh
#EOF
#
#crontab certsync

#touch /root/MEEK/cert-sync.sh
#cat << EOF > /root/MEEK/cert-sync.sh
#cp -Lr /etc/letsencrypt/live/ /var/www/html/cert-sync
#chown -R www-data:www-data /var/www/html/
#EOF
#chmod +rwx cert-sync.sh

service nginx reload

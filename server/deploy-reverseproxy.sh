#!/bin/bash

# curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/server/deploy-reverseproxy.sh --output deploy-reverseproxy.sh && chmod +rwx deploy-reverseproxy.sh && ./deploy-reverseproxy.sh
# xxxxxx = Full domain
# zzzzzz = IP container

######--Get IP & full domainname for new container--################################################
cp /etc/letsencrypt/archive/deploy/user /root/user
IP="$(head -1 /root/user)"
NAME="$(tail -1 /root/user)"

cat <<'EOF'> /root/new.conf
server {
server_name xxxxxx;
#Domoticz server in Root
location / {
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_pass_header Authorization;
proxy_pass http://zzzzzz:81;
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
EOF

cat <<'EOF'> /root/newssl.conf
server {
server_name xxxxxx;
#Domoticz server in Root
location / {
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_pass_header Authorization;
proxy_pass http://zzzzzz:81;
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
return 301 https://xxxxxx:1880;
}
location /homebridge {
return 301 https://xxxxxx:8581;
}
#Dashticz subpath forwarding
location /dashticz {
proxy_pass_header Authorization;
proxy_pass http://zzzzzz:81/dashticz;
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
location /admin {
proxy_pass_header Authorization;
proxy_pass http://zzzzzz:82/admin;
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
listen 443 ssl;
ssl_certificate /etc/letsencrypt/live/xxxxxx/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/xxxxxx/privkey.pem;
include /etc/letsencrypt/options-ssl-nginx.conf;
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
#Node-Red port :1880
server {
listen [::]:1880;
server_name xxxxxx;
location = /robots.txt {
add_header  Content-Type  text/plain;
return 200 "User-agent: *\nDisallow: /\n";
}
location / {
proxy_pass http://zzzzzz:1881;
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
listen 1880 ssl;
ssl_certificate /etc/letsencrypt/live/xxxxxx/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/xxxxxx/privkey.pem;
include /etc/letsencrypt/options-ssl-nginx.conf;
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
#Homebridge port 8581
server {
listen [::]:8581;
server_name xxxxxx;
location / {
proxy_pass                  http://zzzzzz:8581;
proxy_http_version          1.1;
proxy_buffering             off;
proxy_set_header            Host $host;
proxy_set_header            Upgrade $http_upgrade;
proxy_set_header            Connection "Upgrade";
proxy_set_header            X-Real-IP $remote_addr;
proxy_set_header            X-Forward-For $proxy_add_x_forwarded_for;
}
listen 8581 ssl;
ssl_certificate /etc/letsencrypt/live/xxxxxx/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/xxxxxx/privkey.pem;
include /etc/letsencrypt/options-ssl-nginx.conf;
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
server {
if ($host = xxxxxx) {
return 301 https://$host$request_uri;
}
server_name xxxxxx;
listen 80;
return 404;
}
EOF

sed -i -e "s/xxxxxx/$NAME/g" /root/new.conf
sed -i -e "s/zzzzzz/$IP/g" /root/new.conf
mv /root/new.conf /etc/nginx/sites-enabled/$NAME.conf
sed -i -e "s/xxxxxx/$NAME/g" /root/newssl.conf
sed -i -e "s/zzzzzz/$IP/g" /root/newssl.conf

######--Issue new Certificte--################################################
cat <<'EOF'> /root/cert.sh
#/bin/sh
echo -n "If you proceed, you will deploy domain xxxxxx with container IP zzzzzz ! (y/n)? "
old_stty_cfg=$(stty -g)
stty raw -echo
answer=$( while ! head -c 1 | grep -i '[ny]' ;do true ;done )
stty $old_stty_cfg
if echo "$answer" | grep -iq "^y" ;then
        certbot run -n --nginx --agree-tos -d xxxxxx -m  cert@mymeek.org --redirect
        mv /root/newssl.conf /etc/nginx/sites-enabled/xxxxxx.conf
        service nginx reload
        rm /etc/letsencrypt/archive/deploy/user
        echo Done, browse to xxxxxx to check
else
    echo No
fi
EOF

sed -i -e "s/xxxxxx/$NAME/g" /root/cert.sh
sed -i -e "s/zzzzzz/$IP/g" /root/cert.sh
chmod +rwx /root/cert.sh

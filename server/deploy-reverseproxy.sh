#!/bin/bash

# curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/server/deploy-reverseproxy.sh --output deploy-reverseproxy.sh && chmod +rwx deploy-reverseproxy.sh && ./deploy-reverseproxy.sh
# xxxxxx = subdomain
# yyyyyy = domain
# zzzzzz = IP container

######--Get IP from new container--################################################
IP="$(head -1 /mnt/certificate/deploy/user)"

######--Set Sub-Domain--################################################
echo -n "Enter subdomain name : "
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

cat <<'EOF'> /etc/nginx/sites-enabled/$NAME.$opt.conf
# xxxxxx = subdomain
server {
listen 80;
server_name xxxxxx.yyyyyy;
return 301 https://$host$request_uri;
}
server {
listen       443 ssl http2;
server_name xxxxxx.yyyyyy;
#Domoticz server in de Root
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
return 301 https://zzzzzz:1880;
}
location /homebridge {
return 301 https://zzzzzz:8581;
}
#Dashticz subpath forwardoing
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
#Dashticz subpath forwardoing
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
}
#Homebridge op specifik port in root
server {
listen 8581 ssl http2;
server_name xxxxxx.yyyyyy;
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
ssl_certificate /etc/letsencrypt/live/xxxxxx.yyyyyy/fullchain.pem; # managed by Certbot
ssl_certificate_key /etc/letsencrypt/live/xxxxxx.yyyyyy/privkey.pem; # managed by Certbot
}
#proxy for node-red @ port :1880
server {
listen 1880 ssl http2;
server_name xxxxxx.yyyyyy;
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
ssl_certificate /etc/letsencrypt/live/xxxxxx.yyyyyy/fullchain.pem; # managed by Certbot
ssl_certificate_key /etc/letsencrypt/live/xxxxxx.yyyyyy/privkey.pem; # managed by Certbot
}
EOF

sed -i -e "s/xxxxxx/$NAME/g" /etc/nginx/sites-enabled/$NAME.$opt.conf
sed -i -e "s/yyyyyy/$opt/g" /etc/nginx/sites-enabled/$NAME.$opt.conf
sed -i -e "s/zzzzzz/$IP/g" /etc/nginx/sites-enabled/$NAME.$opt.conf

######--Issue new Certificte--################################################
certbot --nginx -d $NAME.$opt

service nginx reload

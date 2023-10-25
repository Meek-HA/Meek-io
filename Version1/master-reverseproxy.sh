#!/bin/bash

# 1) Create container "reverseproxy" in unpriviliged mode
# 2) Enable container -nesting- & -NFS- & -IP 10.10.10.100/24 -Gateway 10.10.10.1 - DNS 10.10.10.1
# 3) apt-get install curl -y && curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/Version1/master-reverseproxy.sh --output master-reverseproxy.sh && chmod +rwx master-reverseproxy.sh && ./master-reverseproxy.sh

echo Update System
apt-get update -y
apt-get upgrade -y

echo Set TimZone to Europe/Amsterdam
timedatectl set-timezone Europe/Amsterdam

echo NFS Share
apt install nfs-kernel-server -y
mkdir -p /etc/letsencrypt/archive/deploy/
chown -R nobody:nogroup /etc/letsencrypt/archive/
chmod 777 /etc/letsencrypt/archive/
cat << EOF > /etc/exports
/etc/letsencrypt/archive/ 10.10.10.0/24(rw,sync,no_subtree_check,crossmnt)
EOF

exportfs -a
systemctl restart nfs-kernel-server

echo Installl Nginx reverse proxy
apt-get install nginx -y
unlink /etc/nginx/sites-enabled/default

apt install certbot python3-certbot-nginx -y

######--NEW USER DEPLOYMENT--################################################
apt-get install -y inotify-tools

mkdir /root/MEEK
touch /root/MEEK/new-user.sh
cat << EOF > /root/MEEK/new-user.sh
#!/bin/bash
inotifywait -m -e create -e moved_to -e modify /etc/letsencrypt/archive/deploy|
while read path action file; do
bash /root/deploy-reverseproxy.sh
done
EOF

chmod +x /root/MEEK/new-user.sh

echo -n "Create cronjob"
touch /root/MEEK/cron
cat << EOF > /root/MEEK/cron
@reboot /root/MEEK/new-user.sh
EOF
crontab /root/MEEK/cron

######--Control.mymeek.org--################################################
cat <<'EOF'> /etc/nginx/sites-enabled/control.conf
server {
        listen 80;
        server_name control.mymeek.org;
        return 301 https://control.mymeek.org$request_uri;
}

server {
        listen 443 ssl;
        server_name control.mymeek.org;
        #ssl on;
        location / {
        proxy_pass https://control.mymeek.org:8006$request_uri;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        }
}
EOF

nginx -s reload

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
certbot run -n --nginx --agree-tos -d control.mymeek.org -m  cert@mymeek.org --redirect

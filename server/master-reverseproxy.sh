#!/bin/bash

# 1) Create container "reverseproxy" in unpriviliged mode
# 2) Enable container -nesting- & -NFS- & -IP 10.10.10.100/24 -Gateway 10.10.10.1 - DNS 10.10.10.1
# 3) apt-get install curl -y && curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/server/master-reverseproxy.sh --output master-reverseproxy.sh && chmod +rwx master-reverseproxy.sh && ./master-reverseproxy.sh

echo Update System
apt-get update -y
apt-get upgrade -y

echo Set TimZone to Europe/Amsterdam
timedatectl set-timezone Europe/Amsterdam

echo NFS Share
apt install nfs-kernel-server -y
mkdir -p /mnt/certificate
chown -R nobody:nogroup /mnt/certificate/
chmod 777 /mnt/certificate/
cat << EOF > /etc/exports
/mnt/certificate 10.10.10.0/24(ro,sync,no_subtree_check)
EOF

exportfs -a
systemctl restart nfs-kernel-server

echo Installl Nginx reverse proxy
apt-get install nginx -y
unlink /etc/nginx/sites-enabled/default

apt install certbot python3-certbot-nginx -y

ln -s /etc/letsencrypt/live/ /mnt/certificate

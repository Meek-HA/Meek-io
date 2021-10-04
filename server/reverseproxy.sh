#!/bin/bash

# 1) Create container "reverseproxy" in unpriviliged mode
# 2) Enable container -nesting- & -NFS-
# 3) apt-get install curl -y && curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/server/reverseproxy.sh --output reverseproxy.sh && chmod +rwx reverseproxy.sh && ./reverseproxy.sh

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

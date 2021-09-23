#!/bin/bash

# 1) Create container "reverseproxy" in unpriviliged mode
# 2) Enable container -nesting- & -NFS-

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
/mnt/nfs_share  reverseproxy/24(ro,sync,no_subtree_check)
EOF

exportfs -a
systemctl restart nfs-kernel-server

echo Installl Nginx reverse proxy
apt-get install nginx -y
unlink /etc/nginx/sites-enabled/default

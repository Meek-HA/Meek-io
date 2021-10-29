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
mkdir -p /mnt/certificate/deploy/
chown -R nobody:nogroup /etc/letsencrypt/live/
chmod 777 /etc/letsencrypt/live/
cat << EOF > /etc/exports
/etc/letsencrypt/live/ 10.10.10.0/24(rw,sync,no_subtree_check)
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
inotifywait -m -e create -e moved_to -e modify /etc/letsencrypt/live/deploy|
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

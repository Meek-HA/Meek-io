######--ADMIN CONTROL CENTER--################################################
echo -n "Admin page install"
mkdir /meek-io/nginx/config/www/admin
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/2026/index.php --output /meek-io/nginx/config/www/admin/index.php


mkdir /meek-io/meek/
curl https://raw.githubusercontent.com/Meek-HA/Meek-io/master/2026/meek-action-handler.sh --output /meek-io/meek//meek-action-handler.sh
chmod +x /meek-io/meek/meek-action-handler.sh


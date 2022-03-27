#!/usr/bin/env bash

if [[ -d /etc/nginx/conf.d ]]; then
	mapfile -t VHOSTS < <(grep -iRls server_name /etc/nginx/conf.d)
fi

for host in "${VHOSTS[@]}"
do
	# Parse root directive in vhost config file
	root_line=$( grep -s -E '^[[:space:]]*?root[[:space:]]{1}[a-zA-Z0-9\/\.\-]+;$' "$host" )
    root_line=$(echo $root_line)
    root=$(echo "$root_line" | cut -d" " -f2 | tr -d ';')

    # Make sure this is a wp site
    if [[ -f "$root/wp-config.php" ]]; then
        wp --path="$root/cms" cron event run --due-now > /dev/null 2>&1
    fi
done

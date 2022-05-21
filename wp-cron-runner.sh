#!/usr/bin/env bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

LOCKFILE=/var/lock/wp-cron-runner.lock

set -o noclobber
exec {lockfd}<> "${LOCKFILE}" || exit 1
set +o noclobber
flock --exclusive --nonblock ${lockfd} || exit 1

if command -v wp > /dev/null 2>&1; then
    WP=$(command -v wp)
else
    echo "Err: WPCLI is not installed."
    exit 1
fi

if [[ -d /etc/nginx/conf.d ]]; then
    mapfile -t VHOSTS < <(/bin/grep -iRls server_name /etc/nginx/conf.d)
fi

for host in "${VHOSTS[@]}"
do
    # Parse root directive in vhost config file
    root_line=$( /bin/grep -s -E '^[[:space:]]*?root[[:space:]]{1}[a-zA-Z0-9\/\.\-]+;$' "$host" )
    root_line=$(echo $root_line)
    root=$(echo "$root_line" | cut -d" " -f2 | tr -d ';')

    # Make sure this is a wp site
    if [[ -f "$root/wp-config.php" ]]; then
        # Run cron jobs
        $WP --path="$root/cms" cron event run --due-now
    fi
done

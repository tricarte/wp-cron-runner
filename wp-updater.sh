#!/usr/bin/env bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

LOCKFILE=/var/lock/wp-updater.lock

set -o noclobber
exec {lockfd}<> "${LOCKFILE}" || exit 1
set +o noclobber
flock --exclusive --nonblock ${lockfd} || exit 1

if command -v composer > /dev/null 2>&1; then
    COMPOSERBIN=$(command -v composer)
else
    echo "Err: Composer cli is not installed."
    exit 1
fi

if command -v wp > /dev/null 2>&1; then
    WP=$(command -v wp)
else
    echo "Err: WPCLI is not installed."
    exit 1
fi

if command -v git > /dev/null 2>&1; then
    GIT=$(command -v git)
else
    echo "Err: git is not installed."
    exit 1
fi

if command -v md5sum > /dev/null 2>&1; then
    MD5BIN=$(command -v md5sum)
else
    echo "Err: md5sum is not installed."
    exit 1
fi

# Is opcache-manager plugin installed
$WP --path="$root/cms" opcache > /dev/null 2>&1
WP_OPCACHE_INSTALLED=$?

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

        # composer update
        MD5SUM=$($MD5BIN "$root/../composer.lock" | cut -d" " -f1)
        $COMPOSERBIN --working-dir="$root/../" update -q
        MD5SUMNEW=$($MD5BIN "$root/../composer.lock" | cut -d" " -f1)

        if [[ $MD5SUMNEW != $MD5SUM ]]; then
            # git commit changes
            $GIT --git-dir="$root/../.git" --work-tree="$root/../" add composer.lock
            $GIT --git-dir="$root/../.git" --work-tree="$root/../" commit -m"versions updated"

            # Invalidate cache
            # if [[ ! $WP_OPCACHE_INSTALLED ]]; then
            #     $WP --path="$root/cms" opcache invalidate --yes > /dev/null 2>&1
            # fi

            # Invalidate opcache
            # https://www.php.net/manual/tr/function.opcache-reset.php#121513
            SITEURL=$($WP --skip-plugins --path="$root/cms" config get WP_HOME)
            # RANDOM_NAME=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)
            echo "<?php opcache_reset(); ?>" > "$root/clear_opcache.php"
            /usr/bin/curl "$SITEURL/clear_opcache.php"
            /bin/rm "$root/clear_opcache.php"
        fi
    fi
done

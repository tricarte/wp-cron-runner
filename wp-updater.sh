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

if command -v msmtp > /dev/null 2>&1; then
    MSMTP=$(command -v msmtp)
else
    echo "Err: msmtp is not installed."
    exit 1
fi

# Is opcache-manager plugin installed
# This command must be run as www-data.
# Or you have to be a member of www-data group
# $WP --path="$root/cms" opcache > /dev/null 2>&1
# WP_OPCACHE_INSTALLED=$?

if [[ -d /etc/nginx/conf.d ]]; then
    mapfile -t VHOSTS < <(/bin/grep -iRls server_name /etc/nginx/conf.d)
fi

# UPDATES_LIST=""

for host in "${VHOSTS[@]}"
do
    # Parse root directive in vhost config file
    root_line=$( /bin/grep -s -E '^[[:space:]]*?root[[:space:]]{1}[a-zA-Z0-9\/\.\-]+;$' "$host" )
    root_line=$(echo $root_line)
    root=$(echo "$root_line" | cut -d" " -f2 | tr -d ';')

    if [[  $root =~ 'twpr' ]]; then
        continue
    fi

    # Make sure this is a wp site
    if [[ -f "$root/wp-config.php" ]]; then
        UPDATES=$($COMPOSERBIN --working-dir="$root/../" update --dry-run 2>&1 | sed -ne '/Package operations/,$ p' | grep "Upgrading" | awk '{ print substr ($0, 15 ) }')

        if [[ -n $UPDATES ]]; then
            # UPDATES_LIST+="$UPDATES\n"
            AdminEmail=$($WP --skip-plugins --path="$root/cms" user get 1 --field=user_email)
            if [[ $AdminEmail != 'info@example.com' ]]; then
                echo -e "Subject: Updates for site $host\n\n$UPDATES" | $MSMTP "$AdminEmail"
            fi

            # composer update
            MD5SUM=$($MD5BIN "$root/../composer.lock" | cut -d" " -f1)
            $COMPOSERBIN --working-dir="$root/../" update -q
            MD5SUMNEW=$($MD5BIN "$root/../composer.lock" | cut -d" " -f1)

            if [[ $MD5SUMNEW != "$MD5SUM" ]]; then
                # git commit changes
                $GIT --git-dir="$root/../.git" --work-tree="$root/../" add composer.lock
                $GIT --git-dir="$root/../.git" --work-tree="$root/../" commit -m"Versions updated..." -m"$UPDATES" -q

            # Invalidate cache
            # if [[ ! $WP_OPCACHE_INSTALLED ]]; then
            #     $WP --path="$root/cms" opcache invalidate --yes > /dev/null 2>&1
            # fi

            # Invalidate opcache and apcu cache
            # https://www.php.net/manual/tr/function.opcache-reset.php#121513
            # Remember that this invalidates caches of all virtual hosts
            # UPDATE: Since I'm using opcache.validate_timestamps=1
            # This no longer resets opcache, just the apcu cache.
            SITEURL=$($WP --skip-plugins --path="$root/cms" config get WP_HOME)
            # RANDOM_NAME=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)
            # echo "<?php opcache_reset(); apcu_clear_cache(); ?>" > "$root/clear_cache.php"
            echo "<?php apcu_clear_cache(); ?>" > "$root/clear_cache.php"
            /usr/bin/curl "$SITEURL/clear_cache.php"
            /bin/rm "$root/clear_cache.php"
        fi
    fi

    fi
done

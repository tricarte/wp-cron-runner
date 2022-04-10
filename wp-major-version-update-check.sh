#!/usr/bin/env bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

LOCKFILE=/var/lock/wp-major-version-update-check.lock

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

if command -v msmtp > /dev/null 2>&1; then
    MSMTP=$(command -v msmtp)
else
    echo "Err: msmtp is not installed."
    exit 1
fi

if [[ -d /etc/nginx/conf.d ]]; then
    mapfile -t VHOSTS < <(/bin/grep -iRls server_name /etc/nginx/conf.d)
fi

sep=","

for host in "${VHOSTS[@]}"
do
    # Parse root directive in vhost config file
    root_line=$( /bin/grep -s -E '^[[:space:]]*?root[[:space:]]{1}[a-zA-Z0-9\/\.\-]+;$' "$host" )
    root_line=$(echo $root_line)
    root=$(echo "$root_line" | cut -d" " -f2 | tr -d ';')

    if [[  $root =~ 'twpr' ]]; then
        continue
    fi

    # The message that will be sent to the site admin
    MAJOR_UPGRADES=""

    # Make sure this is a wp site
    if [[ -f "$root/wp-config.php" ]]; then
		# Find out major core upgrades
        MAJOR_CORE=$($WP --skip-plugins --path="$root/cms" core check-update --major --fields=version --format=csv | tail -n +2)

        if [[ -n $MAJOR_CORE ]]; then
           MAJOR_UPGRADES+="$host can be upgraded to a major WP version: $MAJOR_CORE.\n\n" 
        fi

		# Find out major plugin upgrades
		MAJOR_PLUGIN_UPGRADES=""
		for plugin in $($WP --skip-plugins --path="$root/cms" plugin list --update=available --fields=name,version,update_version --format=csv | tail -n +2)
		do
			IFS="$sep" read -rd '' name version update_version < <(printf '%s%s' "$plugin" "$sep") || true
			CURVERSION="${version#[vV]}"
			UPDATEVERSION="${update_version#[vV]}"
			if [[ ${UPDATEVERSION%%\.*} > ${CURVERSION%%\.*} ]]; then
				MAJOR_PLUGIN_UPGRADES+="Plugin $name have a major version upgrade: $update_version\n"
			fi
		done

		if [[ -n $MAJOR_PLUGIN_UPGRADES ]]; then
		    MAJOR_UPGRADES+="$MAJOR_PLUGIN_UPGRADES\n\n"
        fi

        # Find out major theme updates
		MAJOR_THEME_UPGRADES=""
		for theme in $($WP --skip-plugins --path="$root/cms" theme list --update=available --fields=name,version,update_version --format=csv | tail -n +2)
		do
			IFS="$sep" read -rd '' name version update_version < <(printf '%s%s' "$theme" "$sep") || true
			CURVERSION="${version#[vV]}"
			UPDATEVERSION="${update_version#[vV]}"
			if [[ ${UPDATEVERSION%%\.*} > ${CURVERSION%%\.*} ]]; then
				MAJOR_THEME_UPGRADES+="Theme $name have a major version upgrade: $update_version\n"
			fi
		done

		if [[ -n $MAJOR_THEME_UPGRADES ]]; then
		    MAJOR_UPGRADES+="$MAJOR_THEME_UPGRADES\n\n"
        fi

		if [[ -n $MAJOR_UPGRADES ]]; then
			AdminEmail=$($WP --skip-plugins --path="$root/cms" user get 1 --field=user_email)
			if [[ $AdminEmail != 'info@example.com' ]]; then
				echo -e "Subject: Updates with major version changes available for $host\n\n$MAJOR_UPGRADES" | $MSMTP "$AdminEmail"
			fi
		fi
    fi
done

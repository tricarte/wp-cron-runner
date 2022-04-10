#!/usr/bin/env bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

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

    # Make sure this is a wp site
    if [[ -f "$root/wp-config.php" ]]; then
		MAJOR_UPGRADES=""
		for plugin in $($WP --skip-plugins --path="$root/cms" plugin list --update=available --fields=name,version,update_version --format=csv | tail -n +2)
		do
			IFS="$sep" read -rd '' name version update_version < <(printf '%s%s' "$plugin" "$sep") || true
			CURVERSION="${version#[vV]}"
			UPDATEVERSION="${update_version#[vV]}"
			if [[ ${UPDATEVERSION%%\.*} > ${CURVERSION%%\.*} ]]; then
				MAJOR_UPGRADES+="$name needs a major version upgrade: $update_version\n"
			fi
		done

		if [[ -n $MAJOR_UPGRADES ]]; then
			AdminEmail=$($WP --skip-plugins --path="$root/cms" user get 1 --field=user_email)
			if [[ $AdminEmail != 'info@example.com' ]]; then
				echo -e "Subject: Plugin updates with major versions available for $host\n\n$MAJOR_UPGRADES" | $MSMTP "$AdminEmail"
			fi
		fi
    fi
done


. /lib/functions.sh
. /lib/functions/network.sh

load_all_config_options()
{
	pkg_name="$1"
	section_id="$2"
	ALL_OPTION_VARIABLES=""

	config_cb()
	{
		if [ ."$2" = ."$section_id" ]; then
			option_cb()
			{
				ALL_OPTION_VARIABLES="$ALL_OPTION_VARIABLES $1"
			}
		else
			option_cb() { return 0; }
		fi
	}


	config_load "$pkg_name"
	for var in $ALL_OPTION_VARIABLES
	do
		config_get "$var" "$section_id" "$var"
	done
}

get_current_ip()
{
	
	if [ "$ip_source" != "interface" ] && [ "$ip_source" != "web" ] && [ "$ip_source" != "script" ]
	then
		ip_source="network"
	fi

	if [ "$ip_source" = "network" ]
	then
		if [ -z "$ip_network" ]
		then
			ip_network="wan"
		fi
	fi

	current_ip='';
	if [ "$ip_source" = "network" ]
	then
		network_get_ipaddr current_ip "$ip_network" || return
	elif [ "$ip_source" = "interface" ]
	then
		current_ip=$(ifconfig $ip_interface | grep -o 'inet addr:[0-9.]*' | grep -o "$ip_regex")
	elif [ "$ip_source" = "script" ]
	then
		current_ip=$($ip_script)
	else
		for addr in $ip_url
		do
			if [ -z "$current_ip" ]
			then
				current_ip=$(echo $( wget -O - $addr 2>/dev/null) | grep -o "$ip_regex")
			fi
		done
		if [ -z "$current_ip" ]
		then
			current_ip=$(echo $( wget -O - http://checkip.dyndns.org 2>/dev/null) | grep -o "$ip_regex")
		fi
	fi

	echo "$current_ip"
}


verbose_echo()
{
	if [ "$verbose_mode" = 1 ]
	then
		echo $1
	fi
}

start_daemon_for_all_ddns_sections()
{
	local event_interface="$1"

	SECTIONS=""
	config_cb() 
	{
		SECTIONS="$SECTIONS $2"
	}
	config_load "ddns"

	for section in $SECTIONS
	do
		local iface
		config_get iface "$section" interface "wan"
		[ "$iface" = "$event_interface" ] || continue
		/usr/lib/ddns/dynamic_dns_updater.sh $section 0 > /dev/null 2>&1 &
	done
}

monotonic_time()
{
	local uptime
	read uptime < /proc/uptime
	echo "${uptime%%.*}"
}

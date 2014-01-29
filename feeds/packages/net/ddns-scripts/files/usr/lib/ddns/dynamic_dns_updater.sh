
. /usr/lib/ddns/dynamic_dns_functions.sh


service_id=$1
if [ -z "$service_id" ]
then
	echo "ERRROR: You must specify a service id (the section name in the /etc/config/ddns file) to initialize dynamic DNS."
	return 1
fi

verbose_mode="1"
if [ -n "$2" ]
then
	verbose_mode="$2"
fi

load_all_config_options "ddns" "$service_id"

if [ -z "$check_interval" ]
then
	check_interval=600
fi

if [ -z "$retry_interval" ]
then
	retry_interval=60
fi

if [ -z "$check_unit" ]
then
	check_unit="seconds"
fi


if [ -z "$force_interval" ]
then
	force_interval=72
fi

if [ -z "$force_unit" ]
then
	force_unit="hours"
fi

if [ -z "$use_https" ]
then
	use_https=0
fi

if [ "x$use_https" = "x1" ]
then
	retrieve_prog="/usr/bin/curl "
	if [ -f "$cacert" ]
	then
		retrieve_prog="${retrieve_prog}--cacert $cacert "
	elif [ -d "$cacert" ]
	then
		retrieve_prog="${retrieve_prog}--capath $cacert "
	fi
else
	retrieve_prog="/usr/bin/wget --no-check-certificate -O - ";
fi

service_file="/usr/lib/ddns/services"

ip_regex="[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}"

NEWLINE_IFS='
'

if [ -n "$service_name" ]
then
	quoted_services=$(cat $service_file |  grep "^[\t ]*[^#]" |  awk ' gsub("\x27", "\"") { if ($1~/^[^\"]*$/) $1="\""$1"\"" }; { if ( $NF~/^[^\"]*$/) $NF="\""$NF"\""  }; { print $0 }' )
	OLD_IFS=$IFS
	IFS=$NEWLINE_IFS
	for service_line in $quoted_services
	do
		next_name=$(echo $service_line | grep -o "^[\t ]*\"[^\"]*\"" | xargs -r -n1 echo)
		next_url=$(echo $service_line | grep -o "\"[^\"]*\"[\t ]*$" | xargs -r -n1 echo)

		if [ "$next_name" = "$service_name" ]
		then
			update_url=$next_url
		fi
	done
	IFS=$OLD_IFS
fi

if [ "x$use_https" = x1 ]
then
	update_url=$(echo $update_url | sed -e 's/^http:/https:/')
fi

verbose_echo "update_url=$update_url"

if [ "$enabled" != "1" ] 
then
	return 0
fi

case "$force_unit" in
	"days" )
		force_interval_seconds=$(($force_interval*60*60*24))
		;;
	"hours" )
		force_interval_seconds=$(($force_interval*60*60))
		;;
	"minutes" )
		force_interval_seconds=$(($force_interval*60))
		;;
	"seconds" )
		force_interval_seconds=$force_interval
		;;
	* )
		force_interval_seconds=$(($force_interval*60*60))
		;;
esac

case "$check_unit" in
	"days" )
		check_interval_seconds=$(($check_interval*60*60*24))
		;;
	"hours" )
		check_interval_seconds=$(($check_interval*60*60))
		;;
	"minutes" )
		check_interval_seconds=$(($check_interval*60))
		;;
	"seconds" )
		check_interval_seconds=$check_interval
		;;
	* )
		check_interval_seconds=$check_interval
		;;
esac

case "$retry_unit" in
	"days" )
		retry_interval_seconds=$(($retry_interval*60*60*24))
		;;
	"hours" )
		retry_interval_seconds=$(($retry_interval*60*60))
		;;
	"minutes" )
		retry_interval_seconds=$(($retry_interval*60))
		;;
	"seconds" )
		retry_interval_seconds=$retry_interval
		;;
	* )
		#default is seconds
		retry_interval_seconds=$retry_interval
		;;
esac

verbose_echo "force seconds = $force_interval_seconds"
verbose_echo "check seconds = $check_interval_seconds"

if [ -d /var/run/dynamic_dns ]
then
	if [ -e "/var/run/dynamic_dns/$service_id.pid" ]
	then
		old_pid=$(cat /var/run/dynamic_dns/$service_id.pid)
		test_match=$(ps | grep "^[\t ]*$old_pid")
		verbose_echo "old process id (if it exists) = \"$test_match\""
		if [ -n  "$test_match" ]
		then
			kill $old_pid
		fi
	fi

else
	mkdir /var/run/dynamic_dns
fi
echo $$ > /var/run/dynamic_dns/$service_id.pid

current_time=$(monotonic_time)
last_update=$(( $current_time - (2*$force_interval_seconds) ))
if [ -e "/var/run/dynamic_dns/$service_id.update" ]
then
	last_update=$(cat /var/run/dynamic_dns/$service_id.update)
fi
time_since_update=$(($current_time - $last_update))


human_time_since_update=$(( $time_since_update / ( 60 * 60 ) ))
verbose_echo "time_since_update = $human_time_since_update hours"

while [ true ]
do
	registered_ip=$(echo $(nslookup "$domain" 2>/dev/null) |  grep -o "Name:.*" | grep -o "$ip_regex")
	current_ip=$(get_current_ip)


	current_time=$(monotonic_time)
	time_since_update=$(($current_time - $last_update))


	verbose_echo "Running IP check..."
	verbose_echo "current system ip = $current_ip"
	verbose_echo "registered domain ip = $registered_ip"


	if [ "$current_ip" != "$registered_ip" ]  || [ $force_interval_seconds -lt $time_since_update ]
	then
		verbose_echo "update necessary, performing update ..."

		final_url=$update_url
		for option_var in $ALL_OPTION_VARIABLES
		do
			if [ "$option_var" != "update_url" ]
			then
				replace_name=$(echo "\[$option_var\]" | tr 'a-z' 'A-Z')
				replace_value=$(eval echo "\$$option_var")
				replace_value=$(echo $replace_value | sed -f /usr/lib/ddns/url_escape.sed)
				final_url=$(echo $final_url | sed s^"$replace_name"^"$replace_value"^g )
			fi
		done
		final_url=$(echo $final_url | sed s^"\[HTTPAUTH\]"^"${username//^/\\^}${password:+:${password//^/\\^}}"^g )
		final_url=$(echo $final_url | sed s/"\[IP\]"/"$current_ip"/g )


		verbose_echo "updating with url=\"$final_url\""

		update_output=$( $retrieve_prog "$final_url" )
		if [ $? -gt 0 ]
		then
			verbose_echo "update failed"
			sleep $retry_interval_seconds
			continue
		fi

		verbose_echo "Update Output:"
		verbose_echo "$update_output"
		verbose_echo ""

		current_time=$(monotonic_time)
		last_update=$current_time
		time_since_update='0'
		registered_ip=$current_ip

		human_time=$(date)
		verbose_echo "update complete, time is: $human_time"

		echo "$last_update" > "/var/run/dynamic_dns/$service_id.update"
	else
		human_time=$(date)
		human_time_since_update=$(( $time_since_update / ( 60 * 60 ) ))
		verbose_echo "update unnecessary"
		verbose_echo "time since last update = $human_time_since_update hours"
		verbose_echo "the time is now $human_time"
	fi

	sleep $check_interval_seconds
done

return 0


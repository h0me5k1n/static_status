#!/usr/bin/env bash

# status.sh
# Forked from: Nils Knieling and Contributors- https://github.com/Cyclenerd/static_status
# Updated by: h0me5k1n - 

# Simple Bash script to generate a status page.

################################################################################
#### Configuration 
################################################################################

# config variables from the cfg/config-example file are used by default!
# to use a custom config, copy this file as cfg/config and edit as necessary

# the cfg/status_hostname_list-example.txt file is used by default for checks!
# to use custom checks, copy this file as cfg/status_hostname_list.txt
# and edit as necessary

# the cfg/status_maintenance_text-example.txt file is used by default for 
# maintenance messages!
# to display custom maintenance messages, create a file called 
# status_maintenance_text.txt

# using the above allows for updating and the potential to persist data when
# running in docker

################################################################################
#### END Configuration 
################################################################################
#Timer - used to display the duration up to writing the html footer
SECONDS=0

ME=$(basename "$0")
BASE_PATH=$(dirname "$0") # TODO: Resolv symlinks https://stackoverflow.com/questions/59895
MY_TIMESTAMP=$(date -u "+%s")
MY_DATE_TIME=$(date -u "+%Y-%m-%d %H:%M:%S %Z")
MY_LASTRUN_TIME="0"
BE_LOUD="no"
BE_QUIET="no"
# Commands we need
MY_COMMANDS=(
	ping
	nc
	curl
	grep
	traceroute
	traceroutevpn
	sed
)

# if a config file hasn't been created use the example/default config
MY_STATUS_CONFIG="$BASE_PATH/cfg/config"
if [[ ! -f "$MY_STATUS_CONFIG" ]]; then
	echo "Using config-example"
	MY_STATUS_CONFIG="$BASE_PATH/cfg/config-example"
fi

################################################################################
# Usage
################################################################################

function usage {
	returnCode="$1"
	echo -e "Usage: $ME [OPTION]:
	OPTION is one of the following:
	\\tsilent\\t no output from faulty connections to stout (default: $BE_QUIET)
	\\tloud\\t output from successful and faulty connections to stout (default: $BE_LOUD)
	\\thelp\\t displays help (this message)"
	exit "$returnCode"
}

################################################################################
# Helper
################################################################################

# debug_variables() print all script global variables to ease debugging
debug_variables() {
	echo "USERNAME: $USERNAME"
	echo "SHELL: $SHELL"
	echo "BASH_VERSION: $BASH_VERSION"
	echo
	echo "MY_TIMEOUT: $MY_TIMEOUT"
	echo "MY_AUTOREFRESH: $MY_AUTOREFRESH"
	echo "MY_TRACEROUTE_HOST: $MY_TRACEROUTE_HOST"
	echo "MY_TRACEROUTE_HOST_VPN: $MY_TRACEROUTE_HOST_VPN"
	echo
	echo "MY_STATUS_CONFIG: $MY_STATUS_CONFIG"
	echo "MY_STATUS_CONFIG_DIR: $MY_STATUS_CONFIG_DIR"
	echo "MY_HOSTNAME_FILE: $MY_HOSTNAME_FILE"
	echo
	echo "MY_STATUS_OUTPUT_DIR: $MY_STATUS_OUTPUT_DIR"
	echo "MY_HOSTNAME_STATUS_OK: $MY_HOSTNAME_STATUS_OK"
	echo "MY_HOSTNAME_STATUS_DOWN: $MY_HOSTNAME_STATUS_DOWN"
	echo "MY_HOSTNAME_STATUS_LASTRUN: $MY_HOSTNAME_STATUS_LASTRUN"
	echo "MY_HOSTNAME_STATUS_HISTORY: $MY_HOSTNAME_STATUS_HISTORY"
	echo "MY_STATUS_HTML: $MY_STATUS_HTML"
	echo "MY_MAINTENANCE_TEXT_FILE: $MY_MAINTENANCE_TEXT_FILE"
	echo
	echo "MY_HOMEPAGE_URL: $MY_HOMEPAGE_URL"
	echo "MY_HOMEPAGE_TITLE: $MY_HOMEPAGE_TITLE"
	echo "MY_STATUS_TITLE: $MY_STATUS_TITLE"
	echo "MY_STATUS_STYLESHEET: $MY_STATUS_STYLESHEET"
	echo "MY_STATUS_FOOTER: $MY_STATUS_FOOTER"
	echo
	echo "MY_STATUS_LOCKFILE: $MY_STATUS_LOCKFILE"
	echo
	echo "MY_TIMESTAMP: $MY_TIMESTAMP"
	echo "MY_DATE_TIME: $MY_DATE_TIME"
	echo "MY_LASTRUN_TIME: $MY_LASTRUN_TIME"
}

# command_exists() tells if a given command exists.
function command_exists() {
	command -v "$1" >/dev/null 2>&1
}

# check_bash() check if current shell is bash
function check_bash() {
	if [[ "$0" == *"bash" ]]; then
		exit_with_failure "Your current shell is $0"
	fi
}

# check_command() check if command exists and exit if not exists
function check_command() {
	if ! command_exists "$1"; then
		exit_with_failure "Command '$1' not found"
	fi
}

# check_config() check if the configuration file is readble
function check_config() {
	if [ ! -r "$1" ]; then
		exit_with_failure "Cannot read required configuration file '$1'"
	fi
}

# check_file() check if the file exists if not create the file
function check_file() {
	if [ ! -f "$1" ]; then
		if ! echo > "$1"; then
			exit_with_failure "Cannot create file '$1'"
		fi
	fi
	if [ ! -w "$1" ]; then
		exit_with_failure "Cannot write file '$1'"
	fi
}

# check_folder() check if the folder exists if not create the folder
function check_folder() {
	if [ ! -d "$1" ]; then
		if ! echo > "$1"; then
			exit_with_failure "Cannot create folder '$1'"
		fi
	fi
	if [ ! -w "$1" ]; then
		exit_with_failure "Cannot write folder '$1'"
	fi
}

# exit_with_failure() outputs a message before exiting the script.
function exit_with_failure() {
	echo
	echo "FAILURE: $1"
	echo
	debug_variables
	echo
	del_lock
	exit 1
}

# echo_warning() outputs a warning message.
function echo_warning() {
	echo
	echo "WARNING: $1, will attempt to continue..."
	echo
}

# echo_do_not_edit() outputs a "do not edit" message to write to a file
function echo_do_not_edit() {
	echo "#"
	echo "# !!! Do not edit this file !!!"
	echo "#"
	echo "# To reset everything, delete the files:"
	echo "#     $MY_HOSTNAME_STATUS_OK"
	echo "#     $MY_HOSTNAME_STATUS_DOWN"
	echo "#     $MY_HOSTNAME_STATUS_LASTRUN"
	echo "#     $MY_HOSTNAME_STATUS_HISTORY"
	echo "#"
}

# set_lock() sets lock file
function set_lock() {
	if ! echo "$MY_DATE_TIME" > "$MY_STATUS_LOCKFILE"; then
		exit_with_failure "Cannot create lock file '$MY_STATUS_LOCKFILE'"
	fi
}

# del_lock() delets lock file
function del_lock() {
	rm "$MY_STATUS_LOCKFILE" &> /dev/null
}

# check_lock() checks lock file and exit if the file exists
function check_lock() {
	if [ -f "$MY_STATUS_LOCKFILE" ]; then
		exit_with_failure "$ME is already running. Please wait... In case of problems simply delete the file: '$MY_STATUS_LOCKFILE'"
	fi
}

# port_to_name() outputs name of well-known ports
#    https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers#Well-known_ports
function port_to_name() {
	case "$1" in
	32[0-9][0-9])
		MY_PORT_NAME="SAP Dispatcher"
		;;
	33[0-9][0-9])
		MY_PORT_NAME="SAP Gateway"
		;;
	80[0-9][0-9])
		MY_PORT_NAME="SAP ICM HTTP"
		;;
	443[0-9][0-9])
		MY_PORT_NAME="SAP ICM HTTPS"
		;;
	36[0-9][0-9])
		MY_PORT_NAME="SAP Message Server"
		;;
	5[0-9][0-9]00)
		MY_PORT_NAME="SAP J2EE HTTP"
		;;
	5[0-9][0-9]01)
		MY_PORT_NAME="SAP J2EE HTTPS"
		;;
	5[0-9][0-9]04)
		MY_PORT_NAME="SAP P4"
		;;
	5[0-9][0-9]08)
		MY_PORT_NAME="SAP Telnet"
		;;
	*)
		MY_SERVICE_NAME=$(awk  '$2 ~ /^'"$1"'\// {print $1; exit}' "/etc/services" 2> /dev/null)
		if [ -n "$MY_SERVICE_NAME" ]; then
			MY_PORT_NAME=$(echo "$MY_SERVICE_NAME" | awk '{print toupper($0)}')
		else
			MY_PORT_NAME="Port $1"
		fi
		;;
	esac
	printf "%s" "$MY_PORT_NAME"
}

# get_lastrun_time()
function get_lastrun_time() {
	while IFS=';' read -r MY_LASTRUN_COMMAND MY_LASTRUN_TIMESTAMP || [[ -n "$MY_LASTRUN_COMMAND" ]]; do
		if 	[[ "$MY_LASTRUN_COMMAND" = "timestamp" ]]; then
			if 	[ "$MY_LASTRUN_TIMESTAMP" -ge "0" ]; then
				MY_LASTRUN_TIME="$((MY_TIMESTAMP-MY_LASTRUN_TIMESTAMP))"
			else
				MY_LASTRUN_TIME="0"
			fi
		fi
	done <"$MY_HOSTNAME_STATUS_LASTRUN"
}

# check_downtime() check whether a failure has already been documented
#   and determine the duration
function check_downtime() {
	MY_COMMAND="$1"
	MY_HOSTNAME="$2"
	MY_PORT="$3"
	MY_DOWN_TIME="0"

	while IFS=';' read -r MY_DOWN_COMMAND MY_DOWN_HOSTNAME MY_DOWN_PORT MY_DOWN_TIME || [[ -n "$MY_DOWN_COMMAND" ]]; do
		if [[ "$MY_DOWN_COMMAND" = "ping" ]] ||
		   [[ "$MY_DOWN_COMMAND" = "nc" ]] ||
		   [[ "$MY_DOWN_COMMAND" = "grep" ]] ||
		   [[ "$MY_DOWN_COMMAND" = "traceroute" ]] ||
		   [[ "$MY_DOWN_COMMAND" = "traceroutevpn" ]] ||
		   [[ "$MY_DOWN_COMMAND" = "curl" ]] ||
		   [[ "$MY_DOWN_COMMAND" = "http-status" ]] ||
		   [[ "$MY_DOWN_COMMAND" = "script" ]]; then
			if 	[[ "$MY_DOWN_HOSTNAME" = "$MY_HOSTNAME" ]]; then
				if 	[[ "$MY_DOWN_PORT" = "$MY_PORT" ]]; then
					MY_DOWN_TIME="$((MY_DOWN_TIME+MY_LASTRUN_TIME))"
					break  # Skip entire rest of loop.
				fi
			fi
		fi
	done <"$MY_HOSTNAME_STATUS_LASTRUN" # MY_HOSTNAME_STATUS_DOWN is copied to MY_HOSTNAME_STATUS_LASTRUN
}

# save_downtime()
function save_downtime() {
	MY_COMMAND="$1"
	MY_HOSTNAME="$2"
	MY_PORT="$3"
	MY_DOWN_TIME="$4"
	printf "\\n%s;%s;%s;%s" "$MY_COMMAND" "$MY_HOSTNAME" "$MY_PORT" "$MY_DOWN_TIME" >> "$MY_HOSTNAME_STATUS_DOWN"
	if [[ "$BE_LOUD" = "yes" ]] || [[ "$BE_QUIET" = "no" ]]; then
		printf "\\n%-5s %-4s %s" "DOWN:" "$MY_COMMAND" "$MY_HOSTNAME"
		if [[ $MY_COMMAND == "nc" ]]; then
			printf " %s" "$(port_to_name "$MY_PORT")"
		fi
		if [[ $MY_COMMAND == "grep" ]]; then
			printf " %s" "$MY_PORT"
		fi
		if [[ $MY_COMMAND == "http-status" ]]; then
			printf " %s" "$MY_PORT"
		fi
	fi
}

# save_availability()
function save_availability() {
	MY_COMMAND="$1"
	MY_HOSTNAME="$2"
	MY_PORT="$3"
	printf "\\n%s;%s;%s" "$MY_COMMAND" "$MY_HOSTNAME" "$MY_PORT" >> "$MY_HOSTNAME_STATUS_OK"
	if [[ "$BE_LOUD" = "yes" ]]; then
		printf "\\n%-5s %-4s %s" "UP:" "$MY_COMMAND" "$MY_HOSTNAME"
		if [[ $MY_COMMAND == "nc" ]]; then
			printf " %s" "$(port_to_name "$MY_PORT")"
		fi
		if [[ $MY_COMMAND == "grep" ]]; then
			printf " %s" "$MY_PORT"
		fi
		if [[ $MY_COMMAND == "http-status" ]]; then
			printf " %s" "$MY_PORT"
		fi
	fi
}

# save_history()
function save_history() {
	MY_COMMAND="$1"
	MY_HOSTNAME="$2"
	MY_PORT="$3"
	MY_DOWN_TIME="$4"
	MY_DATE_TIME="$5"
	if cp "$MY_HOSTNAME_STATUS_HISTORY" "$MY_HOSTNAME_STATUS_HISTORY_TEMP_SORT" &> /dev/null; then
		printf "\\n%s;%s;%s;%s;%s" "$MY_COMMAND" "$MY_HOSTNAME" "$MY_PORT" "$MY_DOWN_TIME" "$MY_DATE_TIME" > "$MY_HOSTNAME_STATUS_HISTORY"
		cat "$MY_HOSTNAME_STATUS_HISTORY_TEMP_SORT" >> "$MY_HOSTNAME_STATUS_HISTORY"
		rm "$MY_HOSTNAME_STATUS_HISTORY_TEMP_SORT" &> /dev/null
	else
		exit_with_failure "Cannot copy file '$MY_HOSTNAME_STATUS_HISTORY' to '$MY_HOSTNAME_STATUS_HISTORY_TEMP_SORT'"
	fi

	if [[ "$BE_LOUD" = "yes" ]]; then
		printf "\\n%-5s %-4s %s %s sec" "HIST:" "$MY_COMMAND" "$MY_HOSTNAME" "$MY_DOWN_TIME"
		if [[ $MY_COMMAND == "nc" ]]; then
			printf " %s" "$(port_to_name "$MY_PORT")"
		fi
		if [[ $MY_COMMAND == "grep" ]]; then
			printf " %s" "$MY_PORT"
		fi
		if [[ $MY_COMMAND == "http-status" ]]; then
			printf " %s" "$MY_PORT"
		fi
	fi
}


################################################################################
# HTML
################################################################################

function page_header() {
	# check for autorefresh
	if [ $MY_AUTOREFRESH -gt 0 ]
	then
		MY_AUTOREFRESH_TEXT="<meta http-equiv=\"refresh\" content=\"$MY_AUTOREFRESH\">"
	else
		MY_AUTOREFRESH_TEXT=""
	fi
	cat > "$MY_STATUS_HTML" << EOF
<!DOCTYPE HTML>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$MY_STATUS_TITLE</title>
<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
<meta name="robots" content="noindex, nofollow">
$MY_AUTOREFRESH_TEXT
<link rel="stylesheet" href="$MY_STATUS_STYLESHEET">
<link href="$MY_STATUS_FONTAWESOME" rel="stylesheet">
<!-- custom styling for specific icons -->
<style type="text/css">
	.fa-check {
		background: white;
		color: green;
	}	
	.fa-times {
		background: white;
		color: red;
	}
</style>
</head>
<body>
<div class="container">

<div class="pb-2 mt-5 mb-2 border-bottom">
	<h1>
		$MY_STATUS_TITLE
		<span class="float-right d-none d-sm-block">
			<a href="$MY_HOMEPAGE_URL" class="btn btn-primary" role="button">
				<i class="fas fa-home"></i>
				$MY_HOMEPAGE_TITLE
			</a>
		</span>
	</h1>
</div>

<div class="d-sm-none d-md-none d-lg-none d-xl-none my-3">
	<a href="$MY_HOMEPAGE_URL" class="btn btn-primary" role="button">
		<i class="fas fa-home"></i>
		$MY_HOMEPAGE_TITLE
	</a>
</div>

EOF
}

function page_footer() {
	ELAPSED="$(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
	cat >> "$MY_STATUS_HTML" << EOF
<hr class="mt-4">
<footer>
	<p>$MY_STATUS_FOOTER</p>
	<p class="text-muted">Last checked at $MY_DATE_TIME - 
	<i class="fas fa-stopwatch"></i> 
	Query time of $ELAPSED</p>
</footer>

</div>
<!-- Powered by https://github.com/Cyclenerd/static_status -->
</body>
</html>

EOF
}

function page_alert_success() {
	cat >> "$MY_STATUS_HTML" << EOF
<div class="alert alert-success my-3" role="alert">
	<i class="fas fa-thumbs-up"></i>
	All Systems Operational
</div>

EOF
}

function page_alert_warning() {
	cat >> "$MY_STATUS_HTML" << EOF
<div class="alert alert-warning my-3" role="alert">
	<i class="fas fa-exclamation-triangle"></i>
	Outage
</div>

EOF
}

function page_alert_danger() {
	cat >> "$MY_STATUS_HTML" << EOF
<div class="alert alert-danger my-3" role="alert">
	<i class="fas fa-fire"></i>
	Major Outage
</div>

EOF
}

function page_alert_maintenance() {
	cat >> "$MY_STATUS_HTML" << EOF
<div class="card my-3">
	<div class="card-header">
		<i class="fas fa-wrench"></i>
		Maintenance
	</div>
	<div class="card-body">
EOF
	if [ -r "$MY_MAINTENANCE_TEXT_FILE" ]; then
		cat "$MY_MAINTENANCE_TEXT_FILE" >> "$MY_STATUS_HTML"
	else
		echo ":-(" >> "$MY_STATUS_HTML"
		echo_warning "Cannot read file '$MY_MAINTENANCE_TEXT_FILE'"
	fi
	cat >> "$MY_STATUS_HTML" << EOF
	</div>
</div>
EOF
}

function item_ok() {
	echo '<li class="list-group-item d-flex justify-content-between align-items-center">'

	if [[ -n "${MY_DISPLAY_TEXT}" ]]; then
		echo "${MY_DISPLAY_TEXT}"
	else
		if [[ "$MY_OK_COMMAND" = "ping" ]]; then
			echo "ping $MY_OK_HOSTNAME"
		elif [[ "$MY_OK_COMMAND" = "nc" ]]; then
			echo "$(port_to_name "$MY_OK_PORT") on $MY_OK_HOSTNAME"
		elif [[ "$MY_OK_COMMAND" = "curl" ]]; then
			echo "Site $MY_OK_HOSTNAME"
		elif [[ "$MY_OK_COMMAND" = "http-status" ]]; then
			echo "HTTP status $MY_OK_PORT of $MY_OK_HOSTNAME"
		elif [[ "$MY_OK_COMMAND" = "grep" ]]; then
			echo "Grep for \"$MY_OK_PORT\" on  $MY_OK_HOSTNAME"
		elif [[ "$MY_OK_COMMAND" = "traceroute" ]]; then
			echo "Route path contains $MY_OK_HOSTNAME"
		elif [[ "$MY_OK_COMMAND" = "traceroutevpn" ]]; then
			echo "Route path via VPN contains $MY_OK_HOSTNAME"
		elif [[ "$MY_OK_COMMAND" = "script" ]]; then
			echo "Script $MY_OK_HOSTNAME"
		fi
	fi

	cat <<EOF
	<span class="badge badge-pill badge-light"><i class="fas fa-check"></i></span>
</li>
EOF
}

function item_down() {
	echo '<li class="list-group-item d-flex justify-content-between align-items-center">'

	if [[ -n "${MY_DISPLAY_TEXT}" ]]; then
		echo "${MY_DISPLAY_TEXT}"
	else
		if [[ "$MY_DOWN_COMMAND" = "ping" ]]; then
			echo "ping $MY_DOWN_HOSTNAME"
		elif [[ "$MY_DOWN_COMMAND" = "nc" ]]; then
			echo "$(port_to_name "$MY_DOWN_PORT") on $MY_DOWN_HOSTNAME"
		elif [[ "$MY_DOWN_COMMAND" = "curl" ]]; then
			echo "Site $MY_DOWN_HOSTNAME"
		elif [[ "$MY_DOWN_COMMAND" = "http-status" ]]; then
			echo "HTTP status $MY_DOWN_PORT of $MY_DOWN_HOSTNAME"
		elif [[ "$MY_DOWN_COMMAND" = "grep" ]]; then
			echo "Grep for \"$MY_DOWN_PORT\" on  $MY_DOWN_HOSTNAME"
		elif [[ "$MY_DOWN_COMMAND" = "traceroute" ]]; then
			echo "Route path contains $MY_DOWN_HOSTNAME"
		elif [[ "$MY_DOWN_COMMAND" = "traceroutevpn" ]]; then
			echo "Route path via VPN contains $MY_DOWN_HOSTNAME"
		elif [[ "$MY_DOWN_COMMAND" = "script" ]]; then
			echo "Script $MY_DOWN_HOSTNAME"
		fi
	fi

	printf '<span class="badge badge-pill badge-light"><i class="fas fa-times"></i> '
	if [[ "$MY_DOWN_TIME" -gt "1" ]]; then
		printf "%.0f min</span>" "$((MY_DOWN_TIME/60))"
	else
		echo "</span>"
	fi
	echo "</li>"
}

function item_history() {
	echo '<li class="list-group-item d-flex justify-content-between align-items-center">'
	echo '<span>'

	if [[ -n "${MY_DISPLAY_TEXT}" ]]; then
		echo "${MY_DISPLAY_TEXT}"
	else
		if [[ "$MY_HISTORY_COMMAND" = "ping" ]]; then
			echo "ping $MY_HISTORY_HOSTNAME"
		elif [[ "$MY_HISTORY_COMMAND" = "nc" ]]; then
			echo "$(port_to_name "$MY_HISTORY_PORT") on $MY_HISTORY_HOSTNAME"
		elif [[ "$MY_HISTORY_COMMAND" = "curl" ]]; then
			echo "Site $MY_HISTORY_HOSTNAME"
		elif [[ "$MY_HISTORY_COMMAND" = "http-status" ]]; then
			echo "HTTP status $MY_HISTORY_PORT of $MY_HISTORY_HOSTNAME"
		elif [[ "$MY_HISTORY_COMMAND" = "grep" ]]; then
			echo "Grep for \"$MY_HISTORY_PORT\" on  $MY_HISTORY_HOSTNAME"
		elif [[ "$MY_HISTORY_COMMAND" = "traceroute" ]]; then
			echo "Route path contains $MY_HISTORY_HOSTNAME"
		elif [[ "$MY_HISTORY_COMMAND" = "traceroutevpn" ]]; then
			echo "Route path via VPN contains $MY_HISTORY_HOSTNAME"
		elif [[ "$MY_HISTORY_COMMAND" = "script" ]]; then
			echo "Script $MY_HISTORY_HOSTNAME"
		fi
	fi

	echo '<small class="text-muted">'
	echo "$MY_HISTORY_DATE_TIME"
	echo '</small>'
	echo '</span>'

	printf '<span class="badge badge-pill badge-light"><i class="fas fa-times"></i> '
	if [[ "$MY_HISTORY_DOWN_TIME" -gt "1" ]]; then
		printf "%.0f min</span>" "$((MY_HISTORY_DOWN_TIME/60))"
	else
		echo "</span>"
	fi
	echo "</li>"
}

################################################################################
# MAIN
################################################################################

case "$1" in
"")
	# called without arguments
	;;
"silent")
	BE_QUIET="yes"
	;;
"loud")
	BE_LOUD="yes"
	;;
"h" | "help" | "-h" | "-help" | "-?" | *)
	usage 0
	;;
esac

if [ -e "$MY_STATUS_CONFIG" ]; then
	if [[ "$BE_LOUD" = "yes" ]] || [[ "$BE_QUIET" = "no" ]]; then
		echo "using config from file: $MY_STATUS_CONFIG"
	fi
	# ignore SC1090
	# shellcheck source=/dev/null
	source "$MY_STATUS_CONFIG"
fi

# if a status_hostname_list.txt file hasn't been created use the status_hostname_list-example.txt
if [[ ! -f "$MY_HOSTNAME_FILE" ]]; then
	echo "Using status_hostname_list-example.txt"
	MY_HOSTNAME_FILE="$BASE_PATH/cfg/status_hostname_list-example.txt"
else
	echo "Using $MY_HOSTNAME_FILE"
fi
# if a status_maintenance_text-example.txt file hasn't been created use the status_maintenance_text-example.txt
if [[ ! -f "$MY_MAINTENANCE_TEXT_FILE" ]]; then
	echo "Using status_maintenance_text-example.txt"
	MY_MAINTENANCE_TEXT_FILE="$BASE_PATH/cfg/status_maintenance_text-example.txt"
else
	echo "Using $MY_MAINTENANCE_TEXT_FILE"
fi

check_bash

for MY_COMMAND in "${MY_COMMANDS[@]}"; do
	if [[ "$MY_COMMAND" = "traceroutevpn" ]]; then
		echo "$MY_COMMAND is a custom scripted command. Not an internal command"
	else
		check_command "$MY_COMMAND"
	fi
done


check_lock
set_lock
check_config "$MY_HOSTNAME_FILE"
check_file "$MY_HOSTNAME_STATUS_DOWN"
check_file "$MY_HOSTNAME_STATUS_LASTRUN"
check_file "$MY_HOSTNAME_STATUS_HISTORY"
check_file "$MY_HOSTNAME_STATUS_HISTORY_TEMP_SORT"
check_file "$MY_STATUS_HTML"
check_folder "cfg"
check_folder "cfg/scripts"
check_folder "output"

if cp "$MY_HOSTNAME_STATUS_DOWN" "$MY_HOSTNAME_STATUS_LASTRUN"; then
	get_lastrun_time
else
	exit_with_failure "Cannot copy file '$MY_HOSTNAME_STATUS_DOWN' to '$MY_HOSTNAME_STATUS_LASTRUN'"
fi

{
	echo "# $MY_DATE_TIME"
	echo_do_not_edit
} > "$MY_HOSTNAME_STATUS_OK"
{
	echo "# $MY_DATE_TIME"
	echo_do_not_edit
	echo "timestamp;$MY_TIMESTAMP"
} > "$MY_HOSTNAME_STATUS_DOWN"


#
# Check and save status
#

MY_HOSTNAME_COUNT=0
while IFS=';' read -r MY_COMMAND MY_HOSTNAME_STRING MY_PORT || [[ -n "$MY_COMMAND" ]]; do

	MY_HOSTNAME="${MY_HOSTNAME_STRING%%|*}" # remove alternative display text

	if [[ "$MY_COMMAND" = "ping" ]]; then
		(( MY_HOSTNAME_COUNT++ ))
		# Detect ping Version
		ping &> /dev/null
		# FreeBSD: 64 = ping -t TIMEOUT
		# macOS:   64 = ping -t TIMEOUT
		# GNU:      2 = ping -w TIMEOUT (-t TTL)
		# OpenBSD:  1 = ping -w TIMEOUT (-t TTL)
		if [ $? -gt 2 ]; then
			# BSD ping
			MY_PING_COMMAND='ping -t'
		else
			# GNU or OpenBSD ping
			MY_PING_COMMAND='ping -w'
		fi
		if $MY_PING_COMMAND "$MY_PING_TIMEOUT" -c "$MY_PING_COUNT" "$MY_HOSTNAME" &> /dev/null; then
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" ""
			# Check status change
			if [[ "$MY_DOWN_TIME" -gt "0" ]]; then
				save_history  "$MY_COMMAND" "$MY_HOSTNAME_STRING" "" "$MY_DOWN_TIME" "$MY_DATE_TIME"
			fi
			save_availability "$MY_COMMAND" "$MY_HOSTNAME_STRING" ""
		else
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" ""
			save_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "" "$MY_DOWN_TIME"
		fi
	elif [[ "$MY_COMMAND" = "nc" ]]; then
		(( MY_HOSTNAME_COUNT++ ))
		if nc -z -w "$MY_TIMEOUT" "$MY_HOSTNAME" "$MY_PORT" &> /dev/null; then
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			# Check status change
			if [[ "$MY_DOWN_TIME" -gt "0" ]]; then
				save_history  "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME" "$MY_DATE_TIME"
			fi
			save_availability "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
		else
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			save_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME"
		fi
	elif [[ "$MY_COMMAND" = "curl" ]]; then
		(( MY_HOSTNAME_COUNT++ ))
		if curl -If -L --max-time "$MY_TIMEOUT" "$MY_HOSTNAME" &> /dev/null; then
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" ""
			# Check status change
			if [[ "$MY_DOWN_TIME" -gt "0" ]]; then
				save_history  "$MY_COMMAND" "$MY_HOSTNAME_STRING" "" "$MY_DOWN_TIME" "$MY_DATE_TIME"
			fi
			save_availability "$MY_COMMAND" "$MY_HOSTNAME_STRING" ""
		else
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" ""
			save_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "" "$MY_DOWN_TIME"
		fi
	elif [[ "$MY_COMMAND" = "http-status" ]]; then
		(( MY_HOSTNAME_COUNT++))
		if [[ $(curl -s -L -o /dev/null -I --max-time "$MY_TIMEOUT" -w "%{http_code}" "$MY_HOSTNAME" 2>/dev/null) == "$MY_PORT" ]]; then
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			# Check status change
			if [[ "$MY_DOWN_TIME" -gt "0" ]]; then
				save_history  "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME" "$MY_DATE_TIME"
			fi
			save_availability "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
		else
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			save_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME"
		fi
	elif [[ "$MY_COMMAND" = "grep" ]]; then
		(( MY_HOSTNAME_COUNT++ ))
		if curl -L --no-buffer -fs --max-time "$MY_TIMEOUT" "$MY_HOSTNAME" | grep -q "$MY_PORT"  &> /dev/null; then
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			# Check status change
			if [[ "$MY_DOWN_TIME" -gt "0" ]]; then
				save_history  "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME" "$MY_DATE_TIME"
			fi
			save_availability "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
		else
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			save_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME"
		fi
	elif [[ "$MY_COMMAND" = "traceroute" ]]; then
		(( MY_HOSTNAME_COUNT++ ))
		MY_PORT=${MY_PORT:=64}
		if traceroute -w "$MY_TIMEOUT" -q "$MY_TRACEROUTE_NQUERIES" -m "$MY_PORT" "$MY_TRACEROUTE_HOST" | grep -q "$MY_HOSTNAME"  &> /dev/null; then
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			# Check status change
			if [[ "$MY_DOWN_TIME" -gt "0" ]]; then
				save_history  "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME" "$MY_DATE_TIME"
			fi
			save_availability "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
		else
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			save_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME"
		fi
	elif [[ "$MY_COMMAND" = "traceroutevpn" ]]; then
		(( MY_HOSTNAME_COUNT++ ))
		MY_PORT=${MY_PORT:=64}
		if traceroute -w "$MY_TIMEOUT" -q "$MY_TRACEROUTE_NQUERIES" -m "$MY_PORT" "$MY_TRACEROUTE_HOST_VPN" | grep -q "$MY_HOSTNAME"  &> /dev/null; then
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			# Check status change
			if [[ "$MY_DOWN_TIME" -gt "0" ]]; then
				save_history  "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME" "$MY_DATE_TIME"
			fi
			save_availability "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
		else
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			save_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME"
		fi
	elif [[ "$MY_COMMAND" = "script" ]]; then
		(( MY_HOSTNAME_COUNT++ ))
	if [[ -x "$MY_STATUS_CONFIG_DIR/$MY_HOSTNAME" ]]; then
				cmd="$MY_STATUS_CONFIG_DIR/$MY_HOSTNAME"
	else
				cmd="$MY_HOSTNAME"
	fi
		if "$cmd" &> /dev/null; then
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			# Check status change
			if [[ "$MY_DOWN_TIME" -gt "0" ]]; then
				save_history  "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME" "$MY_DATE_TIME"
			fi
			save_availability "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
		else
			check_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT"
			save_downtime "$MY_COMMAND" "$MY_HOSTNAME_STRING" "$MY_PORT" "$MY_DOWN_TIME"
		fi
	fi

done <"$MY_HOSTNAME_FILE"


#
# Create status page
#

page_header

MY_ITEMS_JSON=()

# Get outage
MY_OUTAGE_COUNT=0
MY_OUTAGE_ITEMS=()
while IFS=';' read -r MY_DOWN_COMMAND MY_DOWN_HOSTNAME_STRING MY_DOWN_PORT MY_DOWN_TIME || [[ -n "$MY_DOWN_COMMAND" ]]; do

	if [[ "$MY_DOWN_COMMAND" = "ping" ]] ||
	   [[ "$MY_DOWN_COMMAND" = "nc" ]] ||
	   [[ "$MY_DOWN_COMMAND" = "curl" ]] ||
	   [[ "$MY_DOWN_COMMAND" = "http-status" ]] ||
	   [[ "$MY_DOWN_COMMAND" = "grep" ]] ||
	   [[ "$MY_DOWN_COMMAND" = "script" ]] ||
	   [[ "$MY_DOWN_COMMAND" = "traceroute" ]] ||
	   [[ "$MY_DOWN_COMMAND" = "traceroutevpn" ]]; then
		MY_DOWN_HOSTNAME="${MY_DOWN_HOSTNAME_STRING%%|*}"
		MY_DISPLAY_TEXT="${MY_DOWN_HOSTNAME_STRING/${MY_DOWN_HOSTNAME}/}"
		MY_DISPLAY_TEXT="${MY_DISPLAY_TEXT:1}"
		(( MY_OUTAGE_COUNT++ ))
		MY_OUTAGE_ITEMS+=("$(item_down)")
		MY_ITEMS_JSON+=("${MY_DISPLAY_TEXT:-${MY_DOWN_HOSTNAME}};$MY_DOWN_COMMAND;Fail")
	fi

done <"$MY_HOSTNAME_STATUS_DOWN"

# Get available systems
MY_AVAILABLE_COUNT=0
MY_AVAILABLE_ITEMS=()
while IFS=';' read -r MY_OK_COMMAND MY_OK_HOSTNAME_STRING MY_OK_PORT || [[ -n "$MY_OK_COMMAND" ]]; do

	if [[ "$MY_OK_COMMAND" = "ping" ]] ||
	   [[ "$MY_OK_COMMAND" = "nc" ]] ||
	   [[ "$MY_OK_COMMAND" = "curl" ]] ||
	   [[ "$MY_OK_COMMAND" = "http-status" ]] ||
	   [[ "$MY_OK_COMMAND" = "grep" ]] ||
	   [[ "$MY_OK_COMMAND" = "script" ]] ||
	   [[ "$MY_OK_COMMAND" = "traceroute" ]] ||
	   [[ "$MY_OK_COMMAND" = "traceroutevpn" ]]; then
		MY_OK_HOSTNAME="${MY_OK_HOSTNAME_STRING%%|*}"
		MY_DISPLAY_TEXT="${MY_OK_HOSTNAME_STRING/${MY_OK_HOSTNAME}/}"
		MY_DISPLAY_TEXT="${MY_DISPLAY_TEXT:1}"
		(( MY_AVAILABLE_COUNT++ ))
		MY_AVAILABLE_ITEMS+=("$(item_ok)")
		MY_ITEMS_JSON+=("${MY_DISPLAY_TEXT:-${MY_OK_HOSTNAME}};$MY_OK_COMMAND;OK")
	fi

done <"$MY_HOSTNAME_STATUS_OK"

# Maintenance text
if [ -s "$MY_MAINTENANCE_TEXT_FILE" ]; then
	page_alert_maintenance
# or status alert
elif [[ "$MY_OUTAGE_COUNT" -gt "$MY_AVAILABLE_COUNT" ]]; then
	page_alert_danger
elif [[ "$MY_OUTAGE_COUNT" -gt "0" ]]; then
	page_alert_warning
else
	page_alert_success
fi

# Outage to HTML
if [[ "$MY_OUTAGE_COUNT" -gt "0" ]]; then
	cat >> "$MY_STATUS_HTML" << EOF
<div class="my-3">
	<ul class="list-group">
		<li class="list-group-item list-group-item-danger">Outage</li>
EOF
	for MY_OUTAGE_ITEM in "${MY_OUTAGE_ITEMS[@]}"; do
		echo "$MY_OUTAGE_ITEM" >> "$MY_STATUS_HTML"
	done
	echo "</ul></div>" >> "$MY_STATUS_HTML"
fi

# Operational to HTML
if [[ "$MY_AVAILABLE_COUNT" -gt "0" ]]; then
	cat >> "$MY_STATUS_HTML" << EOF
<div class="my-3">
	<ul class="list-group">
		<li class="list-group-item list-group-item-success">Operational</li>
EOF
	for MY_AVAILABLE_ITEM in "${MY_AVAILABLE_ITEMS[@]}"; do
		echo "$MY_AVAILABLE_ITEM" >> "$MY_STATUS_HTML"
	done
	echo "</ul></div>" >> "$MY_STATUS_HTML"
fi

# Outage and operational to JSON
if [ -n "$MY_STATUS_JSON" ]; then
	printf "[\n" > "$MY_STATUS_JSON"
	for ((position = 0; position < ${#MY_ITEMS_JSON[@]}; ++position)); do
		IFS=";" read -r -a ITEMS <<< "${MY_ITEMS_JSON[$position]}"
		# shellcheck disable=SC2001
		MY_OUTAGE_ITEM=$(sed -e 's/<[^>]*>//g' <<< "${ITEMS[0]}")
		MY_OUTAGE_ITEM_CMD="${ITEMS[1]}"
		MY_OUTAGE_ITEM_STATUS="${ITEMS[2]}"
		printf '  {\n    "site": "%s",\n    "command": "%s",\n    "status": "%s",\n    "updated": "%s"\n  }' \
				"$MY_OUTAGE_ITEM" "$MY_OUTAGE_ITEM_CMD" "$MY_OUTAGE_ITEM_STATUS" "$MY_DATE_TIME" >> "$MY_STATUS_JSON"
		if [ "$position" -lt "$(( ${#MY_ITEMS_JSON[@]} - 1 ))" ];	then
			printf ",\n" >> "$MY_STATUS_JSON"
		else
			printf "\n" >> "$MY_STATUS_JSON"
		fi
	done
	printf "]" >> "$MY_STATUS_JSON"
fi

# Get history (last 10 incidents)
MY_HISTORY_COUNT=0
MY_HISTORY_ITEMS=()
while IFS=';' read -r MY_HISTORY_COMMAND MY_HISTORY_HOSTNAME_STRING MY_HISTORY_PORT MY_HISTORY_DOWN_TIME MY_HISTORY_DATE_TIME || [[ -n "$MY_HISTORY_COMMAND" ]]; do

	if [[ "$MY_HISTORY_COMMAND" = "ping" ]] ||
	   [[ "$MY_HISTORY_COMMAND" = "nc" ]] ||
	   [[ "$MY_HISTORY_COMMAND" = "curl" ]] ||
	   [[ "$MY_HISTORY_COMMAND" = "http-status" ]] ||
	   [[ "$MY_HISTORY_COMMAND" = "grep" ]] ||
	   [[ "$MY_HISTORY_COMMAND" = "script" ]] ||
	   [[ "$MY_HISTORY_COMMAND" = "traceroute"  ]] ||
	   [[ "$MY_HISTORY_COMMAND" = "traceroutevpn"  ]]; then
		MY_HISTORY_HOSTNAME="${MY_HISTORY_HOSTNAME_STRING%%|*}"
		MY_DISPLAY_TEXT="${MY_HISTORY_HOSTNAME_STRING/${MY_HISTORY_HOSTNAME}/}"
		MY_DISPLAY_TEXT="${MY_DISPLAY_TEXT:1}"
		(( MY_HISTORY_COUNT++ ))
		MY_HISTORY_ITEMS+=("$(item_history)")
	fi
	if [[ "$MY_HISTORY_COUNT" -gt "9" ]]; then
		break
	fi

done <"$MY_HOSTNAME_STATUS_HISTORY"

# History to HTML
if [[ "$MY_HISTORY_COUNT" -gt "0" ]]; then
	cat >> "$MY_STATUS_HTML" << EOF
<div class="pb-2 mt-5 mb-3 border-bottom">
	<h2>Past Incidents</h2>
</div>
<ul class="list-group">
EOF
	for MY_HISTORY_ITEM in "${MY_HISTORY_ITEMS[@]}"; do
		echo "$MY_HISTORY_ITEM" >> "$MY_STATUS_HTML"
	done
	echo "</ul>" >> "$MY_STATUS_HTML"
fi

page_footer

del_lock
echo

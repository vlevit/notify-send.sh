#!/bin/sh
# @file - notify-send.sh
# @brief - drop-in replacement for notify-send with more features
###############################################################################
# Copyright (C) 2015-2021 notify-send.sh authors (see AUTHORS file)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# NOTE: Desktop Notifications Specification
# https://developer.gnome.org/notification-spec/

################################################################################
## Globals (Comprehensive - common.setup)

# Symlink script resolution via coreutils (exists on 95+% of linux systems.)
SELF=$(readlink -n -f "$0");
PROCDIR="$(dirname "$SELF")"; # Process direcotry.
APPNAME="$(basename "$SELF")";
TMP="${XDG_RUNTIME_DIR:-/tmp}";
LOGFILE=${LOGFILE:=$TMP/notify-send.$$.log};
SPEC_VERSION="1.2"; # The current spec version we're targeting.
EXPIRE_TIME=-1;
ID=0;
URGENCY=1;
PRINT_ID=false;
EXPLICIT_CLOSE=false;
CALLER_APPNAME=;
SUMMARY=; BODY=;
AKEYS=; ACMDS=; ACTION_COUNT=0;
HINTS=;

#s=; # Generic temporary string.

# Capability Flags (these are used later with the ${var:=false} matcher)
SERVER_HAS_ACTION_ICONS="false";
SERVER_HAS_ACTIONS="false";
SERVER_HAS_BODY="false";
SERVER_HAS_BODY_HYPERLINKS="false";
SERVER_HAS_BODY_IMAGES="false";
SERVER_HAS_BODY_MARKUP="false";
SERVER_HAS_ICON_MULTI="false";
SERVER_HAS_ICON_STATIC="false";
SERVER_HAS_PERSISTENCE="false";
SERVER_HAS_SOUND="false";

SERVER_NAME=;
SERVER_VENDOR=;
SERVER_VERSION=;
SERVER_SPEC_VERSION=;

################################################################################
## Functions

. "$PROCDIR/common.functions.sh"; # Import shared code.
. "$PROCDIR/common.setup.sh"; # Ensures we have debug and logfile stuff together.

# @describe - Allows you to filter characters from a given string. Note that
#             using multiple strings will concatenate them into the output.
# @example - filter_chars FILTER STRING('s)...
# @arg $1 (STRING's) - The string or strings you wish to sanitize.
# @arg $* FILTER - A string containing all the characters you wish to filter.
# @exitcode 0
filter_chars()
(
	ESCAPES="$1"; DONE=''; f=''; shift;

	OIFS="$IFS";
	IFS="$ESCAPES"; for f in $@; do DONE="$DONE$f"; done;
	IFS="$OIFS";

	printf '%s' "$DONE";
)

# @describe - Allows you to filter shell patterns from a given string. Note that
#             using multiple strings will concatenate them into the output.
#
#             BIG NOTE: It's advised the first string always use tics '' instead
#             of full quotes "", because using full quotes makes it harder to
#             read what the actual pattern will look like after it's gone
#             through two cycles of escape sanitization.
#
# @usage - filter_chars FILTER STRING('s)...
# @arg (STRING's) - The string or strings you wish to sanitize.
# @arg FILTER - A POSIX shell pattern to be removed from the input.
filter_pattern()
(
	FILTER="$1"; DONE=''; f=''; b='';

	shift; TODO="$*";

	while test -n "$TODO"; do
		f="${TODO%%$FILTER*}";
		b="${TODO#*$FILTER}";
		if test "$f" = "$TODO"; then
			DONE="$DONE$TODO"; break;
		fi;
		DONE="$DONE$f";
		TODO="$b";
	done;

	printf '%s' "$DONE";
)

help () {
	echo 'Usage:';
	echo '\tnotify-send.sh [OPTION...] <SUMMARY> [BODY] - creates a notification';
	echo '';
	echo 'Help Options:';
	echo '\t-h|--help                      Show help options.';
	echo '\t-v|--version                   Print version number.';
	echo '\t   --spec-version              Prints the Desktop Notification Spec this script adhears to.';
	echo '';
	echo 'Application Options:';
	echo '\t-u, --urgency=LEVEL            Specifies the urgency level (low, normal, critical).';
	echo '\t-t, --expire-time=TIME         Specifies the timeout in milliseconds at which to expire the notification.';
	echo '\t-f, --force-expire             Forcefully closes the notification when the notification has expired.';
	echo "\t                               This won't work unless the expire time is greater than zero."
	echo '\t-a, --app-name=APP_NAME        Specifies the app name for the icon.';
	echo '\t-i, --icon=ICON[,ICON...]      Specifies an icon filename or stock icon to display.';
	echo '\t-c, --category=TYPE[,TYPE...]  Specifies the notification category.';
	echo '\t-H, --hint=TYPE:NAME:VALUE     Specifies basic extra data to pass. Supports all GDBUS simple primitives.';
	echo "\t-o, --action=LABEL:COMMAND     Specifies an action. Can be passed multiple times. LABEL is usually a button's label.";
	echo "\t                               COMMAND is a script executed when action is invoked within the users default shell.";
	echo '\t-d, --default-action=COMMAND   Specifies the default action which is usually invoked by clicking the notification.';
	echo '\t-l, --close-action=COMMAND     Specifies the action invoked when notification is closed.';
	echo '\t-p, --print-id                 Print the notification ID to the standard output.';
	echo '\t-r, --replace=ID               Replace existing notification.';
	echo '\t-R, --replace-file=FILE        Store and load notification replace ID to/from this file.';
	echo '\t-s, --close=ID                 Close notification.';
	echo '\t    --list-capabilities        Shows a list of all optional notification features supported by the server.'
	echo '\t    --server-info              Prints information about your notification server.';
	echo '';
}

list_capabilities() {
	printf 'Status of server capabilities:\n';
	printf '%s' "\"actions\"         - Status: ";
	if ! $SERVER_HAS_ACTIONS; then printf 'UN'; fi; printf '%b' 'SUPPORTED\n';
	printf '%s' "\"action-icons\"    - Status: ";
	if ! $SERVER_HAS_ACTION_ICONS; then printf 'UN'; fi; printf '%b' 'SUPPORTED\n';
	printf '%s' "\"body\"            - Status: ";
	if ! $SERVER_HAS_BODY; then printf 'UN'; fi; printf '%b' 'SUPPORTED\n';
	printf '%s' "\"body-hyperlinks\" - Status: ";
	if ! $SERVER_HAS_BODY_HYPERLINKS; then printf 'UN'; fi; printf '%b' 'SUPPORTED\n';
	printf '%s' "\"body-images\"     - Status: ";
	if ! $SERVER_HAS_BODY_IMAGES; then printf 'UN'; fi; printf '%b' 'SUPPORTED\n';
	printf '%s' "\"body-markup\"     - Status: ";
	if ! $SERVER_HAS_BODY_MARKUP; then printf 'UN'; fi; printf '%b' 'SUPPORTED\n';

	# NOTE: these are mutually exclusive, so we only need to check one.
	printf '%s' "\"icon-frames\"     - Status: ";
	if $SERVER_HAS_ICON_MULTI; then printf 'MULTI\n';
	elif $SERVER_HAS_ICON_STATIC; then printf 'STATIC\n';
	else printf 'UNSUPPORTED\n';
	fi;

	printf '%s' "\"persistence\"     - Status: ";
	if ! $SERVER_HAS_PERSISTENCE; then printf 'UN'; fi; printf '%b' 'SUPPORTED\n';
	printf '%s' "\"sound\"           - Status: ";
	if ! $SERVER_HAS_SOUND; then printf 'UN'; fi; printf '%b' 'SUPPORTED\n';
	echo;
}

list_server_info() {
	echo "Name:           '$SERVER_NAME'";
	echo "Vendor:         '$SERVER_VENDOR'";
	echo "Server Version: '$SERVER_VERSION'";
	echo "Spec. Version:  '$SERVER_SPEC_VERSION'";
	echo;
}

notify_close () {
	gdbus call --session \
		--dest org.freedesktop.Notifications \
		--object-path /org/freedesktop/Notifications \
		--method org.freedesktop.Notifications.CloseNotification \
		"$1" >&2;
}

process_action () {
	l=0; s=''; c='';

	OIFS="$IFS"; # Split argument into it's fields.
	IFS=":"; for field in $@; do
		case "$l" in
			0) s="$field";;
			1) c="$field";;
			*)
		esac;
		l=$((l+1));
	done;
	if test "$l" -ne 2; then abrt "action syntax is \"NAME:COMMAND\""; fi;
	if test -z "$s"; then abrt "action name cannot be empty."; fi;

	# The user isn't intended to be able to interact with our notifications
	# outside this application, so keep the API simple and use numbers
	# for each custom action.
	ACTION_COUNT="$((ACTION_COUNT + 1))";
	AKEYS="$AKEYS,\"$ACTION_COUNT\",\"$s\"";
	ACMDS="$ACMDS \"$ACTION_COUNT\" \"$(sanitize_quote_escapes "$c")\"";
}

process_category () {
	OIFS="$IFS";
	IFS=','; for c in $@; do
		IFS="$OIFS" process_hint "string:category:$c";
	done;
	IFS="$OIFS";
}

process_capabilities() {
	eval "set $*"; # expand variables from pre-tic-quoted list.\
	for c in $@; do
		case "$c" in
			action-icons)    SERVER_HAS_ACTION_ICONS="true";;
			actions)         SERVER_HAS_ACTIONS="true";;
			body)            SERVER_HAS_BODY="true";;
			body-hyperlinks) SERVER_HAS_BODY_HYPERLINKS="true";;
			body-images)     SERVER_HAS_BODY_IMAGES="true";;
			body-markup)     SERVER_HAS_BODY_MARKUP="true";;
			icon-multi)      SERVER_HAS_ICON_MULTI="true";;
			icon-static)     SERVER_HAS_ICON_STATIC="true";;
			persistence)     SERVER_HAS_PERSISTENCE="true";;
			sound)           SERVER_HAS_SOUND="true";;
		esac;
	done;
}

process_hint() {
	l=0; t=''; n=''; v='';

	# Split argument into it's fields.
	OIFS="$IFS";
	IFS=':'; for field in $@; do
		case "$l" in
			0) t="$field";;
			1) n="$field";;
			2) v="$field";;
		esac;
		l=$((l+1));
	done;

	if test "$l" -ne 3; then abrt "hint syntax is \"TYPE:NAME:VALUE\"."; fi;
	if test -z "$n"; then abrt "hint name cannot be empty."; fi;

	# https://www.alteeve.com/w/List_of_DBus_data_types
	# NOTE: I'm only implementing simple primitives here because I don't think
	#       the notification server will need higher order data types.
	#       I'm also lazy and don't feel like writing the code to parse anything
	#       more challenging. If I see a GH issue for it, I'll consider support.
	case "$t" in
		byte|uint16|uint32|uint64|int16|int32|int64|double|string|boolean) true;;
		BYTE|UINT16|UINT32|UINT64|INT16|INT32|INT64|DOUBLE|STRING|BOOLEAN) true;;
		*) abrt "hint types must be one of the datatypes listed the site below.
https://www.alteeve.com/w/List_of_DBus_data_types";;
	esac;

	# NOTE: Don't actually worry about extra typechecking for hints, since
	#       if someone's using this script, they're probably educated enough
	#       to figure out what GDBUS throws as its error.
	if test "$t" = 'string'; then v="\"$(sanitize_quote_escapes "$v")\""; fi;

	HINTS="$HINTS,\"$n\":<$t $v>";
};

process_server_info() {
	c='';
	eval "set $*"; # expand variables from pre-tic-quoted list.
	SERVER_NAME="$1";
	SERVER_VENDOR="$2";
	SERVER_VERSION="$3";
	SERVER_SPEC_VERSION="$4";
}

# key=default: key:command and key:label, with empty label
# key=close:   key:command, no key:label (no button for the on-close event)
process_special_action() {
	if test -z "$2"; then abrt "Command must not be empty"; fi;
	if test "$1" = 'default'; then
		# That documentation is really hard to read, yes this is correct.
		AKEYS="$AKEYS,\"default\",\"Okay\"";
	fi;

	ACMDS="$ACMDS \"$1\" \"$(sanitize_quote_escapes "$2")\"";
}

process_urgency() {
	case "$1" in
		0|low) URGENCY=0 ;;
		1|normal) URGENCY=1 ;;
		2|critical) URGENCY=2 ;;
		*) abrt "urgency values are ( 0 => low; 1 => normal; 2 => critical )" ;;
	esac;
}

starts_with()
(
	STR="$1" QUERY="$2";
	test "${STR#$QUERY}" != "$STR"; # implicit exit code return.
)

################################################################################
## Main Script

# NOTE: Extra setup of STDIO done in common.lib.#!/bin/sh

# Fetch notification server info.
s="$(gdbus call --session \
		--dest org.freedesktop.Notifications \
		--object-path /org/freedesktop/Notifications \
		--method org.freedesktop.Notifications.GetServerInformation)";

s="$(filter_chars '(),' "$s")";
process_server_info "$s";

# Alert the user if this script is opperating on a newer or older spec version
# than the server.
if test "$SPEC_VERSION" != "$SERVER_SPEC_VERSION"; then
	echo "Warning: This script complies with a different standard than the" >&2;
	echo "         server on your machine, some basic features may be unavailable" >&2;
	echo "         or this script may fail outright. For more information see" >&2;
	echo "         \t'notify-send.sh --server-info'" >&2;
fi;

# Fetch notification server capabilities.
s="$(gdbus call --session \
		--dest org.freedesktop.Notifications \
		--object-path /org/freedesktop/Notifications \
		--method org.freedesktop.Notifications.GetCapabilities)";

s="$(filter_chars '[](),' "$s")";
process_capabilities "$s";

while test "$#" -gt 0; do
	case "$1" in
		#--) positional=true;;
		-h|--help) help; exit;;
		-v|--version) echo "v$VERSION"; exit;;
		#--spec-version) echo "v$SPEC_VERSION"; exit; ;;
		-f|--force-expire) export EXPLICIT_CLOSE=true;;
		-p|--print-id) PRINT_ID=true;;
		--list-capabilities) list_capabilities; exit;;
		--server-info) list_server_info; exit;;
		-u|--urgency|--urgency=*)
			if starts_with "$1" '--urgency='; then s="${1#*=}"; else shift; s="$1"; fi;
			process_urgency "$s";
		;;
		-t|--expire-time|--expire-time=*)
			if starts_with "$1" '--expire-time='; then s="${1#*=}"; else shift; s="$1"; fi;
			EXPIRE_TIME="$s";
		;;
		-a|--app-name|--app-name=*)
			if starts_with "$1" '--app-name='; then s="${1#*=}"; else shift; s="$1"; fi;
			CALLER_APPNAME="$s";
		;;
		-i|--icon|--icon=*)
			if starts_with "$1" '--icon='; then s="${1#*=}"; else shift; s="$1"; fi;

			# NOTE: We don't need to assist the search path at all or modify
			#       the path into a URI, I misunderstood the spec.
			# THEME=$(gsettings get org.gnome.desktop.interface icon-theme)
			# ICON="$(readlink -n -f "$s")";

			ICON="$s";
		;;
		-c|--category|--category=*)
			if starts_with "$1" '--category='; then s="${1#*=}"; else shift; s="$1"; fi;
			process_category "$s";
		;;
		-H|--hint|--hint=*)
			if starts_with "$1" '--hint='; then s="${1#*=}"; else shift; s="$1"; fi;
			process_hint "$s";
		;;
		-o|--action|--action=*)
			if starts_with "$1" '--action='; then s="${1#*=}"; else shift; s="$1"; fi;
			process_action "$s";
		;;
		-d|--default-action|--default-action=*)
			if starts_with "$1" '--default-action='; then s="${1#*=}"; else shift; s="$1"; fi;
			process_special_action default "$s";
		;;
		-l|--close-action|--close-action=*)
			if starts_with "$1" '--close-action='; then s="${1#*=}"; else shift; s="$1"; fi;
			process_special_action close "$s";
		;;
		-r|--replace|--replace=*)
			if starts_with "$1" '--replace='; then s="${1#*=}"; else shift; s="$1"; fi;

			if test "$(typeof "$s")" != "uint" -o "$s" -lt 1; then
				abrt "ID must be a positive integer greater than 0, but was provided \"$s\".";
			fi;

			ID="$s";
		;;
		-R|--replace-file|--replace-file=*)
			if starts_with "$1" '--replace-file='; then s="${1#*=}"; else shift; s="$1"; fi;

			ID_FILE="$s";
			if test -e "$ID_FILE"; then
				read -r ID < "$ID_FILE";
			else
				abrt "file \"$ID_FILE\" couldn't be found.";
			fi;

			if test "$(typeof "$ID")" != "uint" -o "$ID" -lt 1; then
				abrt "ID must be a positive integer greater than 0, but was provided \"$s\".";
			fi;
		;;
		-s|--close|--close=*)
			if starts_with "$1" '--close='; then s="${1#*=}"; else shift; s="$1"; fi;

			if test "$(typeof "$s")" != "uint" -o "$s" -lt 1; then
				abrt "ID must be a positive integer greater than 0, but was provided \"$s\".";
			fi;

			notify_close "$s";
			exit $?;
		;;
		*)
			# NOTE: breaking change from master. Will need to be reflected in
			#       versioning. Before, the postitionals were mobile, but per the
			#       reference, they aren't supposed to be. This simplifies the
			#       application.
			if test "$1" != "${1#-}" ; then
				abrt "unknown option $1";
			fi;

			# TODO: Ensure these exist where necessary. Maybe extend functionality.
			#       Could include some more verbose logging when a user's missing an arg.
			SUMMARY="$1"; # This can be empty, so a null param is fine.

			if $SERVER_HAS_BODY; then
				BODY="$2";
				if $SERVER_HAS_BODY_MARKUP; then
					if $SERVER_HAS_BODY_HYPERLINKS; then
						echo "Warning: The notification service on your device doesn't support" >&2;
						echo "         hyperlinks in it's body text. So they will be filtered out." >&2;
						BODY="$(filter_pattern '<a href="*">' "$BODY")";
						BODY="$(filter_pattern '<a/>' "$BODY")";
					fi;
					if ${SERVER_HAS_BODY_IMAGES:=false}; then
						echo "Warning: The notification service on your device doesn't support" >&2;
						echo "         images in it's body text. So they will be filtered out." >&2;
						BODY="$(filter_pattern '<img */>' "$BODY")";
					fi;
				else
					echo "Warning: The notification service on your device doesn't support" >&2;
					echo "         markup in it's body text. So it will be filtered out." >&2;
					# Filter every markup;
					# NOTE: This isn't a fucking XML AST okay?! I don't have time to write
					#       that in /bin/sh, as cool as that would be. So this may break
					#       in certain circumstances where a user embeds markup not
					#       supported by the spec.
					BODY="$(filter_pattern '<[biu]>' "$BODY")";
					BODY="$(filter_pattern '<a href="*">' "$BODY")";
					BODY="$(filter_pattern '<[biua]/>' "$BODY")";
					BODY="$(filter_pattern '<img */>' "$BODY")";
				fi;
			else
				echo "Warning: Omitting body text because the notification server doesn't support it." >&2;
			fi;

			if test -n "$3"; then
				abrt "unexpected positional argument \"$3\". See \"notify-send.sh --help\".";
			fi;

			s="$#"; # Reuse for temporary storage of shifts remaining.
			shift "$((s - 1))"; # Clear remaining arguments - 1 so the loop stops.
		;;
	esac;
	shift;
done;

# send the dbus message, collect the notification ID
OLD_ID="$ID";
NEW_ID=0;
if ! s="$(gdbus call --session \
	--dest org.freedesktop.Notifications \
	--object-path /org/freedesktop/Notifications \
	--method org.freedesktop.Notifications.Notify \
	"$CALLER_APPNAME" "uint32 $ID" "$ICON" "$SUMMARY" "$BODY" \
	"[${AKEYS#,}]" "{\"urgency\":<byte $URGENCY>$HINTS}" \
	"int32 ${EXPIRE_TIME}")";
then
	abrt "\`gdbus\` failed with:: $s";
fi;

# process the ID
s="${s%,*}"; NEW_ID="${s#* }";


if test "$(typeof "$NEW_ID")" != "uint" -o "$NEW_ID" -lt 1; then
	abrt "invalid notification ID from \`gdbus\`.";
fi;

test "$OLD_ID" -gt 1 || ID=${NEW_ID};

if test -n "$ID_FILE" -a "$OLD_ID" -lt 1; then
	echo "$ID" > "$ID_FILE";
fi;

if $PRINT_ID; then
	echo "$ID";
fi;

if test -n "$ACMDS"; then
	# bg task to monitor dbus and perform the actions
	# Uses field expansion to form string based array.
	# Also, use deterministic execution for the rare instance where
	# the filesystem doesn't support linux executable permissions bit,
	# or it's been left unset.
	eval "setsid /bin/sh $PROCDIR/notify-action.sh $ID $ACMDS >&- <&- &";
else
	# Since we know there won't be any scripts to inherit the log files from,
	# we can use a conditional trap to cleanup on exit. Ignore cleanup if we're
	# debugging.
	if ! $DEBUG; then trap "cleanup_pipes" 0; fi;
fi;

# bg task to wait expire time and then actively close notification
if $EXPLICIT_CLOSE && test "$EXPIRE_TIME" -ge 0; then
	# Expire timeout for gdbus call is in milliseconds
	# If the expire time is less than an NTSC standard frame,
	# it's hardly worth waiting the time to execute this since
	# based on external factors, you probably won't see it anyway.
	if test "$EXPIRE_TIME" -gt "33"; then sleep "$((EXPIRE_TIME / 1000))"; fi;
	notify_close "$ID";
fi;

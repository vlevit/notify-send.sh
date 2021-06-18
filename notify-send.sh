#!/bin/sh
# @file - notify-send.sh
# @brief - drop-in replacement for notify-send with more features
###############################################################################
# Copyright (C) 2015-2020 notify-send.sh authors (see AUTHORS file)
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
SELF=$(readlink -n -f $0);
PROCDIR="$(dirname "$SELF")"; # Process direcotry.
APP_NAME="$(basename "$SELF")";
TMP="${XDG_RUNTIME_DIR:-/tmp}";
EXPIRE_TIME=-1;
ID=0;
URGENCY=1;
PRINT_ID=false;
EXPLICIT_CLOSE=false;
#positional=false;
SUMMARY=; BODY=;
AKEYS=; ACMDS=; ACTION_COUNT=0;
HINTS=;

################################################################################
## Functions

. $PROCDIR/common.functions.sh; # Import shared code.
. $PROCDIR/common.setup.sh; # Ensures we have debug and logfile stuff together.

# @describe - Allows you to filter characters from a given string. Note that
#             using multiple strings will concatenate them into the output.
# @usage - filter_chars FILTER STRING('s)...
# @param (STRING's) - The string or strings you wish to sanitize.
# @param FILTER - The number of passes to run sanitization, default is 1.
filter_chars(){
	local ESCAPES="$1" DONE= f=; shift;

	OIFS="$IFS";
	IFS="$ESCAPES"; for f in $*; do DONE="$DONE$f"; done;
	IFS="$OIFS";

	printf '%s' "$DONE";
}

help () {
	echo 'Usage:';
	echo '\tnotify-send.sh [OPTION...] <SUMMARY> [BODY] - create a notification';
	echo '';
	echo 'Help Options:';
	echo '\t-h|--help                      Show help options.';
	echo '\t-v|--version                   Print version number.';
	echo '';
	echo 'Application Options:';
	echo '\t-u, --urgency=LEVEL            Specifies the urgency level (low, normal, critical).';
	echo '\t-t, --expire-time=TIME         Specifies the timeout in milliseconds at which to expire the notification.';
	echo '\t-f, --force-expire             Forcefully closes the notification when the notification has expired.';
	echo '\t-a, --app-name=APP_NAME        Specifies the app name for the icon.';
	echo '\t-i, --icon=ICON[,ICON...]      Specifies an icon filename or stock icon to display.';
	echo '\t-c, --category=TYPE[,TYPE...]  Specifies the notification category.';
	echo '\t-H, --hint=TYPE:NAME:VALUE     Specifies basic extra data to pass. Valid types are int, double, string and byte.';
	echo "\t-o, --action=LABEL:COMMAND     Specifies an action. Can be passed multiple times. LABEL is usually a button's label.";
	echo "\t                               COMMAND is a shell script executed when action is invoked with the calling users default shell.";
	echo '\t-d, --default-action=COMMAND   Specifies the default action which is usually invoked by clicking the notification.';
	echo '\t-l, --close-action=COMMAND     Specifies the action invoked when notification is closed.';
	echo '\t-p, --print-id                 Print the notification ID to the standard output.';
	echo '\t-r, --replace=ID               Replace existing notification.';
	echo '\t-R, --replace-file=FILE        Store and load notification replace ID to/from this file.';
	echo '\t-s, --close=ID                 Close notification.';
	echo '';
}

starts_with(){
	local STR="$1" QUERY="$2";
	test "${STR#$QUERY}" != "$STR"; # implicit exit code return.
}

notify_close () {
	test "$2" -lt 1 || sleep "$(expr substr "$2" 0 $((${#2} - 3)))";
	gdbus call $NOTIFY_ARGS --method org.freedesktop.Notifications.CloseNotification "$1" >&-;
}

process_urgency () {
	case "$1" in
		0|low) URGENCY=0 ;;
		1|normal) URGENCY=1 ;;
		2|critical) URGENCY=2 ;;
		*) abrt "urgency values are ( 0 => low; 1 => normal; 2 => critical )" ;;
	esac;
}

process_category () {
	local todo="$@" c=;
	while test -n "$todo"; do
		c="${todo%%,*}";
		process_hint "string:category:$c";
		test "$todo" = "${todo#*,}" && break || todo="${todo#*,}";
	done;
}

process_hint () {
	local l=0 todo="$@" field= t= n= v=;

	# Split argument into it's fields.
	while test -n "$todo"; do
		field="${todo%%:*}";
		case "$l" in
			0) t="$field";;
			1) n="$field";;
			2) v="$field";;
		esac;
		l=$((l+1));
		if test "$todo" = "${todo#*:}"; then todo=; else todo="${todo#*:}"; fi;
	done;
	test "$l" -eq 3 || abrt "hint syntax is \"TYPE:NAME:VALUE\".";

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

	test -n "$n" || abrt "hint name cannot be empty.";

	# NOTE: Don't actually worry about extra typechecking for hints, since
	#       if someone's using this script, they're probably educated enough
	#       to figure out what GDBUS throws as its error.
	if test "$t" = 'string'; then
		# Add quote buffer to string values
		v="\"$(sanitize_quote_escapes "$2")\"";
	fi;

	HINTS="$HINTS,\"$n\":<$t $v>";
}

process_capabilities() {
	local c=;
	eval "set $*"; # expand variables from pre-tic-quoted list.\
	for c in $*; do
		case "$c" in
			*) true; # Pass for now, need to back up my work.
		esac;
	done;
}

process_action () {
	local l=0 todo="$@" field= s= c=;

	# Split argument into it's fields.
	while test -n "$todo"; do
		field="${todo%%:*}";
		case "$l" in
			0) s="$field";;
			1) c="$field";;
		esac;
		l=$((l+1));
		test "$todo" = "${todo#*:}" && break || todo="${todo#*:}";
	done;
	test "$l" -eq 2 || abrt "action syntax is \"NAME:COMMAND\"";

	test -n "$s" || abrt "action name cannot be empty.";

	# The user isn't intended to be able to interact with our notifications
	# outside this application, so keep the API simple and use numbers
	# for each custom action.
	ACTION_COUNT="$((ACTION_COUNT + 1))";
	AKEYS="$AKEYS,\"$ACTION_COUNT\",\"$s\"";
	ACMDS="$ACMDS \"$ACTION_COUNT\" \"$(sanitize_quote_escapes "$c")\"";
}

# key=default: key:command and key:label, with empty label
# key=close:   key:command, no key:label (no button for the on-close event)
process_special_action () {
	test -n "$2" || abrt "Command must not be empty";
	if test "$1" = 'default'; then
		# That documentation is really hard to read, yes this is correct.
		AKEYS="$AKEYS,\"default\",\"Okay\"";
	fi;

	ACMDS="$ACMDS \"$1\" \"$(sanitize_quote_escapes "$2")\"";
}

################################################################################
## Main Script

# NOTE: Extra setup of STDIO done in common.lib.sh

# Fetch notification server capabilities.
s="$(gdbus call --session \
		--dest org.freedesktop.Notifications \
		--object-path /org/freedesktop/Notifications \
		--method org.freedesktop.Notifications.GetCapabilities)";

# Filter unnecessary characters.
s="$(filter_chars '[](),' "$s")";
process_capabilities "$s";

while test "$#" -gt 0; do
	case "$1" in
		#--) positional=true;;
		-h|--help) help; exit 0;;
		-v|--version) echo "v$VERSION"; exit 0;;
		-f|--force-expire) export EXPLICIT_CLOSE=true;;
		-p|--print-id) PRINT_ID=true;;
		-u|--urgency|--urgency=*)
			starts_with "$1" '--urgency=' && s="${1#*=}" || { shift; s="$1"; };
			process_urgency "$s";
		;;
		-t|--expire-time|--expire-time=*)
			starts_with "$1" '--expire-time=' && s="${1#*=}" || { shift; s="$1"; };
			EXPIRE_TIME="$s";
		;;
		-a|--app-name|--app-name=*)
			starts_with "$1" '--app-name=' && s="${1#*=}" || { shift; s="$1"; };
			export APP_NAME="$s";
		;;
		-i|--icon|--icon=*)
			starts_with "$1" '--icon=' && s="${1#*=}" || { shift; s="$1"; };
			ICON="$s";
		;;
		-c|--category|--category=*)
			starts_with "$1" '--category=' && s="${1#*=}" || { shift; s="$1"; };
			process_category "$s";
		;;
		-H|--hint|--hint=*)
			starts_with "$1" '--hint=' && s="${1#*=}" || { shift; s="$1"; };
			process_hint "$s";
		;;
		-o|--action|--action=*)
			starts_with "$1" '--action=' && s="${1#*=}" || { shift; s="$1"; };
			process_action "$s";
		;;
		-d|--default-action|--default-action=*)
			starts_with "$1" '--default-action=' && s="${1#*=}" || { shift; s="$1"; };
			process_special_action default "$s";
		;;
		-l|--close-action|--close-action=*)
			starts_with "$1" '--close-action=' && s="${1#*=}" || { shift; s="$1"; };
			process_special_action close "$s";
		;;
		-r|--replace|--replace=*)
			starts_with "$1" '--replace=' && s="${1#*=}" || { shift; s="$1"; };

			test "$(typeof "$s")" = "uint" -a "$s" -gt 0 || \
				abrt "ID must be a positive integer greater than 0, but was provided \"$s\".";

			ID="$s";
		;;
		-R|--replace-file|--replace-file=*)
			starts_with "$1" '--replace-file=' && s="${1#*=}" || { shift; s="$1"; };

			ID_FILE="$s"; ! test -s "$ID_FILE" || read ID < "$ID_FILE";
		;;
		-s|--close|--close=*)
			starts_with "$1" '--close=' && s="${1#*=}" || { shift; s="$1"; };

			test "$(typeof "$s")" = "uint" -a "$s" -gt 0 || \
				abrt "ID must be a positive integer greater than 0, but was provided \"$s\".";

			ID="$s";

			notify_close "$ID" "0";
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
			BODY="$2";

			# Alert the user we weren't expecting any more arguments.
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
	"$APP_NAME" "uint32 $ID" "$ICON" "$SUMMARY" "$BODY" \
	"[${AKEYS#,}]" "{\"urgency\":<byte $URGENCY>$HINTS}" \
	"int32 ${EXPIRE_TIME}")";
then
	abrt "\`gdbus\` failed with:: $s";
fi;

# process the ID
s="${s%,*}"; NEW_ID="${s#* }";


if ! ( test "$(typeof "$NEW_ID")" = "uint" && test "$NEW_ID" -gt 1 ); then
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
	# or it's been left unset by a package manager.
	eval "/bin/sh $PROCDIR/notify-action.sh $ID $ACMDS >&- <&- &";
fi;

# bg task to wait expire time and then actively close notification
if $EXPLICIT_CLOSE && test "$EXPIRE_TIME" -gt 0; then
	/bin/sh "$SELF" -t "$EXPIRE_TIME" -s "$ID" >&- <&- & #  2>&-
fi;

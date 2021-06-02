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
## Globals (Comprehensive)

# Symlink script resolution via coreutils
SELF="/"$(readlink -n -f $0); x=${SELF%/*}; x=${x#/}; x=${x:-.};
PROCDIR=$(cd "$x"; pwd); # Process direcotry.
APP_NAME=${SELF##*/};
TMP=${XDG_RUNTIME_DIR:-/tmp};
VERSION="2.0.0-rc.m3tior"; # Changed to semantic versioning.
ACTION_SH=$PROCDIR/notify-action.sh
NOTIFY_ARGS="--session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications";
EXPIRE_TIME=-1;
ID=0;
URGENCY=1;
PRINT_ID=false
EXPLICIT_CLOSE=false
positional=false
summary_set=false
AKEYS=()
ACMDS=()
HINTS=()
SUMMARY=
BODY=
_r=

################################################################################
## Functions

echo(){ printf '%b' "$*\n"; }
abrt () { echo "$SELF: $*" >&2; exit 1; }

help () {
	echo 'Usage:';
	echo '\tnotify-send.sh [OPTION...] <SUMMARY> [BODY] - create a notification';
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
	echo "\t-o, --action=LABEL:COMMAND     Specifies an action. Can be passed multiple times. LABEL is usually a button's label. COMMAND is a shell command executed when action is invoked.";
	echo '\t-d, --default-action=COMMAND   Specifies the default action which is usually invoked by clicking the notification.';
	echo '\t-l, --close-action=COMMAND     Specifies the action invoked when notification is closed.';
	echo '\t-p, --print-id                 Print the notification ID to the standard output.';
	echo '\t-r, --replace=ID               Replace existing notification.';
	echo '\t-R, --replace-file=FILE        Store and load notification replace ID to/from this file.';
	echo '\t-s, --close=ID                 Close notification.';
}


is_int() {
	case "$1" in
		''|*[!0-9]*) return 1;;
		*) return 0;;
	esac;
}

starts_with(){
	local STR;   STR="$1";
	local QUERY; QUERY="$2";
	test "${STR#$QUERY}" != "$STR";
	return $?; # This may be redundant, but I'm doing it anyway for my sanity.
}

notify_close () {
	i=${2} ;((${i}>0)) && sleep ${i:0:-3}.${i:$((${#i}-3))}
	gdbus call ${NOTIFY_ARGS[@]} --method org.freedesktop.Notifications.CloseNotification "${1}" >&-
}

process_urgency () {
	case "$1" in
		0|low) URGENCY=0 ;;
		1|normal) URGENCY=1 ;;
		2|critical) URGENCY=2 ;;
		*) abrt "Urgency values: 0 low 1 normal 2 critical" ;;
	esac
}

process_category () {
	local a c; IFS=, a=(${1});
	for c in "${a[@]}"; do
		make_hint string category "${c}" && HINTS+=(${_r})
	done
}

make_hint () {
	_r= ;local t=${1} n=${2} c=${3}
	[[ ${t} =~ ^(byte|int32|double|string)$ ]] || abrt "Hint types: byte int32 double string"
	[[ ${t} = string ]] && c="\"${3}\""
	_r="\"${n}\":<${t} ${c}>"
}

process_hint () {
	local a ;IFS=: a=(${1})
	((${#a[@]}==3)) || abrt "Hint syntax: \"TYPE:NAME:VALUE\""
	make_hint "${a[0]}" "${a[1]}" "${a[2]}" && HINTS+=(${_r})
}

process_action () {
	local a k ;IFS=: a=(${1})
	((${#a[@]}==2)) || abrt "Action syntax: \"NAME:COMMAND\""
	k=${#AKEYS[@]}
	AKEYS+=("\"${k}\",\"${a[0]}\"")
	ACMDS+=("${k}" "${a[1]}")
}

# key=default: key:command and key:label, with empty label
# key=close:   key:command, no key:label (no button for the on-close event)
process_special_action () {
	[[ "${2}" ]] || abrt "Command must not be empty"
	[[ "${1}" != "close" ]] && AKEYS+=("\"${1}\",\"\"")
	ACMDS+=("${1}" "${2}")
}

process_posargs () {
	[[ "${1}" = -* ]] && ! ${positional} && abrt "Unknown option ${1}"
	${summary_set} && BODY=${1} || SUMMARY=${1} summary_set=true
}

################################################################################
## Main Script

${DEBUG_NOTIFY_SEND:=false} && {
	exec 2>${TMP}/.${SELF}.${$}.e
	set -x
	trap "set >&2" 0
}

while test "$#" -gt 0; do
	# s= i=0
	case "$1" in
		--) positional=true;;
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
			export APP_NAME=$s;
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
			ID="$s";
		;;
		-R|--replace-file|--replace-file=*)
			starts_with "$1" '--replace-file=' && s="${1#*=}" || { shift; s="$1"; };
			ID_FILE="$s"; ! test -s "$ID_FILE" || read ID < "$ID_FILE";
		;;
		-s|--close|--close=*)
			starts_with "$1" '--close=' && i="${1#*=}" || { shift; i="$1"; };
			! is_int "$ID" || abrt 'ID should be an integer but was provided "$i".';
			if test "$i" -lt 1 -a "$ID" -gt 0; then i="$ID"; fi;

			# This has to look weird bc -e safe mode demands it.
			test "$i" -gt 0 && notify_close "$i" "$EXPIRE_TIME" || exit "$?";
			exit;
		;;
		*)
			process_posargs "$1";
		;;
	esac;
	shift;
done;

# build the actions & hints strings
a= ;for s in "${AKEYS[@]}" ;do a+=,${s} ;done ;a=${a:1}
make_hint byte urgency "${URGENCY}" ;h=${_r}
for s in "${HINTS[@]}" ;do h+=,${s} ;done

# send the dbus message, collect the notification ID
typeset -i OLD_ID=${ID} NEW_ID=0
s=$(gdbus call ${NOTIFY_ARGS[@]} \
	--method org.freedesktop.Notifications.Notify \
	"${APP_NAME}" ${ID} "${ICON}" "${SUMMARY}" "${BODY}" \
	"[${a}]" "{${h}}" "int32 ${EXPIRE_TIME}")

# process the ID
s=${s%,*} NEW_ID=${s#* }
((${NEW_ID}>0)) || abrt "invalid notification ID from gdbus"
((${OLD_ID}>0)) || ID=${NEW_ID}
[[ "${ID_FILE}" ]] && ((${OLD_ID}<1)) && echo ${ID} > "${ID_FILE}"
${PRINT_ID} && echo ${ID}

# bg task to monitor dbus and perform the actions
((${#ACMDS[@]}>0)) && setsid -f "${ACTION_SH}" ${ID} "${ACMDS[@]}" >&- 2>&- &

# bg task to wait expire time and then actively close notification
${EXPLICIT_CLOSE} && ((${EXPIRE_TIME}>0)) && setsid -f "${0}" -t ${EXPIRE_TIME} -s ${ID} >&- 2>&- <&- &

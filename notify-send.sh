#!/usr/bin/env bash

# notify-send.sh - drop-in replacement for notify-send with more features
# Copyright (C) 2015-2020 notify-send.sh authors (see AUTHORS file)

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Desktop Notifications Specification
# https://developer.gnome.org/notification-spec/

SELF=${0##*/}
TMP=${XDG_RUNTIME_DIR:-/tmp}
${DEBUG_NOTIFY_SEND:=false} && {
	exec 2>${TMP}/.${SELF}.${$}.e
	set -x
	trap "set >&2" 0
}

VERSION=1.1-bkw777
ACTION_SH=${0%/*}/notify-action.sh
NOTIFY_ARGS=(--session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications)

typeset -i i=0 ID=0 EXPIRE_TIME=-1 URGENCY=1
unset ID_FILE
AKEYS=()
ACMDS=()
HINTS=()
APP_NAME=${SELF}
PRINT_ID=false
EXPLICIT_CLOSE=false
SUMMARY=
BODY=
positional=false
summary_set=false

abrt () { echo "${0}: ${@}" >&2 ; exit 1 ; }

help () {
	cat <<EOF
Usage:
  notify-send.sh [OPTION...] <SUMMARY> [BODY] - create a notification

Help Options:
  -?|--help                         Show help options

Application Options:
  -u, --urgency=LEVEL               Specifies the urgency level (low, normal, critical).
  -t, --expire-time=TIME            Specifies the timeout in milliseconds at which to expire the notification.
  -f, --force-expire                Forcefully closes the notification when the notification has expired.
  -a, --app-name=APP_NAME           Specifies the app name for the icon.
  -i, --icon=ICON[,ICON...]         Specifies an icon filename or stock icon to display.
  -c, --category=TYPE[,TYPE...]     Specifies the notification category.
  -h, --hint=TYPE:NAME:VALUE        Specifies basic extra data to pass. Valid types are int, double, string and byte.
  -o, --action=LABEL:COMMAND        Specifies an action. Can be passed multiple times. LABEL is usually a button's label. COMMAND is a shell command executed when action is invoked.
  -d, --default-action=COMMAND      Specifies the default action which is usually invoked by clicking the notification.
  -l, --close-action=COMMAND        Specifies the action invoked when notification is closed.
  -p, --print-id                    Print the notification ID to the standard output.
  -r, --replace=ID                  Replace existing notification.
  -R, --replace-file=FILE           Store and load notification replace ID to/from this file.
  -s, --close=ID                    Close notification.
  -v, --version                     Version of the package.

EOF
}

convert_type () {
	case "$1" in
		int) echo int32 ;;
		double|string|byte) echo "$1" ;;
		*) echo error; return 1 ;;
	esac
}

make_action_key () {
	echo "$(tr -dc _A-Z-a-z-0-9 <<< \"$1\")${RANDOM}"
}

make_action () {
	local action_key="$1"
	printf -v text "%q" "$2"
	echo "\"$action_key\", \"$text\""
}

make_hint () {
	type=$(convert_type "$1")
	[[ ! $? = 0 ]] && return 1
	name="$2"
	[[ "$type" = string ]] && command="\"$3\"" || command="$3"
	echo "\"$name\": <$type $command>"
}

concat_actions () {
	local result="$1"
	shift
	for s in "$@"; do
		result="$result, $s"
	done
	echo "[$result]"
}

concat_hints () {
	local result="$1"
	shift
	for s in "$@"; do
		result="$result, $s"
	done
	echo "{$result}"
}

notify_close () {
	i=${2} ;((${i}>0)) && sleep ${i:0:-3}.${i:$((${#i}-3))}
	gdbus call "${NOTIFY_ARGS[@]}" --method org.freedesktop.Notifications.CloseNotification "${1}" >/dev/null
}

process_urgency () {
	case "$1" in
		low) URGENCY=0 ;;
		normal) URGENCY=1 ;;
		critical) URGENCY=2 ;;
		*) abrt "Unknown urgency $URGENCY specified. Known urgency levels: low, normal, critical." ;;
	esac
}

process_category () {
	IFS=, read -a categories <<< "$1"
	for category in "${categories[@]}"; do
		hint="$(make_hint string category "$category")"
		HINTS=("${HINTS[@]}" "$hint")
	done
}

process_hint () {
	IFS=: read type name command <<< "$1"
	[[ "$name" ]] && [[ "$command" ]] || abrt "Invalid hint syntax specified. Use TYPE:NAME:VALUE."
	hint="$(make_hint "$type" "$name" "$command")"
	[[ $? = 0 ]] || abrt "Invalid hint type \"$type\". Valid types are int, double, string and byte."
	HINTS=("${HINTS[@]}" "$hint")
}

process_action () {
	IFS=: read name command <<<"$1"
	[[ "$name" ]] && [[ "$command" ]] || abrt "Invalid action syntax specified. Use NAME:COMMAND."

	local action_key="$(make_action_key "$name")"
	ACMDS=("${ACMDS[@]}" "$action_key" "$command")

	local action="$(make_action "$action_key" "$name")"
	AKEYS=("${AKEYS[@]}" "$action")
}

# key=default: key:command and key:label, with empty label
# key=close:   key:command, no key:label (no button for the on-close event)
process_special_action () {
	action_key="$1"
	command="$2"

	[[ "$action_key" ]] && [[ "$command" ]] || abrt "Command must not be empty"

	ACMDS=("${ACMDS[@]}" "$action_key" "$command")

	[[ "$action_key" != close ]] && {
		local action="$(make_action "$action_key" "$name")"
		AKEYS=("${AKEYS[@]}" "$action")
	}
}

process_posargs () {
	[[ "${1}" = -* ]] && ! ${positional} && abrt "Unknown option ${1}"
	${summary_set} && BODY=${1} || SUMMARY=${1} summary_set=true
}

while ((${#})) ; do
	s= i=0
	case "${1}" in
		-\?|--help)
			help
			exit 0
			;;
		-v|--version)
			echo "${SELF} ${VERSION}"
			exit 0
			;;
		-u|--urgency|--urgency=*)
			[[ "${1}" = --urgency=* ]] && s=${1#*=} || { shift ;s=${1} ; }
			process_urgency "${s}"
			;;
		-t|--expire-time|--expire-time=*)
			[[ "${1}" = --expire-time=* ]] && EXPIRE_TIME=${1#*=} || { shift ;EXPIRE_TIME=${1} ; }
			;;
		-f|--force-expire)
			export EXPLICIT_CLOSE=true
			;;
		-a|--app-name|--app-name=*)
			[[ "${1}" = --app-name=* ]] && APP_NAME=${1#*=} || { shift ;APP_NAME=${1} ; }
			export APP_NAME
			;;
		-i|--icon|--icon=*)
			[[ "${1}" = --icon=* ]] && ICON=${1#*=} || { shift ;ICON=${1} ; }
			;;
		-c|--category|--category=*)
			[[ "${1}" = --category=* ]] && s=${1#*=} || { shift ;s=${1} ; }
			process_category "${s}"
			;;
		-h|--hint|--hint=*)
			[[ "${1}" = --hint=* ]] && s=${1#*=} || { shift ;s=${1} ; }
			process_hint "${s}"
			;;
		-o|--action|--action=*)
			[[ "${1}" == --action=* ]] && s=${1#*=} || { shift ;s=${1} ; }
			process_action "${s}"
			;;
		-d|--default-action|--default-action=*)
			[[ "${1}" == --default-action=* ]] && s=${1#*=} || { shift ;s=${1} ; }
			process_special_action default "${s}"
			;;
		-l|--close-action|--close-action=*)
			[[ "${1}" == --close-action=* ]] && s=${1#*=} || { shift ;s=${1} ; }
			process_special_action close "${s}"
			;;
		-p|--print-id)
			PRINT_ID=true
			;;
		-r|--replace|--replace=*)
			[[ "${1}" = --replace=* ]] && ID=${1#*=} || { shift ;ID=${1} ; }
			;;
		-R|--replace-file|--replace-file=*)
			[[ "${1}" = --replace-file=* ]] && ID_FILE=${1#*=} || { shift ;ID_FILE=${1} ; }
			[[ -s ${ID_FILE} ]] && read ID < "${ID_FILE}"
			;;
		-s|--close|--close=*)
			[[ "${1}" = --close=* ]] && i=${1#*=} || { shift ;i=${1} ; }
			((${i}<1)) && ((${ID}>0)) && i=${ID}
			((${i}>0)) && notify_close ${i} ${EXPIRE_TIME}
			exit ${?}
			;;
		--)
			positional=true
			;;
		*)
			process_posargs "${1}"
			;;
	esac
	shift
done

# build the actions & hints strings
HINTS=("$(make_hint byte urgency "$URGENCY")" "${HINTS[@]}")
actions="$(concat_actions "${AKEYS[@]}")"
hints="$(concat_hints "${HINTS[@]}")"

# send the dbus message, collect the notification ID
typeset -i OLD_ID=${ID} NEW_ID=0
s=$(gdbus call "${NOTIFY_ARGS[@]}"  \
	--method org.freedesktop.Notifications.Notify \
	"$APP_NAME" "$ID" "$ICON" "$SUMMARY" "$BODY" \
	"${actions}" "${hints}" "int32 $EXPIRE_TIME")

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

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

EXPIRE_TIME=-1
APP_NAME=${SELF}
REPLACE_ID=0
URGENCY=1
HINTS=()
SUMMARY_SET=n

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

parse_notification_id () {
	sed 's/(uint32 \([0-9]\+\),)/\1/g'
}

notify () {
	local actions="$(concat_actions "${ACTIONS[@]}")"
	local hints="$(concat_hints "${HINTS[@]}")"

	NOTIFICATION_ID=$(gdbus call "${NOTIFY_ARGS[@]}"  \
		--method org.freedesktop.Notifications.Notify \
		"$APP_NAME" "$REPLACE_ID" "$ICON" "$SUMMARY" "$BODY" \
		"${actions}" "${hints}" "int32 $EXPIRE_TIME" \
		| parse_notification_id)

	[[ -n "$STORE_ID" ]] && echo "$NOTIFICATION_ID" > $STORE_ID

	[[ -n "$PRINT_ID" ]] && echo "$NOTIFICATION_ID"

	[[ -n "$FORCE_EXPIRE" ]] && {
		type bc &> /dev/null || abrt "bc command not found. Please install bc package."
		SLEEP_TIME="$(bc <<< "scale=3; $EXPIRE_TIME / 1000")"
		( sleep "$SLEEP_TIME" ; notify_close "$NOTIFICATION_ID" ) &
	}

	maybe_run_action_handler
}

notify_close () {
	gdbus call "${NOTIFY_ARGS[@]}"  --method org.freedesktop.Notifications.CloseNotification "$1" >/dev/null
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

maybe_run_action_handler () {
	[[ -n "$NOTIFICATION_ID" ]] && [[ -n "$ACTION_COMMANDS" ]] && {
		[[ -x "$ACTION_SH" ]] && {
			"$ACTION_SH" "$NOTIFICATION_ID" "${ACTION_COMMANDS[@]}" &
			exit 0
		} || {
			abrt "executable file not found: $notify_action"
		}
	}
}

process_action () {
	IFS=: read name command <<<"$1"
	[[ "$name" ]] && [[ "$command" ]] || abrt "Invalid action syntax specified. Use NAME:COMMAND."

	local action_key="$(make_action_key "$name")"
	ACTION_COMMANDS=("${ACTION_COMMANDS[@]}" "$action_key" "$command")

	local action="$(make_action "$action_key" "$name")"
	ACTIONS=("${ACTIONS[@]}" "$action")
}

process_special_action () {
	action_key="$1"
	command="$2"

	[[ "$action_key" ]] && [[ "$command" ]] || abrt "Command must not be empty"

	ACTION_COMMANDS=("${ACTION_COMMANDS[@]}" "$action_key" "$command")

	[[ "$action_key" != close ]] && {
		local action="$(make_action "$action_key" "$name")"
		ACTIONS=("${ACTIONS[@]}" "$action")
	}
}

process_posargs () {
	[[ "$1" = -* ]] && ! [[ "$positional" = yes ]] && abrt "Unknown option $1"

	[[ "$SUMMARY_SET" = n ]] && {
		SUMMARY="$1"
		SUMMARY_SET=y
	} || {
		BODY="$1"
	}
}

while (( $# > 0 )) ; do
	case "$1" in
		-\?|--help)
			help
			exit 0
			;;
		-v|--version)
			echo "${0##*/} $VERSION"
			exit 0
			;;
		-u|--urgency|--urgency=*)
			[[ "$1" = --urgency=* ]] && urgency="${1#*=}" || { shift; urgency="$1"; }
			process_urgency "$urgency"
			;;
		-t|--expire-time|--expire-time=*)
			[[ "$1" = --expire-time=* ]] && EXPIRE_TIME="${1#*=}" || { shift; EXPIRE_TIME="$1"; }
			[[ "$EXPIRE_TIME" =~ ^-?[0-9]+$ ]] || abrt "Invalid expire time: ${EXPIRE_TIME}"
			;;
		-f|--force-expire)
			FORCE_EXPIRE=yes
			;;
		-a|--app-name|--app-name=*)
			[[ "$1" = --app-name=* ]] && APP_NAME="${1#*=}" || { shift; APP_NAME="$1"; }
			export APP_NAME
			;;
		-i|--icon|--icon=*)
			[[ "$1" = --icon=* ]] && ICON="${1#*=}" || { shift; ICON="$1"; }
			;;
		-c|--category|--category=*)
			[[ "$1" = --category=* ]] && category="${1#*=}" || { shift; category="$1"; }
			process_category "$category"
			;;
		-h|--hint|--hint=*)
			[[ "$1" = --hint=* ]] && hint="${1#*=}" || { shift; hint="$1"; }
			process_hint "$hint"
			;;
		-o | --action | --action=*)
			[[ "$1" == --action=* ]] && action="${1#*=}" || { shift; action="$1"; }
			process_action "$action"
			;;
		-d | --default-action | --default-action=*)
			[[ "$1" == --default-action=* ]] && default_action="${1#*=}" || { shift; default_action="$1"; }
			process_special_action default "$default_action"
			;;
		-l | --close-action | --close-action=*)
			[[ "$1" == --close-action=* ]] && close_action="${1#*=}" || { shift; close_action="$1"; }
			process_special_action close "$close_action"
			;;
		-p|--print-id)
			PRINT_ID=yes
			;;
		-r|--replace|--replace=*)
			[[ "$1" = --replace=* ]] && REPLACE_ID="${1#*=}" || { shift; REPLACE_ID="$1"; }
			;;
		-R|--replace-file|--replace-file=*)
			[[ "$1" = --replace-file=* ]] && filename="${1#*=}" || { shift; filename="$1"; }
			[[ -s "$filename" ]] && REPLACE_ID="$(< $filename)"
			STORE_ID="$filename"
			;;
		-s|--close|--close=*)
			[[ "$1" = --close=* ]] && close_id="${1#*=}" || { shift; close_id="$1"; }
			notify_close "$close_id"
			exit $?
			;;
		--)
			positional=yes
			;;
		*)
			process_posargs "$1"
			;;
	esac
	shift
done

# urgency is always set
HINTS=("$(make_hint byte urgency "$URGENCY")" "${HINTS[@]}")

[[ "$SUMMARY_SET" = n ]] && {
	help
	exit 1
} || {
	notify
}

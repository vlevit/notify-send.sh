#!/usr/bin/env bash

SELF=${0##*/}
TMP=${XDG_RUNTIME_DIR:-/tmp}
${DEBUG_NOTIFY_SEND:=false} && {
	exec 2>"${TMP}/.${SELF}.${$}.e"
	set -x
	trap "set >&2" 0
}

SEND_SH=${0%/*}/notify-send.sh
GDBUS_PIDF=${TMP}/${APP_NAME:=${SELF}}.${$}.p
GDBUS_ARGS=(gdbus monitor --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications)

abrt () { echo "${0}: ${@}" >&2 ; exit 1 ; }

# consume the command line
typeset -i ID="${1}"
((${ID}>0)) || abrt "no notification id passed: $@"
shift

a=("$@")
[[ "$a" ]] || abrt "no action commands passed: $@"


rm -f "$GDBUS_PIDF"
umask 077
touch "$GDBUS_PIDF"

trap "cleanup" 0
cleanup () {
	kill $(<"$GDBUS_PIDF")
	rm -f "$GDBUS_PIDF"
}

# execute an invoked command
doit () {
	invoked_action_id="$1"
	local action="" cmd=""
	for index in "${!a[@]}"; do
		[[ $((index % 2)) == 0 ]] && {
			action="${a[$index]}"
		} || {
			cmd="${a[$index]}"
			[[ "$action" == "$invoked_action_id" ]] && {
				bash -c "${cmd}" &
			}
		}
	done
}

# start the monitor
( "${GDBUS_ARGS[@]}" & echo $! >&3 ) 3>"$GDBUS_PIDF" | while read -r line ;do
	typeset -i i="$(sed '/^\/org\/freedesktop\/Notifications: org.freedesktop.Notifications.NotificationClosed (uint32 \([0-9]\+\), uint32 [0-9]\+)$/!d;s//\1/' <<< "$line")"
	((${i}>0)) && {
		((${i}==${ID})) && {
			doit close
			break
		}
	} || {
		s="$(sed '/\/org\/freedesktop\/Notifications: org.freedesktop.Notifications.ActionInvoked (uint32 \([0-9]\+\), '\''\(.*\)'\'')$/!d;s//\1:\2/' <<< "$line")"
		IFS=: read i k <<< "${s}"
			((${i}==${ID})) && {
				doit "${k}"
				break
			}
	}
done

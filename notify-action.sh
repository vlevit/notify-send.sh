#!/usr/bin/env bash

SELF=${0##*/}
TMP=${XDG_RUNTIME_DIR:-/tmp}
${DEBUG_NOTIFY_SEND:=false} && {
	exec 2>"${TMP}/.${SELF}.${$}.e"
	set -x
	trap "set >&2" 0
}

GDBUS_MONITOR_PID=/tmp/notify-action-dbus-monitor.$$.pid
GDBUS_MONITOR=(gdbus monitor --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications)

abrt () { echo "${0}: ${@}" >&2 ; exit 1 ; }

NOTIFICATION_ID="$1"
[[ "$NOTIFICATION_ID" ]] || abrt "no notification id passed: $@"
shift

ACTION_COMMANDS=("$@")
[[ "$ACTION_COMMANDS" ]] || abrt "no action commands passed: $@"

cleanup() {
	rm -f "$GDBUS_MONITOR_PID"
}

create_pid_file(){
	rm -f "$GDBUS_MONITOR_PID"
	umask 077
	touch "$GDBUS_MONITOR_PID"
}

invoke_action() {
	invoked_action_id="$1"
	local action="" cmd=""
	for index in "${!ACTION_COMMANDS[@]}"; do
		[[ $((index % 2)) == 0 ]] && {
			action="${ACTION_COMMANDS[$index]}"
		} || {
			cmd="${ACTION_COMMANDS[$index]}"
			[[ "$action" == "$invoked_action_id" ]] && {
				bash -c "${cmd}" &
			}
		}
	done
}

monitor() {
	create_pid_file
	( "${GDBUS_MONITOR[@]}" & echo $! >&3 ) 3>"$GDBUS_MONITOR_PID" | while read -r line
	do
		local closed_notification_id="$(sed '/^\/org\/freedesktop\/Notifications: org.freedesktop.Notifications.NotificationClosed (uint32 \([0-9]\+\), uint32 [0-9]\+)$/!d;s//\1/' <<< "$line")"
		[[ -n "$closed_notification_id" ]] && {
			[[ "$closed_notification_id" == "$NOTIFICATION_ID" ]] && {
				invoke_action close
				break
			}
		} || {
			local action_invoked="$(sed '/\/org\/freedesktop\/Notifications: org.freedesktop.Notifications.ActionInvoked (uint32 \([0-9]\+\), '\''\(.*\)'\'')$/!d;s//\1:\2/' <<< "$line")"
			IFS=: read invoked_id action_id <<< "$action_invoked"
				[[ "$invoked_id" == "$NOTIFICATION_ID" ]] && {
					invoke_action "$action_id"
					break
				}
		}
	done
	kill $(<"$GDBUS_MONITOR_PID")
	cleanup
}

monitor

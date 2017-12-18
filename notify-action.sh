#!/usr/bin/env bash

NOTIFY_ARGS=(--session "path=/org/freedesktop/Notifications,member=ActionInvoked")

# set -x

dbus-monitor "${NOTIFY_ARGS[@]}" |
while read -r line
do 
  IS_NOTIFY_SEND=`echo "$line" | grep "notify-send: "`
  if [[ -n $IS_NOTIFY_SEND ]]; then
    COMMAND=`echo "$line" | sed -e 's/string "notify-send: \(.*\)"$/\1/'`
    bash -c "$COMMAND"
  fi
done

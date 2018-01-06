#!/usr/bin/env bash

NOTIFY_ARGS=(--session "path=/org/freedesktop/Notifications,member=ActionInvoked")

dbus-monitor "${NOTIFY_ARGS[@]}" |
while read -r line
do 
  IS_NOTIFY_SEND=`echo "$line" | grep "notify-send.sh: "`
  if [[ -n $IS_NOTIFY_SEND ]]; then
    COMMAND=`echo "$line" | sed -e 's/string "notify-send.sh: \(.*\)"$/\1/'`
    bash -c "$COMMAND"
  fi
done

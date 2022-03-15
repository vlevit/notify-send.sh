#!/usr/bin/env bash

# notify-send.sh - drop-in replacement for notify-send with more features
# Copyright (C) 2015-2021 notify-send.sh authors (see AUTHORS file)

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

VERSION=1.2
NOTIFY_ARGS=(--session
             --dest org.freedesktop.Notifications
             --object-path /org/freedesktop/Notifications)
EXPIRE_TIME=-1
APP_NAME="${0##*/}"
REPLACE_ID=0
URGENCY=1
HINTS=()
SUMMARY_SET=n

help() {
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

convert_type() {
    case "$1" in
        int) echo int32 ;;
        double|string|byte) echo "$1" ;;
        *) echo error; return 1 ;;
    esac
}

make_action_key() {
    echo "$(tr -dc _A-Z-a-z-0-9 <<< \"$1\")${RANDOM}"
}

make_action() {
    local action_key="$1"
    printf -v text "%q" "$2"
    echo "\"$action_key\", \"$text\""
}

make_hint() {
    type=$(convert_type "$1")
    [ $? -ne 0 ] && return 1
    name="$2"
    [ "$type" = string ] && command="\"$3\"" || command="$3"
    echo "\"$name\": <$type $command>"
}

concat_actions() {
    local result="$1"
    shift
    for s in "$@"; do
        result="$result, $s"
    done
    echo "[$result]"
}

concat_hints() {
    local result="$1"
    shift
    for s in "$@"; do
        result="$result, $s"
    done
    echo "{$result}"
}

parse_notification_id(){
    sed 's/(uint32 \([0-9]\+\),)/\1/g'
}

notify() {
    local actions="$(concat_actions "${ACTIONS[@]}")"
    local hints="$(concat_hints "${HINTS[@]}")"

    NOTIFICATION_ID=$(gdbus call "${NOTIFY_ARGS[@]}"  \
                            --method org.freedesktop.Notifications.Notify \
                            -- \
                            "$APP_NAME" "$REPLACE_ID" "$ICON" "$SUMMARY" "$BODY" \
                            "${actions}" "${hints}" "int32 $EXPIRE_TIME" \
                          | parse_notification_id)

    if [ -n "$STORE_ID" ] ; then
        echo "$NOTIFICATION_ID" > "$STORE_ID"
    fi
    if [ -n "$PRINT_ID" ] ; then
        echo "$NOTIFICATION_ID"
    fi

    if [ -n "$FORCE_EXPIRE" ] ; then
        SLEEP_TIME="$( LC_NUMERIC=C printf %f "${EXPIRE_TIME}e-3" )"
        ( sleep "$SLEEP_TIME" ; notify_close "$NOTIFICATION_ID" ) &
    fi

    maybe_run_action_handler
}

notify_close () {
    gdbus call "${NOTIFY_ARGS[@]}"  --method org.freedesktop.Notifications.CloseNotification "$1" >/dev/null
}

process_urgency() {
    case "$1" in
        low) URGENCY=0 ;;
        normal) URGENCY=1 ;;
        critical) URGENCY=2 ;;
        *) echo "Unknown urgency $URGENCY specified. Known urgency levels: low, normal, critical."
           exit 1
           ;;
    esac
}

process_category() {
    IFS=, read -a categories <<< "$1"
    for category in "${categories[@]}"; do
        hint="$(make_hint string category "$category")"
        HINTS=("${HINTS[@]}" "$hint")
    done
}

process_hint() {
    IFS=: read type name command <<< "$1"
    if [ -z "$name" ] || [ -z "$command" ] ; then
        echo "Invalid hint syntax specified. Use TYPE:NAME:VALUE."
        exit 1
    fi
    hint="$(make_hint "$type" "$name" "$command")"
    if [ $? -ne 0 ] ; then
        echo "Invalid hint type \"$type\". Valid types are int, double, string and byte."
        exit 1
    fi
    HINTS=("${HINTS[@]}" "$hint")
}

maybe_run_action_handler() {
    if [ -n "$NOTIFICATION_ID" ] && [ -n "$ACTION_COMMANDS" ]; then
        local notify_action="$(dirname ${BASH_SOURCE[0]})/notify-action.sh"
        if [ -x "$notify_action" ] ; then
            "$notify_action" "$NOTIFICATION_ID" "${ACTION_COMMANDS[@]}" &
            exit 0
        else
            echo "executable file not found: $notify_action"
            exit 1
        fi
    fi
}

process_action() {
    IFS=: read name command <<<"$1"
    if [ -z "$name" ] || [ -z "$command" ]; then
        echo "Invalid action syntax specified. Use NAME:COMMAND."
        exit 1
    fi

    local action_key="$(make_action_key "$name")"
    ACTION_COMMANDS=("${ACTION_COMMANDS[@]}" "$action_key" "$command")

    local action="$(make_action "$action_key" "$name")"
    ACTIONS=("${ACTIONS[@]}" "$action")
}

process_special_action() {
    action_key="$1"
    command="$2"

    if [ -z "$action_key" ] || [ -z "$command" ]; then
        echo "Command must not be empty"
        exit 1
    fi

    ACTION_COMMANDS=("${ACTION_COMMANDS[@]}" "$action_key" "$command")

    if [ "$action_key" != close ]; then
        local action="$(make_action "$action_key" "$name")"
        ACTIONS=("${ACTIONS[@]}" "$action")
    fi
}

process_posargs() {
    case "$1" in
        -*) if [ "$positional" != yes ] ; then
                echo "Unknown option $1"
                exit 1
            fi ;;
    esac

    if [ "$SUMMARY_SET" = n ]; then
        SUMMARY="$1"
        SUMMARY_SET=y
    else
        BODY="$1"
    fi
}

while [ $# -gt 0 ] ; do
    case "$1" in
        -\?|--help)
            help
            exit 0
            ;;

        -v|--version)
            echo "${0##*/} $VERSION"
            exit 0
            ;;

        -u|--urgency)
            shift
            process_urgency "$1"
            ;;
        --urgency=*)
            process_urgency "${1#*=}"
            ;;

        -t|--expire-time|--expire-time=*)
            case "$1" in
                --expire-time=*) EXPIRE_TIME="${1#*=}" ;;
                *) shift; EXPIRE_TIME="$1" ;;
            esac
            # check if it is a numeric value
            case "${EXPIRE_TIME#-}" in
                *[![:digit:]]*|"")
                    echo "Invalid expire time: ${EXPIRE_TIME}"
                    exit 1
                    ;;
            esac
            ;;

        -f|--force-expire)
            FORCE_EXPIRE=yes
            ;;

        -a|--app-name)
            shift
            APP_NAME="$1"
            ;;
        --app-name=*)
            APP_NAME="${1#*=}"
            ;;

        -i|--icon)
            shift
            ICON="$1"
            ;;
        --icon=*)
            ICON="${1#*=}"
            ;;

        -c|--category)
            shift
            process_category "$1"
            ;;
        --category=*)
            process_category "${1#*=}"
            ;;

        -h|--hint)
            shift
            process_hint "$1"
            ;;
        --hint=*)
            process_hint "${1#*=}"
            ;;

        -o|--action)
            shift
            process_action "$1"
            ;;
        --action=*)
            process_action "${1#*=}"
            ;;

        -d|--default-action)
            shift
            process_special_action default "$1"
            ;;
        --default-action=*)
            process_special_action default "${1#*=}"
            ;;

        -l|--close-action)
            shift
            process_special_action close "$1"
            ;;
        --close-action=*)
            process_special_action close "${1#*=}"
            ;;

        -p|--print-id)
            PRINT_ID=yes
            ;;

        -r|--replace)
            shift
            REPLACE_ID="$1"
            ;;
        --replace=*)
            REPLACE_ID="${1#*=}"
            ;;

        -R|--replace-file|--replace-file=*)
            case "$1" in
                --replace-file=*) filename="${1#*=}" ;;
                *) shift; filename="$1" ;;
            esac
            if [ -s "$filename" ]; then
                REPLACE_ID="$(< "$filename")"
            fi
            STORE_ID="$filename"
            ;;

        -s|--close|--close=*)
            case "$1" in
                --close=*) close_id="${1#*=}" ;;
                *) shift; close_id="$1" ;;
            esac
            # always check that --close provides a numeric value
            case "${close_id#*-}" in
                *[![:digit:]]*|"")
                  echo "Invalid close id: '$close_id'"
                  exit 1
                  ;;
            esac
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

# always force --replace and --replace-file to provide a numeric value; 0 means no id provided
case "$REPLACE_ID" in
    # empty or something in [[:digit:]]
    ""|*[![:digit:]]*) REPLACE_ID=0 ;;
esac

# urgency is always set
HINTS=("$(make_hint byte urgency "$URGENCY")" "${HINTS[@]}")

if [ "$SUMMARY_SET" = n ] ; then
    help
    exit 1
else
    notify
fi

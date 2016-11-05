#!/usr/bin/env bash

# notify-send.sh - drop-in replacement for notify-send with more features
# Copyright (C) 2015 Vyacheslav Levit <dev@vlevit.org>

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

VERSION=0.1
NOTIFY_ARGS=(--session
             --dest org.freedesktop.Notifications
             --object-path /org/freedesktop/Notifications)
EXPIRE_TIME=-1
APP_NAME="${0##*/}"
REPLACE_ID=0
URGENCY=1
HINTS=()

help() {
    cat <<EOF
Usage:
  notify-send.sh [OPTION...] <SUMMARY> [BODY] - create a notification

Help Options:
  -?|--help                         Show help options

Application Options:
  -u, --urgency=LEVEL               Specifies the urgency level (low, normal, critical).
  -t, --expire-time=TIME            Specifies the timeout in milliseconds at which to expire the notification.
  -a, --app-name=APP_NAME           Specifies the app name for the icon
  -i, --icon=ICON[,ICON...]         Specifies an icon filename or stock icon to display.
  -c, --category=TYPE[,TYPE...]     Specifies the notification category.
  -h, --hint=TYPE:NAME:VALUE        Specifies basic extra data to pass. Valid types are int, double, string and byte.
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

make_hint() {
    type=$(convert_type "$1")
    [[ ! $? = 0 ]] && return 1
    name="$2"
    [[ "$type" = string ]] && value="\"$3\"" || value="$3"
    echo "\"$name\": <$type $value>"
}

concat_hints() {
    local result="$1"
    shift
    for s in "$@"; do
        result="$result, $s"
    done
    echo "{$result}"
}

handle_output() {
    if [[ -n "$STORE_ID" ]] ; then
        sed 's/(uint32 \([0-9]\+\),)/\1/g' > $STORE_ID
    elif [[ -z "$PRINT_ID" ]] ; then
        cat > /dev/null
    else
        sed 's/(uint32 \([0-9]\+\),)/\1/g'
    fi
}

notify () {
    gdbus call "${NOTIFY_ARGS[@]}"  --method org.freedesktop.Notifications.Notify \
          "$APP_NAME" "$REPLACE_ID" "$ICON" "$SUMMARY" "$BODY" \
          [] "$(concat_hints "${HINTS[@]}")" "int32 $EXPIRE_TIME" | handle_output
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
    IFS=: read type name value <<< "$1"
    if [[ -z "$name" ]] || [[ -z "$value" ]] ; then
        echo "Invalid hint syntax specified. Use TYPE:NAME:VALUE."
        exit 1
    fi
    hint="$(make_hint "$type" "$name" "$value")"
    if [[ ! $? = 0 ]] ; then
        echo "Invalid hint type \"$type\". Valid types are int, double, string and byte."
        exit 1
    fi
    HINTS=("${HINTS[@]}" "$hint")
}

process_posargs() {
    if [[ "$1" = -* ]] && ! [[ "$positional" = yes ]] ; then
        echo "Unknown option $1"
        exit 1
    else
        [[ -z "$SUMMARY" ]] && SUMMARY="$1" || BODY="$1"
    fi
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
            ;;
        -a|--app-name|--app-name=*)
            [[ "$1" = --app-name=* ]] && APP_NAME="${1#*=}" || { shift; APP_NAME="$1"; }
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
        -p|--print-id)
            PRINT_ID=yes
            ;;
        -r|--replace|--replace=*)
            [[ "$1" = --replace=* ]] && REPLACE_ID="${1#*=}" || { shift; REPLACE_ID="$1"; }
            ;;
        -R|--replace-file|--replace-file=*)
            [[ "$1" = --replace-file=* ]] && filename="${1#*=}" || { shift; filename="$1"; }
            if [[ -s "$filename" ]]; then
                REPLACE_ID="$(< $filename)"
            fi
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

if [[ -z "$SUMMARY" ]] ; then
    help
    exit 1
else
    notify
fi

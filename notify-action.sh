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
GDBUS_ARGS=(monitor --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications)

abrt () { echo "${SELF}: ${@}" >&2 ; exit 1 ; }

# consume the command line
typeset -i ID="${1}" ;shift
((${ID}>0)) || abrt "no notification id"
declare -A a ;while ((${#})) ;do a[${1}]=${2} ;shift 2 ;done
((${#a[@]})) || abrt "no actions"

[[ "${DISPLAY}" ]] || abrt "no DISPLAY"
typeset -i i=0 p=0
set +H
shopt -s extglob

# kill obsolete monitors (now)
echo -n "${DISPLAY} ${ID} " > "${GDBUS_PIDF}"
for f in ${TMP}/${APP_NAME}.+([0-9]).p ;do
	[[ -s ${f} ]] || continue
	[[ ${f} -ot ${GDBUS_PIDF} ]] || continue
	read d i p x < ${f}
	[[ "${d}" == "${DISPLAY}" ]] || continue
	((${i}==${ID})) || continue
	((${p}>1)) || continue
	rm -f "${f}"
	kill ${p}
done

# kill current monitor (on exit)
trap "conclude" 0
conclude () {
	${DEBUG_NOTIFY_SEND} && set >&2
	[[ -s ${GDBUS_PIDF} ]] || exit 0
	read d i p x < "${GDBUS_PIDF}"
	rm -f "${GDBUS_PIDF}"
	((${p}>1)) || exit
	kill ${p}
}

# execute an invoked command
doit () {
	setsid -f ${a[${1}]} >&- 2>&- <&- &
	${EXPLICIT_CLOSE:-false} && "${SEND_SH}" -s ${ID}
}

# start the monitor
{
	gdbus ${GDBUS_ARGS[@]} & echo ${!} >> "${GDBUS_PIDF}"
} |while IFS=" :.(),'" read x x x x e x i x k x ;do
	((${i}==${ID})) || continue
	case "${e}" in
		"NotificationClosed") doit "close" ;;
		"ActionInvoked") doit "${k}" ;;
	esac
	break
done

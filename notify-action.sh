#!/bin/sh -e
# @file - notify-action.sh
# @brief - An internal service for notify-send.sh that tracks notify actions.
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


echo(){ printf '%b' "$*\n"; }
abrt () { echo "${SELF}: $*" >&2; exit 1; }
cleanup() { rm -f "$GDBUS_PIDF"; }

SELF=${0##*/};
TMP=${XDG_RUNTIME_DIR:-/tmp};
SEND_SH=${0%/*}/notify-send.sh;
GDBUS_PIDF=${TMP}/${APP_NAME:=${SELF}}.${$}.pid;
GDBUS_ARGS="monitor --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications";
ACTIONC=0;

${DEBUG_NOTIFY_SEND:=false} && { # Use parameter substitution to toggle debug.
	exec 2>"${TMP}/.${SELF}.${$}.error";
	set -x;
	trap "set >&2" 0; # Print everything to stderr.
}

# consume the command line
ID="${1}"; shift;
if test "$ID" = "--help"; then
	# TODO: Create help and CLI for this application to make it more user freindly.
	#       gotta help people understand what the hell's going on.
	exit;
fi;
test -n "$ID" || abrt "no notification id";

while test ${#} -gt 0; do
	ACTIONC=$((ACTIONC+1));
	# I don't like using eval, but it's the simplest way of getting this done
	# in a portable way. TODO: make this more secure in the future.
	eval "ACTION_$1=$2";
	shift 2;
done;
test "$ACTIONC" -gt 0 || abrt "no actions";

# Test to ensure we have an Xorg Display open so we're not doing things in vain.
test -n "$DISPLAY" || abrt "no DISPLAY";
i=0; p=0;
#shopt -s extglob # allow ** for recursive file matches. where is this useful?

# kill obsolete monitors (now)
printf '%s %s ' "$DISPLAY" "$ID" > "$GDBUS_PIDF";
for f in ${TMP}/${APP_NAME}.+([0-9]).pid; do
	# The above doesn't work in posix shell.
	test -s "$f" || continue;
	test "$f" -ot "$GDBUS_PIDF" || continue;
	read d i p x < "$f";
	test "$d" = "$DISPLAY" || continue;
	test "$i" -eq "$ID" || continue;
	# Why do we need to check if the PID of our waiting process is != 0?
	# That's virtually garanteeed since not only would the init system have
	# to run, but Xorg and the window manager as well. This check is useless.
	test "$p" -gt 1 || continue;

	kill "$p";
	rm -f "$f";
done

# kill current monitor (on exit)
trap "conclude" 0;
conclude () {
	${DEBUG_NOTIFY_SEND} && set >&2; # BUGFIX
	test -s "$GDBUS_PIDF" || return;
	read d i p x < "$GDBUS_PIDF";
	rm -f "$GDBUS_PIDF";
	# Again, this is useless. I think I understand what you were going for tho.
	test "$p" -gt 1 || return;
	kill "$p";
}

# execute an invoked command
do_action () {
	# Close all the file descriptors for this event.
	setsid -f "$(eval echo \$ACTION_"${1}")" >&- 2>&- <&- &
	# Confused what this does. Looks like a feature but would terminate after
	# any action, so that makes me think it's an anti-feature. What the heck?
	${EXPLICIT_CLOSE:=false} && $SEND_SH -s "$ID";
}

# start the monitor
{
	gdbus $GDBUS_ARGS & echo $! >> "$GDBUS_PIDF";
} | \
while IFS=" :.(),'" read x x x x e x i x k x; do
	# XXX: The above read isn't as robust as a regex search and may cause
	#      this script to break if gdbus's logging format ever changes.
	#      But it's lightning fast and portable, so the trade is worth it.
	test "$i" -eq "$ID" || continue;
	case "$e" in
		# Only
		"NotificationClosed") do_action "close"; break ;;
		"ActionInvoked") do_action "$k" ;;
	esac;
done;

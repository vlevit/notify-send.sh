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

################################################################################
## Globals (Comprehensive)

# Symlink script resolution via coreutils
SELF="/"$(readlink -n -f $0); x=${SELF%/*}; x=${x#/}; x=${x:-.};
PROCDIR=$(cd "$x"; pwd); # Process direcotry.
TMP=${XDG_RUNTIME_DIR:-/tmp}; # XDG standard runtime directory.
GDBUS_PIDF=$TMP/${APP_NAME:=${SELF##*/}}.$$.dat;
SEND_SH=$PROCDIR/notify-send.sh;
ACTIONC=0;
#CONCLUDED=; Used to bugfix the exit handler.
#ID=; # Current shell's target ID.
#DISPLAY=; # Xorg display to use.
#ACTION_(*); # Actions the shell commit on the $1 regex matching gdbus event.
#x=; # General use temporary variable.
#p=; # PID extracted from external files.
#i=; # ID extracted from external files.
#d=; # DISPLAY extracted from external files.

################################################################################
## Functions

echo(){ printf '%b' "$*\n"; }
abrt () { echo "$SELF: $*" >&2; exit 1; }

do_action () {
	local ACTION; ACTION="$(eval echo \$ACTION_"${1}")";
	if test -n "$ACTION"; then
		# Close all the file descriptors for this event.
		setsid -f "$ACTION" >&- 2>&- <&- &
		# Confused what this does. Looks like a feature but would terminate after
		# any action, so that makes me think it's an anti-feature. What the heck?
		${EXPLICIT_CLOSE:=false} && $SEND_SH -s "$ID";
	fi;
}

conclude () {
	# Bugfix: twice recurring handler
	if ${CONCLUDED:=false}; then return; fi; CONCLUDED=true;

	# Only handle the datafile when it exists.
	test -s "$GDBUS_PIDF" || return;
	read d i p x < "$GDBUS_PIDF";

	# Only need to kill `gdbus` if it still exists. Because this process is
	# shutting down the shell parent. If we don't do this, `gdbus` will be
	# left alive dangling on an empty FD.
	test -z "$p" || kill "$p";

	# Always attempt to clean up the PID file.
	rm -vf "$GDBUS_PIDF";
}

################################################################################
## Main Script

# Use parameter substitution to toggle debug.
${DEBUG_NOTIFY_SEND:=false} && {
	exec 2>"$TMP/$APP_NAME.$$.log";
	set -x;
	trap "set >&2" EXIT HUP INT QUIT ABRT KILL TERM; # Print everything to stderr.
}

if test "$1" = "--help" -o "$1" = "-h"; then
	# TODO: Create help and CLI for this application to make it more user freindly.
	#       gotta help people understand what the hell's going on.
	echo 'Usage: notify-action.sh ID ACTION_KEY VALUE [[ACTION_KEY] [VALUE]]...';
	echo 'Description:';
	echo "\tA suplemental utility for notify-send.sh that handles action events.";
	echo;
	echo 'Help Options:';
	echo '\t-h|--help           Show help options';
	echo;
	echo 'Positional Arguments:';
	echo '\tID          - The event ID to handle.';
	echo '\tACTION_KEY  - The name of the event to handle.';
	echo '\tVALUE       - The action to be taken when the event fires.';
	exit;
fi;

# consume the command line
test -n "${ID:=$1}" || abrt "No notification id provided."; shift;
case "$ID" in
	''|*[!0-9]*) abrt "ID must be integer type.";;
esac;

while test ${#} -gt 0; do
	ACTIONC=$((ACTIONC+1));
	# I don't like using eval, but it's the simplest way of getting this done
	# in a portable way. TODO: make this more secure in the future.
	for x in $1; do true; done;
	eval "ACTION_$x=\"$2\"";

	# Throw error when key is supplied without action value.
	test -n "$2" || abrt "Action #$ACTIONC supplied key without value.";

	shift 2;
done;
test "$ACTIONC" -gt 0 || abrt "No action provided.";

# Test to ensure we have an Xorg Display open so we're not doing things in vain.
test -n "$DISPLAY" || abrt "DISPLAY is unset; No Xorg available.";

# kill obsolete monitors (now)
printf '%s %s ' "$DISPLAY" "$ID" > "$GDBUS_PIDF";
for f in ${TMP}/${APP_NAME}.*.dat; do
	# Since our PID file suffix is unique, we can guarantee the above will work
	# for all existing PID files.
	test -s "$f" || continue;
	test "$f" -ot "$GDBUS_PIDF" || continue;
	read d i p x < "$f";

	# Ensure target processes have the same display.
	test "$d" = "$DISPLAY" || continue;
	# Ensure target processes have the same notification ID.
	test "$i" -eq "$ID" || continue;

	# Fetch group PID from filename.
	p=${f%.dat}; p=${p##*.};

	# Kill by group ID. More robust than depending on gdbus invocation & PID.
	kill -- "-$p";
	rm -f "$f";
done;

# kill current monitor (on exit and other processable signals)
trap "conclude" EXIT HUP INT QUIT ABRT TERM;

# start the monitor
{
	gdbus monitor --session \
		--dest org.freedesktop.Notifications \
		--object-path /org/freedesktop/Notifications &

	echo "$!" >> $GDBUS_PIDF;
} | \
while IFS=" :.(),'" read x x x x e x i x k x; do
	# XXX: The above read isn't as robust as a regex search and may cause
	#      this script to break if gdbus's logging format ever changes.
	#      But it's lightning fast and portable, so the trade is worth it.

	# The first two lines always contain garbage data, so supress the illegal
	# number warnings from test by blocking stderr.
	test "$i" -eq "$ID" 2>/dev/null || continue;
	case "$e" in
		# Only
		"NotificationClosed") do_action "close"; break ;;
		"ActionInvoked") do_action "$k" ;;
	esac;
done;

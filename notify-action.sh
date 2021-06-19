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
## Globals (Comprehensive - common.setup)

# Symlink script resolution via coreutils (exists on 95+% of linux systems.)
SELF=$(readlink -n -f "$0");
PROCDIR="$(dirname "$SELF")"; # Process direcotry.
APPNAME="$(basename "$SELF")";
TMP=${XDG_RUNTIME_DIR:-/tmp}; # XDG standard runtime directory.
GDBUS_PIDF=$TMP/${APP_NAME:=${SELF##*/}}.$$.dat;
LOGFILE=${LOGFILE:=$TMP/notify-action.$$.log};
ACTIONED="false";
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
## Imports

. $PROCDIR/common.functions.sh; # Import shared code.
. $PROCDIR/common.setup.sh; # Ensures we have debug and logfile stuff together.

################################################################################
## Functions

do_action () {
	eval "ACTION=\"\$ACTION_$1\"";
	if test -n "$ACTION"; then
		# Call setsid to execute the action in a new session.
		setsid $SHELL -c "$($ACTION)" &;
		ACTIONED="true";
	fi;
}

conclude () {
	# Bugfix: twice recurring handler
	if ${CONCLUDED:=false}; then return; fi; CONCLUDED="true";

	# Only handle the datafile when it exists.
	test -s "$GDBUS_PIDF" || return;
	read d i p x < "$GDBUS_PIDF";

	# Only need to kill `gdbus` if it still exists. Because this process is
	# shutting down the shell parent. If we don't do this, `gdbus` will be
	# left alive dangling on an empty FD.
	test -z "$p" || kill "$p";

	# Always attempt to clean up the PID file.
	rm -vf "$GDBUS_PIDF";

	# Only cleanup pipes if we haven't launched an action or we're debugging
	! $ACTIONED || ! $DEBUG  || cleanup_pipes;
}

################################################################################
## Main Script

# NOTE: Extra setup of STDIO done in common.lib.sh

if test "$1" = "--help" -o "$1" = "-h"; then
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
test "$(typeof "$ID")" = "uint" || abrt "ID must be unsigned integer type.";

while test ${#} -gt 0; do
	if test "$(typeof -g "$1")" -lt 4; then
		 abrt "action key must not contain special characters.";
	fi;

	eval "ACTION_$1=\"$(sanitize_quote_escapes "$2")\"";

	# Throw error when key is supplied without action value.
	test -n "$2" || abrt "Action #$ACTIONC supplied key without value.";

	shift 2;

	ACTIONC=$((ACTIONC+1));
done;
test "$ACTIONC" -gt 0 || abrt "No action provided.";

# Test to ensure we have an Xorg Display open so we're not doing things in vain.
test -n "$DISPLAY" || abrt "DISPLAY is unset; No Xorg available.";

# kill obsolete monitors (now)
printf '%s %s ' "$DISPLAY" "$ID" > "$GDBUS_PIDF";
for f in ${TMP}/${APPNAME}.*.dat; do
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

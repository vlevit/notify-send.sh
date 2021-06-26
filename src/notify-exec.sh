#!/bin/sh
# @file - notify-exec.sh
# @brief - An internal service for notify-send.sh that encapsulates the
#          action taken by a notification and provides user alerts for
#          command failure and other statuses.
###############################################################################
# Copyright (C) 2015-2021 notify-send.sh authors (see AUTHORS file)
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

# Symlink script resolution via coreutils (exists on 95+% of linux systems.)
SELF=$(readlink -n -f "$0");
PROCDIR="$(dirname "$SELF")";
APPNAME="$(basename "$SELF")";
TMP="${XDG_RUNTIME_DIR:-/tmp}";
LOGFILE=${LOGFILE:=$TMP/notify-exec.$$.log};
RESULT_OUTPUT=; RESULT_STATUS=;
NOTIFY_CMD_FAILURE=${NOTIFY_CMD_FAILURE:=true};
NOTIFY_CMD_SUCCESS=${NOTIFY_CMD_FAILURE:=false};
SUCCESS_MSG=${SUCCESS_MSG:=};
NOTIFIED="false";

################################################################################
## Imports

. $PROCDIR/notify-common.d/setup.sh; # Ensures we have debug and logfile stuff together.

################################################################################
## Functions

################################################################################
## Main Script

while test "$#" -gt 0; do
	case "$1" in
		-h|--help)
			echo 'Usage: notify-exec.sh COMMAND';
			echo;
			echo 'Description:';
			echo "\tA supplemental utility for notify-send.sh that protects actions.";
			echo "\tThis script throws an error notification if it's action fails.";
			echo;
			echo 'Help Options:';
			echo '\t-h, --help           Show help options';
			echo;
			echo 'Application Options:';
			echo "\t-q, --quietly-fail             When an action fails, don't display the error notification.";
			echo '\t    --alert-success=MSG        After successfully executing an action, displays a notification with the body MSG.';
			echo;
			echo 'Positional Arguments:';
			echo '\tCOMMAND          - The command to execute.';
			echo;
			exit;
		;;
		-q|--quietly-fail) NOTIFY_CMD_FAILURE="false";;
		--alert-success|--alert-success=*)
			if starts_with "$1" '--alert-success'; then s="${1#*=}"; else shift; s="$1"; fi;
			NOTIFY_CMD_SUCCESS="true";
			SUCCESS_MSG="$s";
		;;
		*) break 2;;
	esac;
	shift;
done;

notify_error() {
	/bin/sh "$PROCDIR/notify-send.sh" -q -t 1 -u critical \
		"Action Failed: $1" \
		"<b>Action:</b> <u><i>$CMD_INPUT</i></u>\n<a href=\"file://$LOGFILE.action\">See the full log in \`$LOGPATH.action\`</a>\n<b>Raw Output:</b> <i>$CMD_OUTPUT</i>";
	NOTIFIED="true";
}

notify_success() {
	/bin/sh "$PROCDIR/notify-send.sh" -q -t 1 -u low "Success!" "$SUCCESS_MSG";
	NOTIFIED="true";
}

CMD_INPUT="$*";
CMD_STATUS="0";
# the || prevents -e from killing us on failure and fills our status variable.
CMD_OUTPUT="$($SHELL -c "$*")" ||
CMD_STATUS="$?";

# Print full log to file.
printf '%s' "$CMD_OUTPUT" > "$LOGFILE.action";
# Two heads truncate the log into a reasonable size for a notification body.
CMD_OUTPUT="$(printf '%s' "$CMD_OUTPUT" | head -4 | head 512)";


if $NOTIFY_CMD_SUCCESS && test "$CMD_STATUS" -eq 0; then
	rm -f "$LOGFILE.action";
	notify_success;
elif $NOTIFY_CMD_FAILURE; then
	case "$CMD_STATUS" in
		1)        notify_error "Script failed to complete";;
		2)        notify_error "Misuse of shell built-in";;
		126)      notify_error "Could not execute";;
		127)      notify_error "Command not found";;
		128)      notify_error "Invalid argument to \"exit\"";;
		# TODO: https://www.man7.org/linux/man-pages/man7/signal.7.html
		#     Only supporting Arm and x86 for now since other architechtures
		#     haven't hit the consumer market, and coding that now would be a
		#     huge pain. The signals below may need broken out in the future!
		129)      notify_error "Hangup detected";;
		130)      notify_error "Process interrupted from keyboard";;
		131)      notify_error "Process quit from keyboard";;
		132)      notify_error "Illegal instruction";;
		133)      notify_error "Trace or breakpoint trap";;
		134)      notify_error "Abort signal dispatched";;
		135)      notify_error "Bus error or bad memory access";;
		136)      notify_error "Floating-point exception";;
		137)      notify_error "Kill signal recieved";;
		138)      notify_error "Exited due to user reserved signal";;
		139)      notify_error "Segfault / invalid memory reference";;
		140)      notify_error "Exited due to user reserved signal";;
		141)      notify_error "Broken pipe / write to pipe with no readers";;
		142)      notify_error "Timer signal dispatched";;
		143)      notify_error "Termination signal";;
		144)      notify_error "Stack fault on coprocessor";;
		145)      notify_error "Child stopped or terminated";;

		# Like hell I'm processing the rest of these. They shouldn't ever be
		# seen by most scripts, so I'm taking the side of lazyness today.
		*)        notify_error "Unknown Error";;
	esac;
fi;

if ! $NOTIFIED; then cleanup; fi;

#!/bin/sh -e
# @file - notify-exec.sh
# @brief - An internal service for notify-send.sh that encapsulates the
#          action taken by a notification and provides user alerts for
#          command failure and other statuses.
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

# Symlink script resolution via coreutils (exists on 95+% of linux systems.)
SELF=$(readlink -n -f "$0");
PROCDIR="$(dirname "$SELF")"; # Process direcotry.
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

. $PROCDIR/common.setup.sh; # Ensures we have debug and logfile stuff together.

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
	NOTIFIED="true"; /bin/sh $PROCDIR/notify-send.sh -q -t 1 -u critical "$1" "$2";
}

notify_success() {
	NOTIFIED="true"; /bin/sh $PROCDIR/notify-send.sh -q -t 1 -u low "$1" "$2";
}

CMD_INPUT="$*";
CMD_STATUS="0";
CMD_OUTPUT="$($SHELL -c "$*")" || # execution in subshell is safe enough.
CMD_STATUS="$?";

if $NOTIFY_CMD_FAILURE; then
	case "$CMD_STATUS" in
		0);;
		127) notify_error "Error: Command Not Found" \
			"<b>Raw Output:</b> <i>\`$CMD_OUTPUT\`</i>\n<b>PATH:<\b> <i>$PATH<i>";;
		*) notify_error "Error: Unknown" \
			"The action failed for an unknown reason.";;
	esac;
fi;

if $NOTIFY_CMD_SUCCESS && test "$CMD_STATUS" -eq 0; then
	notify_success "Success!" "$SUCCESS_MSG";
fi;

if ! $NOTIFIED; then cleanup; fi;

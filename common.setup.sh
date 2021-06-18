# @file - common.setup.sh
# @brief - Shared setup code for the notify-send.sh suite.
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

# NOTE: No code involved in this script should call functions outside this script.
#       This code is intended to be portable between applications, not static.

################################################################################
## Globals

LOGFILE=${LOGFILE:=$TMP/notify-send.$$.log};
TERMINAL=; # Holds the file for printing to our terminal, if we have one.
VERSION="2.0.0-rc.m3tior"; # Should be included in all scripts.

################################################################################
## Main Script

# NOTE: This should execute prior to all other code besides global variables
#       and function definitions.

for f in "/proc/$$/fd/1" "/proc/$$/fd/2"; do
	if test -e "$f"; then
		TERMINAL="$(readlink -n -f "$f")";
		break;
	fi;
done;

# This will redirect all output to our logfile,
exec 1>&2 2>"$LOGFILE";
# And this will pick up the log, redirecting it to the terminal.
test -z "$TERMINAL" -a "$TERMINAL" != "/dev/null" ||
	tail --pid="$$" -f "$LOGFILE" > "$TERMINAL" &

${DEBUG:=false} && {
	PS4="\$APPNAME PID#\$\$[\$LINENO]: ";
	set -x;
	trap "set >&2" 0;
}

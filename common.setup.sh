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

# Record previous FDs for processing later.
FD1="$(readlink -n -f /proc/$$/fd/1)";
FD2="$(readlink -n -f /proc/$$/fd/2)";

# Redirect to logfiles.
exec 1>$LOGFILE.1;
exec 2>$LOGFILE.2;

# And this will pick up the log, redirecting it to the terminal if we have one.
test -n "$FD1" -a "$FD1" != "\dev\null" || tail --pid="$$" -f $LOGFILE.1 >> "$FD1" &
test -n "$FD2" -a "$FD2" != "\dev\null" || tail --pid="$$" -f $LOGFILE.2 >> "$FD2" &


# Micro-optimization. Maybe, that's more of a parent script calling this one
# kind of deal.
# hash gdbus;

${DEBUG:=false} && {
	PS4="\$APPNAME PID#\$\$[\$LINENO]: ";
	set -x;
	trap "set >&2" 0;
}

# shellcheck shell=sh
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

# SELF=; # The path to the currently executing script.
TMP=${XDG_RUNTIME_DIR:-/tmp};

# shellcheck disable=SC2059,SC2034
VERSION="2.0.0+m3tior"; # Should be included in all scripts.

export SHELL="$SHELL";

# BUGFIX: Prevents nested shells from being unable to log.
export XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR";
export LOGFILE="${LOGFILE:=$TMP/notify-send.$$.log}";
export DEBUG="${DEBUG:=false}";

# Record initial FDs for processing later.
FD1="$(readlink -n -f /proc/$$/fd/1)";
FD2="$(readlink -n -f /proc/$$/fd/2)";

################################################################################
## Functions

cleanup(){
	if ! $DEBUG; then
		rm -f "$LOGFILE.1" "$LOGFILE.2";
	fi;
}

################################################################################
## Main Script

# NOTE: This should execute prior to all other code besides global variables
#       and function definitions.

# Redirect to logfiles.
exec 1>>"$LOGFILE.1";
exec 2>>"$LOGFILE.2";

if $DEBUG; then
	PS4="\$SELF in PID#\$\$ @\$LINENO: ";
	set -x;
	trap "set >&2;" 0;
fi;

# And this will pick up the log, redirecting it to the terminal if we have one.
if test -n "$FD1" -a "$FD1" != "/dev/null" -a "$FD1" != "$LOGFILE.1"; then
	tail --pid="$$" -f "$LOGFILE.1" >> "$FD1" & trap "kill $!;" 0;
fi;
if test -n "$FD2" -a "$FD2" != "/dev/null" -a "$FD2" != "$LOGFILE.2"; then
	tail --pid="$$" -f "$LOGFILE.2" >> "$FD2" & trap "kill $!;" 0;
fi;

# XXX: Fixes a racing condition caused by the shared logging setup.
sleep 0.01;

# Always cleanup on explitcit exit. Where we exit without the command, we're
# passing execution to the next script in the chain.
alias exit="cleanup; exit";

# Micro-optimization. Maybe, that's more of a parent script calling this one
# kind of deal.
# hash gdbus;

#!/bin/sh
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

################################################################################
## Globals (Comprehensive)

# Symlink script resolution via coreutils (exists on 95+% of linux systems.)
SELF=$(readlink -n -f "$0");
PROCDIR="$(dirname "$SELF")";
APPNAME="$(basename "$SELF")";
TMP="${XDG_RUNTIME_DIR:-/tmp}";

################################################################################
## Imports

################################################################################
## Functions

################################################################################
## Main Script

notify_send(){
	/bin/sh "$PROCDIR/../src/notify-send.sh" $*;
}

# TODO: Make test for basic notification
# TODO: Make test for notification timeout
# TODO: Make test for notification body filtering if possible
# TODO: Make test for notification buttons
# TODO: Make test for notification default action
# TODO: Make test for notification close action
# TODO: test diagnostics info.

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

mkdir -p "$PROCDIR/.bin";
PATH="$PROCDIR/.bin:$PATH";

if ! type jq 1>/dev/null; then
	# The only package that needs to be latest is shellcheck because it provides
	# protection of our sourcecode. As much as I'd like to have both sources
	# hash validated to eliminate the MiM risk vector, I can't for all systems.
	# Neither package author provides checksums.
	echo "Fetching jq...";
	curl -L --progress-bar \
		-o "$PROCDIR/.bin/jq" \
		"https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64";

	chmod +x "$PROCDIR/.bin/jq";
fi;

# Enforce using the latest shellcheck.
# Screw the current users installation if they have one, I don't want to deal
# with that balognia.
if ! test -x "$PROCDIR/.bin/shellcheck"; then
	RELEASES="$(tempfile)";
	TARGET="$(tempfile)";
	curl -s \
		-H "Accept: application/vnd.github.v3+json" \
		"https://api.github.com/repos/koalaman/shellcheck/releases" > "$RELEASES";

	l=0; # This value won't be tracked outside the loop, but that's okay.

	# I really hate how POSIX does this, the following is actually in a subshell.
	# Don't mess with it please. The first array index is assumed to be
	# the latest release.
	{ jq '.[0].assets[].name' < "$RELEASES"; } | while read asset; do
		# XXX: Piping input directly into a string search is risky, but
		#      I haven't seen any architechtures that use special characters
		#      in their identifiers, so it should be fine.
		if test "$asset" != "${asset#*linux.$(uname -m).tar.xz}"; then
			jq ".[0].assets[$l].browser_download_url" < "$RELEASES" > "$TARGET";
			break;
		fi;
		l="$((l + 1))";
	done;

	# Out of subshell, use -s to check if we've piped anything to file.
	# Alternative to variable -n method when outside a subshell.
	if test -s "$TARGET"; then
		URL="$(cat $TARGET)";
		URL="${URL#\"}"; URL="${URL%\"}";
		FILENAME="${URL##*/}";
		# -o "${XDG_RUNTIME_DIR}/$FILENAME"
		echo "Fetching shellcheck...";
		curl -L "$URL" --progress-bar --ssl | tar \
				--strip-components=1 -J \
				--get "${FILENAME%%.linux*}/shellcheck" \
				-O > "$PROCDIR/.bin/shellcheck";

		chmod +x "$PROCDIR/.bin/shellcheck";
	else
		echo "Error: shellcheck isn't available for your system." >&2; exit 1;
	fi;

	rm -f "$RELEASES" "$TARGET";
fi;

if test -n "$1"; then
	shellcheck $*;
else
	# NOTE: Excluded warnings
	#     SC1091 - External source issue. Shellcheck is failing to trace files.
	#     SC2068 - Double quote array expansions are intentionally used.
	#     SC2028 - `echo` is a function wrapping printf.
	#     SC2141 - Literal backslashes are all over the place.
	#     SC1003 - It's confused about my use of the double backslash literal.
	#     SC2064 - Assume I know what I'm doing with evaled expansions values.
	shellcheck -x \
		-e SC2068,SC1091,SC2028,SC2141,SC1003,SC2064 \
		$(find "$PROCDIR/../src" -type f -printf '%p ');
fi;

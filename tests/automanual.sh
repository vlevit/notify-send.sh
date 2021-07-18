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

MANUAL_FALLBACK='false';

# Capability Flags (these are used later with the ${var:=false} matcher)
SERVER_HAS_ACTION_ICONS="false";
SERVER_HAS_ACTIONS="false";
SERVER_HAS_BODY="false";
SERVER_HAS_BODY_HYPERLINKS="false";
SERVER_HAS_BODY_IMAGES="false";
SERVER_HAS_BODY_MARKUP="false";
SERVER_HAS_ICON_MULTI="false";
SERVER_HAS_ICON_STATIC="false";
SERVER_HAS_PERSISTENCE="false";
SERVER_HAS_SOUND="false";

SERVER_NAME=;
SERVER_VENDOR=;
SERVER_VERSION=;
SERVER_SPEC_VERSION=;

################################################################################
## Imports

################################################################################
## Functions

# @describe - Allows you to filter characters from a given string. Note that
#             using multiple strings will concatenate them into the output.
# @usage - filter_chars FILTER STRING('s)...
# @param (STRING's) - The string or strings you wish to sanitize.
# @param FILTER - A string containing all the characters you wish to filter.
# @exitcode 0
filter_chars()
(
	ESCAPES="$1"; DONE=''; f=''; shift;

	OIFS="$IFS";
	IFS="$ESCAPES"; for f in $@; do DONE="$DONE$f"; done;
	IFS="$OIFS";

	printf '%s' "$DONE";
)

# @describe - Adds simple FPE math to test from the GNU coreutils library.
test()
(
	# Based on the latest docs:
	# https://www.gnu.org/software/coreutils/manual/coreutils.html#test-invocation
	f1=; b1=; f2=; b2=; lenb=;
	case "$1" in
		-[bcdfhLpStgkruwxOGesznN]) command test "$1" "$2"; return "$?";;
		*)
			f1="$1"; shift;
			case "$1" in
				-nt|-ot|-ef|'='|'=='|'!=') command test "$f1" "$1" "$2"; return "$?";;
				-eq|-ne|-lt|-le|-gt|-ge)
					# Convert the decimals into integers by shifting in tens to the left.
					# That way we can compute them.
					f1="${f1%%.*}"; f2="${2%%.*}";
					if command test "$f1" != "$ARG1"; then b1="${ARG#*.}"; fi;
					if command test "$f2" != "$2"; then b2="${2#*.}"; fi;

					if command test -z "$b1" && command test -z "$b2"; then
						# No modification needed.
						test "$f1" "$1" "$f2"; return "$?";
					fi;

					lenb="$((${#b1} - ${#b2}))";
					while command test "$lenb" -gt 0; do b2="${b2}0"; lenb=$((lenb - 1)); done;
					while command test "$lenb" -lt 0; do b1="${b1}0"; lenb=$((lenb - 1)); done;

					test "$f1$b1" "$1" "$f2$b2"; return "$?";
				;;
				*) test "$f1" "$1" "$f2"; return "$?";; # Let test throw our error.
			esac;
		;;
	esac;
);

# @describe - Compares Semantic Version strings using a similar syntax to `test`.
semver()
(
	v1="$1"; c="$2"; v2="$3"; shift 3;
	if test -n "$1"; then
		echo "too many arguments at: \"$1\"" >&2; return 2;
	fi;

	# @describe - Tokenizes a string into semver segments, or throws an error.
	tokenize_semver_string(){
		s="$1"; l=0; major='0'; minor='0'; patch='0'; prerelease=''; buildmetadata='';

		# Check for build metadata or prerelease
		f="${s%%[\-+]*}"; b="${s#*[\-+]}";
		if test -z "$f"; then
			echo "\"$1\" is not a Semantic Version." >&2; return 2;
		fi;
		OIFS="$IFS"; IFS=".";
		for ns in $f; do
			# Can't have empty fields, zero prefixes or contain non-numbers.
			if test -z "$ns" -o "$ns" != "${ns#0[0-9]}" -o "$ns" != "${ns#*[!0-9]}"; then
				echo "\"$1\" is not a Semantic Version." >&2; return 2;
			fi;

			case "$l" in
				'0') major="$ns";; '1') minor="$ns";; '2') patch="$ns";;
				*) echo "\"$1\" is not a Semantic Version." >&2; return 2;;
			esac;
			l=$(( l + 1 ));
		done;
		IFS="$OIFS";

		# Determine what character was used, metadata or prerelease.
		if test "$f-$b" = "$s"; then
			# if it was for the prerelease, check for the final build metadata.
			s="$b"; f="${s%%+*}"; b="${s#*+}";

			prerelease="$f";
			if test "$f" != "$b"; then buildmetadata="$b"; fi;

		elif test "$f+$b" = "$s"; then
			# If metadata, we're done processing.
			buildmetadata="$b";
		fi;

		OIFS="$IFS"; IFS=".";
		# prereleases and build metadata can have any number of letter fields,
		# alphanum, and numeric fields separated by dots.
		# Also protect buildmetadata and prerelease from special chars.
		for s in $prerelease; do
			case "$s" in
				# Leading zeros is bad juju
				''|0*[!1-9a-zA-Z-]*|*[!0-9a-zA-Z-]*)
					echo "\"$1\" is not a Semantic Version." >&2;
				IFS="$OIFS"; return 2;;
			esac;
		done;
		for s in $buildmetadata; do
			case "$s" in
				''|*[!0-9a-zA-Z-]*)
					echo "\"$1\" is not a Semantic Version." >&2;
				IFS="$OIFS"; return 2;;
			esac;
		done;
		IFS="$OIFS";
	}

	tokenize_semver_string "$v1" || return "$?";
	v11="$major"; v12="$minor"; v13="$patch"; v14="$prerelease"; v15="$buildmetadata";

	tokenize_semver_string "$v2" || return "$?";
	v21="$major"; v22="$minor"; v23="$patch"; v24="$prerelease"; v25="$buildmetadata";

	#############################################################################

	case "$c" in
		# Lexical comparision for basic eq and ne is fastest.
		-eq) test "$v11$v12$v13$v14" = "$v21$v22$v23$v24" || return $?;;
		-ne) test "$v11$v12$v13$v14" != "$v21$v22$v23$v24" || return $?;;
		-[gl][et])
			# Convert comparison into a single integer state.
			xv=0;
			if test "$v11" -gt "$v21"; then xv=$((xv + 4));
			elif test "$v11" -lt "$v21"; then xv=$((xv - 4)); fi;
			if test "$v12" -gt "$v22"; then xv=$((xv + 2));
			elif test "$v12" -lt "$v22"; then xv=$((xv - 2)); fi;
			if test "$v13" -gt "$v23"; then xv=$((xv + 1));
			elif test "$v13" -lt "$v23"; then xv=$((xv - 1)); fi;

			if ! test "$xv" "$c" 0; then return 1; fi;

			if test "$c" = '-gt' -a -n "$v14" -a -z "$v24" ||
			   test "$c" = '-lt' -a -z "$v14" -a -n "$v24";
			then
				return 1;
			fi;

			# Parse prerelease segments.
			OIFS="$IFS"; IFS='.'; s2b="$v24";
			# Loop through the first value we're checking actively, if it's none, then
			# we're either gt or ge the value we're comparing against.
			for s in $v14; do
				s2f="${s2b%%.*}"; s2b="${s2b#*.}";
				if "$s2f" = "$s2b"; then s2b=''; fi;
				# The spec says only numerical indicators need to be compared
				# mathmatically and the lingual spec doesn't mention chars needing
				# to be the preface to an alphanumeric section. So we can take
				# a shortcut here and assume anything containing a non-number
				# is compared lexically.

				# First half of equivalent suffix precedence test.
				# If 2f is empty, v1 <= v2
				if test -z "$s2f" -a "$c" = '-ge'; then return 1; else return 0; fi;

				# Check for lexical comparison type. Numeric comparison is the default.
				st=0; s2t=0;
				case "$s" in ''*[!0-9]*) st=1;; esac;
				case "$s2f" in
					''*[!0-9]*) s2t=1;; esac; # Would shorten but it breaks my code highlighting lol

				# Checks if our types are missmatched and returns failure if they are.
				if ! test "$st" "$c" "$s2t"; then return 1; fi;

				if "$st" -eq 0; then
					if ! test "$s" "$c" "$s2f"; then return 1; fi;
				else
					# Use expr for lexical comparison, it's a part of coreutils.
					if ! expr "$s" "$c" "$s2f"; then return 1; fi;
				fi;
			done;
			IFS="$OIFS";

			# Second half of equivalent suffix precedence test.
			if test -n "$s2b" -a "$c" = '-le'; then return 1; fi;
		;;
		*) echo "invalid conditional expression: \"$c\"" >&2; return 2;;
	esac;
);

process_capabilities() {
	eval "set $*"; # expand variables from pre-tic-quoted list.\
	for c in $@; do
		case "$c" in
			action-icons)    SERVER_HAS_ACTION_ICONS="true";;
			actions)         SERVER_HAS_ACTIONS="true";;
			body)            SERVER_HAS_BODY="true";;
			body-hyperlinks) SERVER_HAS_BODY_HYPERLINKS="true";;
			body-images)     SERVER_HAS_BODY_IMAGES="true";;
			body-markup)     SERVER_HAS_BODY_MARKUP="true";;
			icon-multi)      SERVER_HAS_ICON_MULTI="true";;
			icon-static)     SERVER_HAS_ICON_STATIC="true";;
			persistence)     SERVER_HAS_PERSISTENCE="true";;
			sound)           SERVER_HAS_SOUND="true";;
		esac;
	done;
}

process_server_info() {
	eval "set $*"; # expand variables from pre-tic-quoted list.
	SERVER_NAME="$1";
	SERVER_VENDOR="$2";
	SERVER_VERSION="$3";
	SERVER_SPEC_VERSION="$4";
}

################################################################################
## Main Script

# Fetch notification server info.
s="$(gdbus call --session \
		--dest org.freedesktop.Notifications \
		--object-path /org/freedesktop/Notifications \
		--method org.freedesktop.Notifications.GetServerInformation)";

s="$(filter_chars '(),' "$s")";
process_server_info "$s";

# Fetch notification server capabilities.
s="$(gdbus call --session \
		--dest org.freedesktop.Notifications \
		--object-path /org/freedesktop/Notifications \
		--method org.freedesktop.Notifications.GetCapabilities)";

s="$(filter_chars '[](),' "$s")";
process_capabilities "$s";

case "$1" in
	-h|--help);;
	--manual-fallback) MANUAL_FALLBACK='true';;
esac;

if test -e "$PROCDIR/auto-server/${SERVER_NAME}(${SERVER_VERSION}).sh"; then
	. "$PROCDIR/auto-server/${SERVER_NAME}(${SERVER_VERSION}).sh";
else
	if $MANUAL_FALLBACK; then
		/bin/sh $PROCDIR/manual.sh;
	else
		printf '%s\n' "Error: unable to run test suite for '$SERVER_NAME', unrecognized server." >&2;
		exit 1;
	fi;
fi;

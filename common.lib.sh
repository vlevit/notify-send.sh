# @file - common.source.sh
# @brief - Shared code for the notify-send.sh suite.
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

# NOTE: No code involved in this script should call functions outside itself.
#       This code is intended to be portable between applications, not static.

################################################################################
## Functions

abrt () { echo "Error in '$SELF': $*" >&2; exit 1; }

# @describe - Prints the simplest primitive type of a value.
# @usage - typeof [-g] VALUE
# @param "-g" - Toggles the numerical return values which increase in order of inclusivity.
# @param VALUE - The value you wish to check.
# @prints (5|'string') - When no other primitive can be coerced from the input.
# @prints (4|'filename') - When a string primitive is safe to use as a filename.
# @prints (3|'alphanum') - When a string primitive only contains letters and numbers.
# @prints (2|'double') - When the input can be coerced into a floating number.
# @prints (1|'int') - When the input can be coerced into a regular integer.
# @prints (0|'uint') - When the input can be coereced into an unsigned integer.
# @prints (Disabled|'binary') - When the input can be coerced into a binary value.
typeof() {
	local SIGNED=false FLOATING=false GROUP=false in='' f='' b='';

	# Check for group return parameter.
	if test "$1" = "-g"; then GROUP=true; shift; fi;

	in="$*";

	# Check for negation sign.
	test "$in" = "${b:=${in#-}}" || SIGNED=true;
	in="$b"; b='';

	# Check for floating point.
	if test "$in" != "${b:=${in#*.}}" -a "$in" != "${f:=${in%.*}}"; then
		if test "$in" != "$f.$b"; then
			$GROUP && echo "5" || echo "string"; return;
		fi;
		FLOATING=true;
	fi;

	case "$in" in
		''|*[!0-9\.]*)
			if test "$in" != "${in#*[~\`\!@\#\$%\^\*()\+=\{\}\[\]|:;\"\'<>,?\/]}"; then
				$GROUP && echo "5" || echo "string";
			else
				if test "$in" != "${1#*[_\-.\\ ]}"; then
					$GROUP && echo "4" || echo "filename";
				else
					$GROUP && echo "3" || echo "alphanum";
				fi;
			fi;;
		*)
			if $FLOATING; then $GROUP && echo "2" || echo "double"; return; fi;
			if $SIGNED; then $GROUP && echo "1" || echo "int"; return; fi;

			# NOTE: I only added this explicitly because GDBUS needs it.
			#       it registers strings of continuous ones and zeros as binary.
			#
			# NOTE: I was wrong, it accepts a decimal number only.
			#
			# if test "$in" = "${in#*[2-9]}"; then
			# 	$GROUP && echo "0" || echo "binary";
			# fi;

			$GROUP && echo "0" || echo "uint";
		;;
	esac;
}

# @describe - Ensures any characters that are embeded inside quotes can
#             be `eval`ed without worry of XSS / Parameter Injection.
# @usage [-p COUNT] sanitize_quote_escapes STRING('s)...
# @param STRING('s) - The string or strings you wish to sanitize.
# @param COUNT - The number of passes to run sanitization, default is 1.
sanitize_quote_escapes(){
	local ESCAPES="\\\"\$" TODO= DONE= PASSES=1 l=0 f= b= c=;

	if test "$1" = '-p'; then PASSES="$2"; shift 2; fi;

	TODO="$*"; # must be set after the conditional shift.

	while test "$l" -lt "$PASSES"; do
		# Ensure we cycle TODO after the first pass.
		if test "$l" -gt 0; then TODO="$DONE"; DONE=; fi;

		while test -n "$TODO"; do
			f="${TODO%%[$ESCAPES]*}"; # front of delimeter.
			b="${TODO#*[$ESCAPES]}"; # back of delimeter.

			# Only need to test one of the directions since $b and $f will be the same
			# if this is true.
			if test "$f" = "$TODO"; then break 2; fi;

			# Capture chracter by removing front
			test -z "$f" && c="$TODO" || c="${TODO#$f}";
			# and rear segments if they exist.
			test -z "$b"              || c="${c%$b}";

			DONE="$DONE$f\\$c";
			# Subtract front segment from TODO.
			TODO="${TODO#$f$c}";
		done;
		l="$((l + 1))"; # Increment loop counter.
	done;

	# If we haven't done anything, then just pass through the input.
	if test -z "$DONE"; then DONE="$TODO"; fi;
	printf '%s' "$DONE";
}

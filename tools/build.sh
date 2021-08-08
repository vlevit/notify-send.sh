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

VERSION='';

BUILD_DEB="true";
BUILD_SIGNED="true";
BUILD_RELEASE="false";

RESET_TARGETS="true";
TARGETS="deb:ubuntu"; # TODO: deb:debian deb:linuxmint
################################################################################
## Imports

################################################################################
## Functions

echo() { printf "%b\n" "$*"; }

reset_targets() {
	if $RESET_TARGETS; then
		TARGETS="";
		RESET_TARGETS="false";
	fi;
}

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

generate_build_version() {
	OIFS="$IFS"; IFS="-";
	set $(git describe --tag --long);
	# This is really fucking annoying
	eval "buildhash=\"\$$(($#))\"";
	eval "commitsahead=\"\$$(($# - 1))\"";
	tagversion="${@%-${commitsahead}-${buildhash}}";
	IFS="$OIFS";

	tokenize_semver_string "${tagversion#v}";
	if $BUILD_RELEASE; then
		if test -z "$VERSION"; then
			# Auto inc patch version if we haven't manually added a release version.
			VERSION="$major.$minor.$((patch + 1))";
			if test -n "$prerelease"; then
				VERSION="${VERSION}-$prerelease";
			fi;
		fi;
	else
		if test "$commitsahead" -gt 0; then
			# Empart a reasonable degree of precedence to the version. dev < rc
			VERSION="$major.$minor.$((patch + 1))-dev.$commitsahead.$buildhash";
			return 0;
		else
			# If we aren't any commits ahead of the last tag, we can assume we're
			# building a stable release.
			VERSION="${tagversion#v}";
		fi;
	fi;
}

build_package() {
	FORMAT="$1";
	DISTRO="$2";

	case "$FORMAT" in
		'deb')
			echo "Building \".deb\" package for \"$DISTRO\"";

			DEB_ROOT="$TEMPDIR/notify-send-sh_${VERSION}_all";
			CONTROL_ROOT="$DEB_ROOT/DEBIAN";

			# Make sure all our parent paths exist.
			mkdir -p "$CONTROL_ROOT";

			{
				echo 'Package: notify-send-sh';
				printf "%s\n" "Version: $VERSION";
				echo 'Architecture: all';
				echo 'Essential: no';
				echo 'Prioritiy: optional';

				printf '%s' 'Depends: coreutils (>= 8)';
				# We have to create separate distro packages because different distros
				# name their packages differently. Of all the stupid bullshit lol.
				case "$DISTRO" in
					# Upon researching into this, installing the `notification-daemon`
					# package should ensure we have a notification daemon needed to
					# actually display notifications. Not sure if this is actually
					# necessary or not, but it's helpful information. Could be good
					# for developing the test scripts. It's not in use on my system
					# at the time of writing even though it's installed. Probably
					# because it's superceeded by the XFCE notification daemon.
					"ubuntu") echo ", libglib2.0-bin (>= 2)";;
				esac;

				echo "Maintainer: $MAINTAINER";
				printf "%s %s %s\n" \
					"Description: An alternative CLI Gnome notification client. Intended to" \
					"be a near drop-in replacement for glib2's notify-send command with" \
					"more features.";
			} >> "$CONTROL_ROOT/control";

			# NOTE: Can I just say, this security model fucking sucks. WTF were the
			#       Debian devs thinking? Let's just get this done? Whyyyyyyyyyy
			#       Ah yes, let's just trust every package to be safe,
			#       there aren't any mallicious people on the web. It's fiiiiiiine.

			# {} >> "$CONTROL_ROOT/preinst";
			{
				echo '#!/bin/sh';
				# TODO: make sure this configures properly when notify alt already exists
				#       should eventually act as alternative for notify-send native.
				# echo 'update-alternatives' '--install /usr/bin/notify' 'notify'\
				#          '/opt/notify-send-sh/notify-send.sh' '80;';
				echo "{";
				echo "	cd /usr/bin;";
				echo "	ln -s /opt/notify-send-sh/notify-send.sh;";
				echo "	ln -s /opt/notify-send-sh/notify-exec.sh;";
				echo "}";
			} >> "$CONTROL_ROOT/postinst";

			# {} >> "$CONTROL_ROOT/prerm";
			{
				echo '#!/bin/sh';
				# TODO: remove this from the alternatives
				echo "{";
				echo "	cd /usr/bin;";
				echo "	rm notify-send.sh notify-exec.sh;";
				echo "}";
			} >> "$CONTROL_ROOT/postrm";


			#chmod 755 "$CONTROL_ROOT/preinst";
			chmod 755 "$CONTROL_ROOT/postinst";
			#chmod 755 "$CONTROL_ROOT/prerm";
			chmod 755 "$CONTROL_ROOT/postrm";

			#mkdir -p "${DEB_ROOT}/usr/local/bin";
			mkdir -p "${DEB_ROOT}/opt/notify-send-sh";
			cp -a -t "${DEB_ROOT}/opt/notify-send-sh" "$PROCDIR/../src/"*;

			dpkg-deb \
				--build "$DEB_ROOT" \
				"$PROCDIR/../build/notify-send-sh_v${VERSION}_${DISTRO}.deb";
		;;
	esac;
}

################################################################################
## Main Script

while test "$#" -gt 0; do
	case "$1" in
		-h|--help)
			echo 'Usage: build.sh [-hum] [-r [VERSION]] [-t "FORMAT:DISTRO" [-t ...]]';
			echo 'Description:';
			echo '\tBuild automation for notify-send-sh. By default builds all';
			echo '\tpackages for all distros. When a single option is specified,';
			echo '\tit only builds the specified target instead.';
			echo '';
			echo 'Help Options:';
			echo '\t-h|--help            Show help options.';
			echo '';
			echo 'Application Options:';
			echo "\t-m  --maintainer[=...]  Name of the maintainer for this build";
			echo "\t-u, --unsigned          Don't create hash checksums.";
			echo "\t-r, --release[=...]     Publish a new git release.";
			echo "\t-t, --target[=...]      Only build specific target distro in format";
			echo "\t    --list-targets      Print available targets";
			echo "\t    --list-formats      Print available formats";
			exit;
		;;
		-u|--unsigned) BUILD_SIGNED="false";;
		-r|--release|--release=*)
			if test "$1" != "${1#--release=}"; then s="${1#*=}";
				s="${s#v}";
				if ! tokenize_semver_string "$s"; then exit 1; fi;
				VERSION="$s";
			fi;
			BUILD_RELEASE='true';
		;;
		-t|--target|--target=*)
			if test "$1" != "${1#--release=}"; then s="${1#*=}"; else shift; s="$1"; fi;
			reset_targets;
			TARGETS="$TARGETS $s";
		;;
		-m|--maintainer|--maintainer=*)
			if test "$1" != "${1#--maintainer=}"; then s="${1#*=}"; else shift; s="$1"; fi;
			MAINTAINER="$s";
		;;
		--list-targets)
			echo "Supported Targets:";
			echo "\tubuntu";
			# TODO:
			#echo "\tdebian";
			#echo "\tlinuxmint";
		;;
		--list-formats)
			echo "Supported Formats:";
			echo "\tdeb";
			# TODO:
			#echo "\trpm";
		;;
	esac;
	shift;
done;

# Fetch maintainer from git if it's not specified by CLI. Fail if we don't
# know them. The maintainer is crucial for ensuring people know who's resposible
# for a package, especially when it's misbehaving.
if test -z "$MAINTAINER" && ! MAINTAINER="$(git config --get user.name)"; then
	echo "Error: couldn't determine this build's maintainer using" >&2;
	echo "       'git config', please build again using the '-m' option." >&2;
fi;

generate_build_version;
rm -rf "$PROCDIR/../build";
mkdir -p "$PROCDIR/../build"; # We want our build files to appear in the repo root.
TEMPDIR="$(mktemp -p "$TMP" -d "notify-send-sh_build.XXX")";
trap "rm -rvf $TEMPDIR" 0;

for format_distro in $TARGETS; do
	OIFS="$IFS"; IFS=":";
	build_package $format_distro;
	IFS="$OIFS";
done;

# Hash generation and signing
# https://www.gnupg.org/gph/en/manual/x135.html
if $BUILD_SIGNED; then
	for file in "$PROCDIR/../build/"*; do
		sha256sum "$file" >> "$PROCDIR/../build/sums.sha256";
	done;

	gpg --detach-sign "$PROCDIR/../build/sums.sha256";
fi;

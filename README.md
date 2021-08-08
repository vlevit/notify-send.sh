# `notify-send.sh`
[![](https://img.shields.io/badge/version-SemVer-informational)](https://semver.org/)
[![](https://img.shields.io/badge/shell-POSIX-informational)](https://pubs.opengroup.org/onlinepubs/9699919799)
[![](https://img.shields.io/badge/linter-ShellCheck-informational)](https://github.com/koalaman/shellcheck)
![](https://img.shields.io/badge/build-untested-important)

notify-send.sh is a replacement solution for notify-send (from
libnotify) with many extra features you might find useful.

This is a fork of [bkw777's][bkw777] fork of [vlevit's original script!][vlevit]
The main purpose of my fork is to address portability but I added a lot of
other features too:
 * I ensured that `notify-send.sh` and the other child services are now
   written in nothing but pure [POSIX][POSIX] compliant shell. Which includes
   `ksh`, `csh`, `bash`, `ash`, `dash`, `fish` and more shells.
 * `notify-action.sh` is now more user friendly.
 * Added `notify-exec.sh` to serve as an action status notifier.
 * `notify-send.sh` can now report information about the notification server.
 * I made a great deal of effort to ensure this complies with [standard][standard].

The reason I chose **bkw777's** fork as my base, was the effort they put in
to remove the external tools, here-docs, make `notify-send` more compliant
with the notification client standards, and [other useful features][big-changes].

The dependencies are GNU's `coreutils`, `gdbus` (shipped with glib2), and a any
POSIX compliant shell as a runtime provider.

In Ubuntu you can ensure all dependencies are installed with the
following command (this also prevents automatic install state clobbering):

```sh
if ! dpkg -S "$(type -p gdbus)"; then sudo apt-get install libglib2.0-bin; fi;
```

***forewarning:*** The TUI has changed, from master. The original TUI wasn't
POSIX compliant. It sought to emulate and replace notify-send, which used
a non-POSIX-compliant TUI. That has been discarded in favor of POSIX adherence:
using `-h` for help over `-?`; `--hint`'s partner has been changed to `-H`.
Linux is POSIX compliant, and I would argue any OS derived from it should at
least maintain consistency within that specification. It provides
a unified interface for users that removes complications when moving between
alternative distributions.

In the future, I may inquire about introducing these features upstream within
`notify-send`. I don't want to introduce any extra complexity into the
Linux notification ecosystem by releasing this toolkit. Think of this as a
proof of concept project.

### Examples

If we want to notify a user of a new email we can run something like the following:
```sh
notify-send.sh \
	--icon=mail-unread \
	--app-name=mail \
	--hint=string:sound-name:message-new-email \
	"Subject" "Message";
```

Just want to say something?
```sh
notify-send.sh "Hello World!" "carpe diem! lorem ipsum, tu amo.";
```


#### Lifetime Management
Let's say you want to update the body of a notification, you can do that!
```sh
# To replace or close existing message first we should know its id. To
# get id we have to run notify-send.sh with `--print-id`.
notify-send.sh --print-id "Subject" "Message"
# Prints: 10

# Now we can update this notification using `--replace` option.
notify-send.sh --replace=10 "New Subject" "New Message"

# Now we may want to close the notification if we didn't set an appropriate
# timeout.
notify-send.sh --close=10
```

Maybe you need to update the same notification several times.
The `--replace-file` parameter is your best friend.
```sh
# Every time this runs, it increases the volume by 5% and displays the new volume.
notify-send.sh \
	--replace-file=/tmp/volumenotification \
	"Increase Volume" "$(amixer sset Master 5%+ | awk '/[0-9]+%/ {print $2,$5}')"
```


#### User Action Triggers

Sometimes you'll need to have users interact with a notification to trigger
an action. There are three different types of action triggers you can use
to achieve your goals.

```sh
# The following will create a notification with a default action.
# Default actions are usually invoked when the notification area is clicked.
# NOTE: No two notification servers are the same and some implement this
#       feature differently. Know your target operating system and server.
notify-send.sh \
	-d "notify-send.sh 'Default Action' 'I was triggered as a default action!'" \
	"Click Me!" "Please 🥺";

# This will make a button using the quoted text before the colon.
# Multiple buttons can be used on the same notification.
notify-send.sh \
	-o "Click Me!":"notify-send.sh 'Wow <3' 'Click harder senpai!'" \
	"I have a button UwU" "You should press it...";

# Finally, this runs a command when the notification closes regardless of
# whether or not any other action was executed.
notify-send.sh \
	-l "notify-send.sh '(╬ ಠ益ಠ)' 'ლ(ಠ益ಠლ)'" \
	"I'm angy." "No touchy!";
```

#### Diagnostics / Server Information

Find information about your notification server by using the
`--server-info` and `--list-capabilities` options.

```sh
# On my machine I'm running Xfce as my session manager.
notify-send.sh --server-info;
# Name:           'Xfce Notify Daemon'
# Vendor:         'Xfce'
# Server Version: '0.4.2'
# Spec. Version:  '1.2'
```

```sh
# You get the gist. Right?
notify-send.sh --list-compatabilies;
# Status of server capabilities:
# "actions"         - SUPPORTED
# "action-icons"    - UNSUPPORTED
# "body"            - SUPPORTED
# "body-hyperlinks" - SUPPORTED
# "body-images"     - UNSUPPORTED
# "body-markup"     - SUPPORTED
# "icon-frames"     - STATIC
# "persistence"     - UNSUPPORTED
# "sound"           - UNSUPPORTED
```


[vlevit]: https://github.com/vlevit/notify-send.sh
[bkw777]: https://github.com/bkw777/notify-send.sh
[POSIX]: https://pubs.opengroup.org/onlinepubs/9699919799
[coreutils]: https://git.savannah.gnu.org/cgit/coreutils.git/tree/README?h=v8.27#n8
[big-changes]: https://github.com/bkw777/mainline/blob/master/lib/notify_send/mainline_changes.txt
[standard]: https://developer.gnome.org/notification-spec/

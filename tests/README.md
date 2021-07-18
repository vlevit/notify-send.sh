# Testing `notify-send.sh`

**Okay, so long story short, I'm not working on this for a while because it
demands that I write chroot encapsulation** I've done this before and
in this situation it looks to be far too much time to be worth it. So this
is going untested unless someone else wants to finish my work. Or until
I work back to this, which probably won't be until the next millennia.

&#x1F627; Please help.


7:19AM (UTC) 07/18/2021 [Three days following the notes above.]
TODO: epiphany! I just realized I don't have to heuristically test this using
other market available notification daemons. What I need to do is impersonate
a backend, intercept all the notification data and validate that the intent
is being communicated properly. This is a client, not a server, and shouldn't
need to be responsible for how servers handle my responses; all I need to do
is make sure my vocabulary is communicated within spec. But ofc this requires
an entire rewrite of my test strategy. I'll probably end up writing the new
version in python when I eventually get to it. This actually reduces the
complexity of testing because I can use a chroot without needing to spawn
a new Xorg server and session manager since I'll be essentially spoofing them.
I still need the chroot to swap out the shells for compatibility testing though.

---

To test this script, you'll need at least a single POSIX compliant shell,
and `xdotool` which provides the Xorg Window manipulation needed for
automatic testing. Along with all the other dependencies `notify-send.sh`
needs to run by itself.

(**I've only personally tested `dash`...**)
This is a short list of widely used shells:
 * [Korn Shell][ksh]
 * [C Shell][csh]
 * [Debian Almquist Shell][dash]
 * [Bourne Again Shell][bash]
 * [Almquist Shell][ash]


There are three suites:
 1. `total.sh` runs the `automanual.sh` suite in every
    known POSIX compliant shell you have installed on your machine and
    compiles the result. Using CLI arguments, it can also include the
    `manual.sh` tests, but this isn't recommended.
 2. `automanual.sh` runs the validation for each notify script on the current server.
 3. `manual.sh` should only be run for comprehensive diagnostics when
    something's gone terribly wrong. This suite includes any test that
    I haven't been able to engineer a way to automate around. It's all
    manual validation honey!


Until I validate CI can handle emulating Xorg and everything else it needs
for testing, I'll be using `automanual.sh` and `manual.sh` to test things on my end.
I understand the limitations of these circumstances, I'm only testing on one server,
and my shell diversity is abysmal. So if you have any bugs, please run
this suite on your machine and file a bug report. I'll get it as fast as I can.


[bash]: https://placeholder.com
[ksh]: https://placeholder.com
[csh]: https://placeholder.com
[dash]: https://placeholder.com
[ash]: https://placeholder.com

# Testing `notify-send.sh`

To test this script, you'll need at least a single POSIX compliant shell,
and `xdotool` which provides the Xorg Window manipulation needed for
automatic testing. Along with all the other dependencies `notify-send.sh`
needs to run by itself.

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
 2. `automanual.sh` runs the validation for each notify script call.
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

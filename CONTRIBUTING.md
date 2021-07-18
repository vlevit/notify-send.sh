# Guidelines for this fork.

## Git PRs and Commit bits.
For this project, I use https://commonflow.org, with the exception that
I only allow PRs to the `develop` branch, because it provides a buffer between
versioning releases and `latest` / `master` branch updates.

## Code Standards
Similar to [LinuxCommand's scripting standard][LCstandard],
each source file must organize the code into four different sections:
 1. **Globals** to be used within the script (excluding single character
     or temporary variables).
 2. **Imports** which consolidate shared code.
 3. **Functions** used within the current script.
 4. **Main** as the actual execution chain of the script.

This helps keep the chain of execution concise and improves readability.
Under very limited circumstances should shared setup / main code be distributed
into an Import. I have no idea how to quantify that right now &#x1F627; so just
submit your PR and I'll give you some feedback on my thoughts. Sorry I don't
have a better answer at the moment.

For single or double quotes, you can use either. I try to limit double quotes
wherever possible because I think it saves CPU cycles, but that's just me.

### Subshells

Try to limit subshell usage at all times. They can have a very large impact on
performance over many calls. Given this negligible in most cases, it does help
to cut down on CPU cycles, power; you know the drill. There are a few cases
where using subshells is encouraged however, such as:
 * Maintaining portability.
 * Redirecting a result from stdout or stderr into a variable.
 * Local variable emulation (another case for portability).

### Documentation & Comments

Only portable code needs documentation. But you may add documentation to
application specific code should you so choose. The documentation syntax
for this project is similar to [shdoc][shdoc], but since all of the portable
functions use subshells and need in most cases share their results as a
string, I've modified it. There isn't an engine to render it for you,
so it'll only reside in the code for now.

 * `@param` denotes a parameter description, instead of `@arg`.
 * `@usage` provides function signatures using [man syntax][manflow].
   For the direct docs see [man(1)][manman].
 * `@prints` describes a printed return value. Multiple can be used.

`describe`, `brief`, `example`, `noargs`, `exitcode` and `file` have been
left untouched.


Extraneous comments can actually make code harder to read. So please keep
comments to a minimum, and let the code annotate itself. Unless you're using
very obscure variable names or you're doing something hacky.

### POSIX Compliance

All code should adhear to the [POSIX spec][POSIX] alone. If you want to use
conventions outside of POSIX like bashisms, please create a fork. I won't
be accepting PRs with them.

[POSIX]: https://pubs.opengroup.org/onlinepubs/9699919799
[shdoc]: https://github.com/reconquest/shdoc
[manflow]: https://unix.stackexchange.com/a/425026/276952
[manman]: https://man7.org/linux/man-pages/man1/man.1.html
[LCstandard]: https://linuxcommand.org/lc3_adv_standards.php

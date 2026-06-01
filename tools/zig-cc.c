/* zig-cc.c -- a single-binary `zig cc` launcher.
 *
 * mrustc execs its $CC as ONE program, so "zig cc" (with a space) can't be the
 * value. build.zig compiles this with `zig cc` itself and points mrustc's CC at
 * it. It execs `$ZIG cc <args...>` ($ZIG defaults to "zig"), optionally
 * appending the object in $ZIGCC_EXTRA so a Zig kernel can be linked into
 * mrustc's output. Written in C (not Zig) on purpose: Zig 0.16 routes process
 * exec through its new Io interface, which differs across 0.15/0.16/0.17, while
 * C's execvp is stable -- so this stays portable and needs no shell. */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

int main(int argc, char **argv) {
    const char *zig = getenv("ZIG"); if (!zig || !*zig) zig = "zig";
    const char *extra = getenv("ZIGCC_EXTRA");
    int n = argc - 1;                         /* args after argv[0] */
    int extra_n = (extra && *extra) ? 1 : 0;
    char **a = calloc((size_t)(2 + n + extra_n + 1), sizeof(char *));
    int i = 0;
    a[i++] = (char *)zig;
    a[i++] = "cc";
    for (int j = 1; j < argc; j++) a[i++] = argv[j];
    if (extra_n) a[i++] = (char *)extra;
    a[i] = NULL;
    execvp(zig, a);
    fprintf(stderr, "zig-cc: cannot exec '%s': ", zig); perror(NULL);
    return 127;
}

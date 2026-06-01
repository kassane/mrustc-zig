/* expect-fail.c -- run argv[1..] and exit 0 iff that command FAILS (a non-zero
 * exit OR death by signal); exit 1 if it unexpectedly succeeds.
 *
 * Used by the `tests/parse-fail/` negative tests: mrustc rejects malformed Rust,
 * but *how* it terminates is platform / toolchain dependent -- it `abort()`s
 * (SIGABRT) on some builds and exits non-zero on others -- so the test must
 * accept ANY failure rather than one specific exit term. Written in C (compiled
 * by `zig cc`, like tools/zig-cc.c) using POSIX fork/execvp/waitpid so it is
 * stable across the Zig versions whose std process API differs; build.zig then
 * just asserts this helper exits 0. No shell involved. */
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "expect-fail: need a command\n"); return 2; }

    pid_t pid = fork();
    if (pid < 0) { perror("expect-fail: fork"); return 2; }
    if (pid == 0) {            /* child: become the command under test */
        execvp(argv[1], &argv[1]);
        perror("expect-fail: execvp");
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) { perror("expect-fail: waitpid"); return 2; }

    /* success (clean exit 0) is the FAILURE of a negative test; anything else
       (non-zero exit, or killed by a signal such as SIGABRT) is the pass. */
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        fprintf(stderr, "expect-fail: command unexpectedly succeeded: %s\n", argv[1]);
        return 1;
    }
    return 0;
}

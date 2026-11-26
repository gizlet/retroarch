/*
 * The package's entry. The Gizlet Store requires an ELF executable there,
 * so this static program runs the shell script beside it with the same
 * name plus ".sh", passing its arguments on.
 */
#define _POSIX_C_SOURCE 200809L

#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    char script[PATH_MAX];
    ssize_t length = readlink("/proc/self/exe", script, sizeof(script) - 4);
    if (length < 0) {
        perror("/proc/self/exe");
        return 1;
    }
    if (length >= (ssize_t)(sizeof(script) - 4)) {
        fputs("The package path is too long.\n", stderr);
        return 1;
    }
    memcpy(script + length, ".sh", sizeof(".sh"));
    if (argc > 0) {
        argv[0] = script;
    }
    execv(script, argv);
    perror(script);
    return 1;
}

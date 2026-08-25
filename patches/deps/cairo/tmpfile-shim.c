
#ifdef __wasi__
/* wasi-libc has no tmpfile() — and no mkstemp() either ("WASI has no temp
   directories"). The runtime contract mounts a writable TMPDIR, so build
   one there: unique name via a per-process counter, O_EXCL creation, and
   the classic unlink-while-open idiom. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
FILE *
tmpfile (void)
{
    static int counter = 0;
    const char *dir = getenv ("TMPDIR");
    char path[512];
    int attempt;
    if (dir == NULL || *dir == '\0')
        dir = "/tmp";
    for (attempt = 0; attempt < 100; attempt++) {
        int fd;
        FILE *f;
        snprintf (path, sizeof (path), "%s/cairo-tmp-%d-%d",
                  dir, counter++, attempt);
        fd = open (path, O_RDWR | O_CREAT | O_EXCL, 0600);
        if (fd < 0)
            continue;
        f = fdopen (fd, "w+b");
        if (f == NULL) {
            close (fd);
            unlink (path);
            return NULL;
        }
        unlink (path);
        return f;
    }
    return NULL;
}
#endif

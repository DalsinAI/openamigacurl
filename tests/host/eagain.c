/* openamigacurl host test: an LD_PRELOAD shim that makes every Nth send or
 * recv answer EAGAIN and cuts the rest short, so the OpenTLS backend's
 * would-block paths run. MIT, Copyright (c) 2026 AmigaChrome Team. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/socket.h>

static unsigned calls;

static int stall(void)
{
    static int every = -1;
    if (every < 0) {
        const char *e = getenv("EAGAIN_EVERY");
        every = e ? atoi(e) : 3;
    }
    return every > 0 && ++calls % (unsigned)every == 0;
}

typedef ssize_t (*send_fn)(int, const void *, size_t, int);
typedef ssize_t (*sendto_fn)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
typedef ssize_t (*recv_fn)(int, void *, size_t, int);
typedef ssize_t (*recvfrom_fn)(int, void *, size_t, int, struct sockaddr *, socklen_t *);

#define NEXT(name, type) static type real; if (!real) real = (type)dlsym(RTLD_NEXT, name)

ssize_t send(int fd, const void *buf, size_t n, int flags)
{
    NEXT("send", send_fn);
    if (stall()) { errno = EAGAIN; return -1; }
    return real(fd, buf, n > 700 ? 700 : n, flags);
}

ssize_t sendto(int fd, const void *buf, size_t n, int flags, const struct sockaddr *a, socklen_t l)
{
    NEXT("sendto", sendto_fn);
    if (stall()) { errno = EAGAIN; return -1; }
    return real(fd, buf, n > 700 ? 700 : n, flags, a, l);
}

ssize_t recv(int fd, void *buf, size_t n, int flags)
{
    NEXT("recv", recv_fn);
    if (stall()) { errno = EAGAIN; return -1; }
    return real(fd, buf, n > 500 ? 500 : n, flags);
}

ssize_t recvfrom(int fd, void *buf, size_t n, int flags, struct sockaddr *a, socklen_t *l)
{
    NEXT("recvfrom", recvfrom_fn);
    if (stall()) { errno = EAGAIN; return -1; }
    return real(fd, buf, n > 500 ? 500 : n, flags, a, l);
}

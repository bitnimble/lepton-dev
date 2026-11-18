#define LEPTON_NDK_HOST_TEST
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
/* pthread.h and sys/mman.h would clash with the shim's own libc declarations */
typedef unsigned long pthread_t;
extern int pthread_create(pthread_t *, const void *, void *(*)(void *), void *);
extern int pthread_join(pthread_t, void **);
int *__errno(void) { return &errno; }
int __android_log_write(int priority, const char *tag, const char *message) {
    (void)priority, (void)tag, (void)message;
    return 0;
}
#include "../patches/ndk_auxv.c"

#define MAPPINGS 20000
#define READERS 4

static char *read_fd(int fd, long *len) {
    long cap = 1 << 20, n = 0, r;
    char *buf = malloc(cap);
    while ((r = syscall(0, fd, buf + n, cap - n)) > 0) {
        n += r;
        if (n == cap) buf = realloc(buf, cap *= 2);
    }
    syscall(3, fd);
    *len = n;
    return buf;
}

static int has(const char *buf, long len, const char *needle) {
    return lepton_range_has(buf, len, needle);
}

static void check_guest_view(const char *who) {
    int fd = lepton_filtered_maps_fd();
    if (fd < 0) { fprintf(stderr, "%s: no filtered maps fd\n", who); exit(1); }
    long len;
    char *maps = read_fd(fd, &len);
    long lines = 0;
    for (long i = 0; i < len; i++) lines += maps[i] == '\n';
    if (!has(maps, len, "[stack]")) { fprintf(stderr, "%s: [stack] missing (%ld bytes)\n", who, len); exit(1); }
    if (lines < MAPPINGS) { fprintf(stderr, "%s: only %ld lines\n", who, lines); exit(1); }
    if (has(maps, len, "libc.so.6")) { fprintf(stderr, "%s: host libc leaked into the guest view\n", who); exit(1); }
    if (len && maps[len - 1] != '\n') { fprintf(stderr, "%s: last line unterminated\n", who); exit(1); }
    free(maps);
}

static void *reader(void *arg) {
    for (int i = 0; i < 5; i++) check_guest_view(arg);
    return 0;
}

int main(void) {
    for (int i = 0; i < MAPPINGS; i++) {
        /* alternating PROT_READ/PROT_NONE keeps the kernel from merging them into one line */
        if (syscall(9, 0L, 4096L, (long)(i % 2), 0x22L /* MAP_PRIVATE|MAP_ANONYMOUS */, -1L, 0L) == -1) {
            perror("mmap");
            return 1;
        }
    }
    check_guest_view("single reader");
    pthread_t threads[READERS];
    for (int i = 0; i < READERS; i++) pthread_create(&threads[i], 0, reader, "concurrent reader");
    for (int i = 0; i < READERS; i++) pthread_join(threads[i], 0);
    if (lepton_guest_syscall_p() != (unsigned long)&lepton_psum[2]) {
        fprintf(stderr, "no arm64 libc on the host, so P must be the shim's triple\n");
        return 1;
    }
    return 0;
}

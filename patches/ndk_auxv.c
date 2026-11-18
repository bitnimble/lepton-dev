/* SPDX-License-Identifier: MIT
 * Compatibility with Google's API 34 r14 NDK bridge, build-id
 * 553ba82b76bb5a11fd1d67b2c7e01b75. No proprietary code is included.
 * See README.md in this directory for ABI verification and limitations.
 * Explicit Bionic declarations allow building with the existing AOSP Clang
 * without downloading an NDK sysroot. This library is x86_64 Android only.
 *
 * Beyond the stock register/auxv shim this build adds three general
 * translation-fidelity/compat features, all version-robust (no per-game or
 * per-library hardcoded offsets):
 *   - guest-consistent /proc/self/maps and /proc/self/task/<tid>/syscall, so
 *     guest code never sees host-translator mappings or host-side PCs;
 *   - a low address bias for guest anonymous mmaps, so Unity's (and any guest
 *     allocator's) arm64 VA-ceiling assumption holds under berberis;
 *   - the translation mode is left to Lepton's rc (runtime.sh), not pinned here.
 * Every private-ABI poke stays gated on the bridge build-id check, so a future
 * NDK build disables those features instead of corrupting state; the libc-level
 * interposers (open/mmap) keep working regardless.
 */
extern int strcmp(const char *, const char *);
extern int memcmp(const void *, const void *, __SIZE_TYPE__);
extern int clock_gettime(int, void *);
struct lepton_timespec { long sec, nsec; };

static int missing_register(unsigned instruction) {
    unsigned opcode = instruction & ~31u;
    return opcode == 0xd5380000u || /* MIDR_EL1 */
           opcode == 0xd53be000u || /* CNTFRQ_EL0 */
           opcode == 0xd53be040u;   /* CNTVCT_EL0 */
}

/* Return 0 for unhandled instructions, 1 for success, -1 for clock failure. */
static int emulate_instruction(unsigned instruction, unsigned long *regs,
                            unsigned long *pc) {
    /* Event hints may complete without sleeping. Pair SEVL/SEV with a
     * nonblocking WFE: no guest can sleep waiting for an event we discarded.
     * Guest lock acquisition and memory ordering still use their original
     * atomic/barrier instructions. These hints provide no memory barrier.
     */
    if (instruction == 0xd50320bfu || /* SEVL */
        instruction == 0xd503209fu || /* SEV */
        instruction == 0xd503205fu) { /* WFE */
        *pc += 4;
        return 1;
    }
    if (!missing_register(instruction)) return 0;
    unsigned opcode = instruction & ~31u;
    unsigned long value;
    if (opcode == 0xd5380000u) {
        value = 0x410fd030; /* Generic Cortex-A53; do not claim Neoverse. */
    } else if (opcode == 0xd53be000u) {
        value = 1000000000UL; /* Counter ticks are CLOCK_MONOTONIC ns. */
    } else {
        struct lepton_timespec ts;
        if (clock_gettime(1, &ts)) return -1;
        value = (unsigned long)ts.sec * 1000000000UL + ts.nsec;
    }
    unsigned target = instruction & 31;
    if (target != 31) regs[target] = value; /* XZR discards the result. */
    *pc += 4;
    return 1;
}

#ifndef LEPTON_NDK_UNIT_TEST
#if (!defined(__ANDROID__) || !defined(__x86_64__)) && !defined(LEPTON_NDK_HOST_TEST)
#error This shim requires an x86_64 Android target
#endif
extern int *__errno(void);
extern int __android_log_write(int, const char *, const char *);
extern int unsetenv(const char *);
extern long syscall(long, ...);
extern int raise(int);
typedef struct {
    const char *name;
    void *base;
    const char *symbol;
    void *address;
} lepton_dl_info;
extern int dladdr(const void *, lepton_dl_info *);
extern void *dlsym(void *, const char *);
#define LEPTON_RTLD_NEXT ((void *)-1L)
#define EXPORT __attribute__((visibility("default")))
#define LOG(message) __android_log_write(4, "LeptonNdkAuxv", message)

/* Resolve the translator's own export past this interposer. Lets a build whose
 * private ABI we do not recognise fall through to the stock implementation
 * instead of crashing. */
static void *lepton_real(const char *mangled, void **cache) {
    void *f = __atomic_load_n(cache, __ATOMIC_ACQUIRE);
    if (!f) { f = dlsym(LEPTON_RTLD_NEXT, mangled); __atomic_store_n(cache, f, __ATOMIC_RELEASE); }
    return f;
}

static unsigned char *bridge_base;
static const unsigned char bridge_id[16] = {
    0x55,0x3b,0xa8,0x2b,0x76,0xbb,0x5a,0x11,
    0xfd,0x1d,0x67,0xb2,0xc7,0xe0,0x1b,0x75
};

/* Module base of the caller if it is the NDK bridge, else 0. */
static unsigned char *lepton_caller_in_bridge(const void *caller) {
    lepton_dl_info info = {0};
    if (!dladdr(caller, &info) || !info.name || !info.base) return 0;
    const char *name = info.name;
    for (const char *p = name; *p; p++) if (*p == '/') name = p + 1;
    return strcmp(name, "libndk_translation.so") ? 0 : info.base;
}

/* Module addresses/state offsets below belong ONLY to this reviewed build.
 * Validate its ELF note before reading any private translator state.
 */
static unsigned char *bridge_for_caller(const void *caller) {
    unsigned char *base = __atomic_load_n(&bridge_base, __ATOMIC_ACQUIRE);
    if (base) return base;
    base = lepton_caller_in_bridge(caller);
    if (!base) return 0;
    if (memcmp(base, "\177ELF\2\1", 6) ||
        memcmp(base + 0x298, bridge_id, sizeof bridge_id)) {
        LOG("Unsupported NDK bridge build; refusing private ABI access");
        return 0;
    }
    __atomic_store_n(&bridge_base, base, __ATOMIC_RELEASE);
    return base;
}

__attribute__((constructor)) static void loaded(void) {
    /* The guest linker must not try to load this host-architecture preload. */
    unsetenv("LD_PRELOAD");
    /* Do not set NDK_TRANSLATION_MODE here: runtime.sh's rc owns the mode and
     * leaves it unset for tiered, so a setenv here would clobber tiered to light. */
    LOG("Native register/auxv compatibility shim loaded");
}

static unsigned lepton_hex(char c) { return c >= 'a' ? c - 'a' + 10 : c - '0'; }

static int lepton_contains(const char *s, const char *sub) {
    for (; *s; s++) {
        const char *a = s, *b = sub;
        while (*a && *b && *a == *b) { a++; b++; }
        if (!*b) return 1;
    }
    return 0;
}

static int lepton_range_has(const char *s, long n, const char *sub) {
    for (long i = 0; i < n; i++) {
        long j = 0;
        while (sub[j] && i + j < n && s[i + j] == sub[j]) j++;
        if (!sub[j]) return 1;
    }
    return 0;
}

#define LEPTON_MAPS_CHUNK 0x10000L
#define LEPTON_MAPS_LINE_MAX 0x1100L

static void *lepton_scratch(long size) {
    long p = syscall(9, 0L, size, 3L /* RW */, 0x22L /* MAP_PRIVATE|MAP_ANONYMOUS */, -1L, 0L);
    return p == -1 ? 0 : (void *)p;
}

/* Calls fn on every /proc/self/maps line, without its newline. */
static int lepton_each_maps_line(void (*fn)(const char *line, long n, void *ctx), void *ctx) {
    long fd = syscall(257, -100L, "/proc/self/maps", 0L, 0L); /* openat AT_FDCWD O_RDONLY */
    if (fd < 0) return -1;
    char *chunk = lepton_scratch(LEPTON_MAPS_CHUNK + LEPTON_MAPS_LINE_MAX);
    if (!chunk) { syscall(3, fd); return -1; }
    char *line = chunk + LEPTON_MAPS_CHUNK;
    long ln = 0, n;
    while ((n = syscall(0, fd, chunk, LEPTON_MAPS_CHUNK)) > 0) {
        for (long i = 0; i < n; i++) {
            if (chunk[i] != '\n') {
                if (ln < LEPTON_MAPS_LINE_MAX) line[ln++] = chunk[i];
                continue;
            }
            fn(line, ln, ctx);
            ln = 0;
        }
    }
    if (ln) fn(line, ln, ctx);
    syscall(11, chunk, LEPTON_MAPS_CHUNK + LEPTON_MAPS_LINE_MAX);
    syscall(3, fd);
    return n < 0 ? -1 : 0;
}

/* Parses "start-end perms"; returns the perms' offset in line. */
static long lepton_maps_range(const char *line, long n, unsigned long *start, unsigned long *end) {
    long c = 0;
    *start = *end = 0;
    while (c < n && line[c] != '-') *start = *start * 16 + lepton_hex(line[c++]);
    if (c < n) c++;
    while (c < n && line[c] != ' ') *end = *end * 16 + lepton_hex(line[c++]);
    return c < n ? c + 1 : n;
}

struct lepton_module { const char *needle; unsigned long base, end; };

static void lepton_module_line(const char *line, long n, void *ctx) {
    struct lepton_module *m = ctx;
    if (!lepton_range_has(line, n, m->needle)) return;
    unsigned long s, e;
    lepton_maps_range(line, n, &s, &e);
    if (!m->base || s < m->base) m->base = s;
    if (e > m->end) m->end = e;
}

static int lepton_app_hex(char *buf, int p, unsigned long v) {
    buf[p++] = ' '; buf[p++] = '0'; buf[p++] = 'x';
    char t[16]; int ti = 0;
    if (!v) t[ti++] = '0'; else while (v) { unsigned d = v & 0xf; t[ti++] = d < 10 ? '0' + d : 'a' + d - 10; v >>= 4; }
    while (ti) buf[p++] = t[--ti];
    return p;
}

static void lepton_write_all(int fd, const char *buf, long len) {
    long wi = 0, w;
    while (wi < len && (w = syscall(1, fd, buf + wi, len - wi)) > 0) wi += w;
}

static int lepton_memfd(const char *name, const char *buf, long len) {
    int mfd = (int)syscall(319 /* memfd_create */, name, 0);
    if (mfd < 0) return -1;
    lepton_write_all(mfd, buf, len);
    syscall(8 /* lseek */, mfd, 0, 0);
    return mfd;
}

/* Which of two addresses fall in readable mappings. Guards a deref at a fixed offset
 * from a module base against landing in an inter-segment PROT_NONE gap. */
struct lepton_readable { unsigned long addr[2]; int readable[2]; };

static void lepton_readable_line(const char *line, long n, void *ctx) {
    struct lepton_readable *r = ctx;
    unsigned long s, e;
    long perms = lepton_maps_range(line, n, &s, &e);
    for (int i = 0; i < 2; i++)
        if (r->addr[i] >= s && r->addr[i] < e) r->readable[i] = perms < n && line[perms] == 'r';
}

/* Guest-consistent value for the /proc syscall PC field. On real arm64 the
 * kernel reports an address inside guest libc (its read-syscall return site);
 * that is what guest code expects to see, and it also happens to satisfy the
 * word[P-8]+word[P-4]+word[P]==0xFC000003 check some anti-tamper SDKs run. Read
 * only the known libc .text offset and verify (a blind scan risks a PROT_NONE
 * gap -> SIGSEGV); fall back to a shim-owned triple summing to the same value. */
static volatile unsigned int lepton_psum[3] = {0x54000001u, 0x54000001u, 0x54000001u};
static unsigned long lepton_guest_syscall_p(void) {
    static unsigned long cached; static int done;
    if (__atomic_load_n(&done, __ATOMIC_ACQUIRE)) return cached;
    unsigned long p = 0;
    struct lepton_module libc = { "/system/lib64/arm64/libc.so", 0, 0 };
    lepton_each_maps_line(lepton_module_line, &libc);
    unsigned long cand = libc.base + 0xe8a5;
    struct lepton_readable r = { { cand - 8, cand }, { 0, 0 } };
    if (libc.base && libc.end > cand) lepton_each_maps_line(lepton_readable_line, &r);
    if (r.readable[0] && r.readable[1]) {
        unsigned w0 = *(volatile unsigned *)(cand - 8), w1 = *(volatile unsigned *)(cand - 4), w2 = *(volatile unsigned *)cand;
        if ((unsigned)(w0 + w1 + w2) == 0xFC000003u) p = cand;
    }
    int fell_back = !p;
    if (!p) p = (unsigned long)&lepton_psum[2];
    cached = p;
    __atomic_store_n(&done, 1, __ATOMIC_RELEASE);
    __android_log_write(4, "LeptonSyscallP", fell_back ? "P = host-triple fallback" : "P = guest libc offset");
    return cached;
}

/* Serve /proc/self/task/<tid>/syscall as a memfd whose PC field is the guest P
 * above, so a reader verifying "the thread's PC lies in guest code" sees a true
 * guest address, not a host-translator one. Format: "<nr> <args...> <sp> <pc>". */
static int lepton_syscall_fd(void) {
    char out[96]; int oi = 0;
    for (const char *t = "63 0x41 0x0 0xff 0x0 0x0 0x0 0x0 0x"; *t; t++) out[oi++] = *t;
    unsigned long p = lepton_guest_syscall_p();
    char t[20]; int ti = 0;
    if (!p) t[ti++] = '0'; else while (p) { unsigned d = p & 0xf; t[ti++] = d < 10 ? '0' + d : 'a' + d - 10; p >>= 4; }
    while (ti) out[oi++] = t[--ti];
    out[oi++] = '\n';
    return lepton_memfd("s", out, oi);
}

/* Guest code parsing /proc/self/maps in the shared address space would otherwise
 * see the host x86_64 libc, the translator, its exec_region and the host linker.
 * Serve a memfd reduced to a pure-arm64 view (anon/stack/heap, arm64 libs, app
 * data, dev, ART artifacts). */
static int lepton_guest_visible(const char *line, long n) {
    long slash = 0;
    while (slash < n && line[slash] != '/') slash++;
    if (slash == n) return 1; /* anon, [stack], [heap], [anon:*] */
    const char *p = line + slash; long pn = n - slash;
    return lepton_range_has(p, pn, "/arm64/") || lepton_range_has(p, pn, "/data/") ||
           lepton_range_has(p, pn, "/dev/") || lepton_range_has(p, pn, "dalvik-cache") ||
           lepton_range_has(p, pn, ".art") || lepton_range_has(p, pn, ".oat") ||
           lepton_range_has(p, pn, ".vdex") || lepton_range_has(p, pn, ".odex") ||
           lepton_range_has(p, pn, "memfd") || lepton_range_has(p, pn, ".apk") ||
           lepton_range_has(p, pn, ".jar");
}

struct lepton_maps_out { int fd; char *buf; long n; };

static void lepton_guest_maps_line(const char *line, long n, void *ctx) {
    struct lepton_maps_out *out = ctx;
    if (!lepton_guest_visible(line, n)) return;
    if (out->n + n + 1 > LEPTON_MAPS_CHUNK) {
        lepton_write_all(out->fd, out->buf, out->n);
        out->n = 0;
    }
    for (long i = 0; i < n; i++) out->buf[out->n++] = line[i];
    out->buf[out->n++] = '\n';
}

static int lepton_filtered_maps_fd(void) {
    struct lepton_maps_out out = { (int)syscall(319 /* memfd_create */, "m", 0), lepton_scratch(LEPTON_MAPS_CHUNK), 0 };
    int ok = out.fd >= 0 && out.buf && lepton_each_maps_line(lepton_guest_maps_line, &out) == 0;
    if (ok) lepton_write_all(out.fd, out.buf, out.n);
    if (out.buf) syscall(11, out.buf, LEPTON_MAPS_CHUNK);
    if (!ok) {
        if (out.fd >= 0) syscall(3, out.fd);
        return -1;
    }
    syscall(8 /* lseek */, out.fd, 0, 0);
    return out.fd;
}

/* Returns a memfd, or -1 to fall through. */
static int lepton_maps_intercept(const char *path, const void *caller) {
    (void)caller;
    if (!path) return -1;
    if (!__atomic_load_n(&bridge_base, __ATOMIC_ACQUIRE)) return -1;
    if (lepton_contains(path, "/syscall")) return lepton_syscall_fd();
    if (lepton_contains(path, "/maps")) return lepton_filtered_maps_fd();
    return -1;
}

static int blocked_auxv(const char *path, const void *caller) {
    if (!path || strcmp(path, "/proc/self/auxv")) return 0;
    /* Do not use a cached module here: native callers must retain access. */
    lepton_dl_info info = {0};
    if (!dladdr(caller, &info) || !info.name) return 0;
    if (!lepton_caller_in_bridge(caller)) return 0;
    bridge_for_caller(caller);
    LOG("Denied host auxv to ARM64 guest; using Android fallback");
    *__errno() = 13; /* EACCES, supported by Go's Android sysargs fallback. */
    return 1;
}

/* NDK bridge guest-open routines ultimately call these Bionic entrypoints.
 * Forward native flags directly to x86_64 openat(2), preserving mode/errno.
 * Do not interpose the bridge's guest-open symbols: they are namespace-local.
 */
EXPORT int openat(int fd, const char *path, int flags, ...) {
    const void *caller = __builtin_return_address(0);
    if (blocked_auxv(path, caller)) return -1;
    int mfd = lepton_maps_intercept(path, caller);
    if (mfd >= 0) return mfd;
    __builtin_va_list ap;
    __builtin_va_start(ap, flags);
    unsigned mode = 0;
    if ((flags & 0x40) || (flags & 0x410000) == 0x410000)
        mode = __builtin_va_arg(ap, unsigned); /* O_CREAT or O_TMPFILE */
    __builtin_va_end(ap);
    return syscall(257, fd, path, flags, mode);
}
EXPORT int open(const char *path, int flags, ...) {
    const void *caller = __builtin_return_address(0);
    if (blocked_auxv(path, caller)) return -1;
    int mfd = lepton_maps_intercept(path, caller);
    if (mfd >= 0) return mfd;
    __builtin_va_list ap;
    __builtin_va_start(ap, flags);
    unsigned mode = 0;
    if ((flags & 0x40) || (flags & 0x410000) == 0x410000)
        mode = __builtin_va_arg(ap, unsigned);
    __builtin_va_end(ap);
    return syscall(257, -100, path, flags, mode); /* AT_FDCWD */
}

/* berberis's guest-mmap emulation (sys_mman_emulation.cc GuestMmap) forwards the
 * guest's NULL hint straight to the host mmap64, so on x86_64 the kernel places
 * the mapping above the 2TB an arm64 guest ever sees. Unity's checked allocator
 * (and any guest code assuming arm64's user-VA ceiling) then rejects the block.
 * Every guest mmap, JIT'd code included, funnels through this one host libc call
 * inside the translator, so biasing guest anonymous data mappings into a low
 * window here fixes the whole class with no per-engine offset. JIT code
 * (PROT_EXEC) and ART (caller not in the bridge) are left alone. */
#define LEPTON_GUEST_VA_FLOOR 0x100000000UL
#define LEPTON_GUEST_VA_CEILING 0x20000000000UL
static unsigned long lepton_guest_va_cursor = LEPTON_GUEST_VA_FLOOR;

static void *lepton_guest_mmap(void *addr, __SIZE_TYPE__ length, int prot, int flags,
                               int fd, long long offset, const void *caller) {
    /* Non-exec guest anon mappings only. Unity reserves its heap arena PROT_NONE and
     * commits later, so requiring PROT_WRITE here misses it and the 2TB check crashes
     * il2cpp; the bias must include PROT_NONE. */
    if (!addr && (flags & 0x20) && !(prot & 4) && length >= 0x100000 &&
        length < 0x1000000000UL && lepton_caller_in_bridge(caller)) {
        unsigned long size = (length + 0xfff) & ~0xfffUL;
        for (unsigned long swept = 0; swept < LEPTON_GUEST_VA_CEILING; swept += size) {
            unsigned long a = __atomic_fetch_add(&lepton_guest_va_cursor, size, __ATOMIC_RELAXED);
            if (a + size > LEPTON_GUEST_VA_CEILING) {
                /* a racing reset can hand out an overlapping range; NOREPLACE rejects it */
                __atomic_store_n(&lepton_guest_va_cursor, LEPTON_GUEST_VA_FLOOR, __ATOMIC_RELAXED);
                continue;
            }
            long r = syscall(9, (void *)a, length, prot, flags | 0x100000 /* MAP_FIXED_NOREPLACE */, fd, offset);
            if (r != -1) {
                static int logged;
                if (!__atomic_exchange_n(&logged, 1, __ATOMIC_RELAXED)) LOG("guest anonymous mmap biased below 2TB");
                return (void *)r;
            }
            if (*__errno() != 17 /* EEXIST */) break;
        }
    }
    return (void *)syscall(9, addr, length, prot, flags, fd, offset);
}
EXPORT void *mmap64(void *addr, __SIZE_TYPE__ length, int prot, int flags, int fd, long long offset) {
    return lepton_guest_mmap(addr, length, prot, flags, fd, offset, __builtin_return_address(0));
}
EXPORT void *mmap(void *addr, __SIZE_TYPE__ length, int prot, int flags, int fd, long long offset) {
    return lepton_guest_mmap(addr, length, prot, flags, fd, offset, __builtin_return_address(0));
}

EXPORT void fallback(void *)
    __asm__("_ZN15ndk_translation15LightTranslator13UndefinedInsnEv");
EXPORT void fallback(void *frontend) {
    unsigned char *base = bridge_for_caller(__builtin_return_address(0));
    if (!base) {
        static void *real;
        void (*f)(void *) = lepton_real("_ZN15ndk_translation15LightTranslator13UndefinedInsnEv", &real);
        if (f) f(frontend); else *(unsigned char *)frontend = 0;
        return;
    }
    /* success_ at 0x00. A failed translation discards the block and invokes
     * InterpretInsn. The original interpreter still handles (and rejects)
     * every opcode outside our explicit register-read and event-hint additions. */
    *(unsigned char *)frontend = 0;
}

EXPORT void interpret(void *)
    __asm__("_ZN15ndk_translation13InterpretInsnEPNS_12ProcessStateE");
EXPORT void interpret(void *state) {
    unsigned char *base = bridge_for_caller(__builtin_return_address(0));
    if (!base) {
        static void *real;
        void (*f)(void *) = lepton_real("_ZN15ndk_translation13InterpretInsnEPNS_12ProcessStateE", &real);
        if (f) f(state);
        return;
    }
    /* CPUState's X0..X30 begin at 0; insn_addr is at 0x310. */
    unsigned long *pc = (void *)((char *)state + 0x310);
    /* A raw svc read(fd, buf, 255) from interpreted code of /proc/.../syscall is the
     * other way an anti-tamper VM reaches that file (besides libc open, handled above);
     * rewrite its result the same way after the real read runs. */
    int is_syscall_read = 0;
    if (*(unsigned *)*pc == 0xd4000001u) {
        unsigned long *r = (unsigned long *)state;
        if (r[8] == 63 && r[2] == 0xff) {
            char path[40]; int pi = 0;
            for (const char *t = "/proc/self/fd/"; *t; t++) path[pi++] = *t;
            unsigned long fd = r[0]; char tmp[20]; int ti = 0;
            if (!fd) tmp[ti++] = '0'; else while (fd) { tmp[ti++] = '0' + fd % 10; fd /= 10; }
            while (ti) path[pi++] = tmp[--ti];
            path[pi] = 0;
            char lt[128]; long rl = syscall(267, -100, path, lt, sizeof(lt) - 1); /* readlinkat */
            if (rl > 0) { lt[rl] = 0; if (lepton_contains(lt, "syscall")) is_syscall_read = 1; }
        }
    }
    int result = emulate_instruction(*(unsigned *)*pc, state, pc);
    if (result < 0) { raise(4); return; }
    if (result) {
        static unsigned seen;
        if (__atomic_fetch_add(&seen, 1, __ATOMIC_RELAXED) < 4)
            LOG("Interpreted missing ARM register/event hint");
        return;
    }
    void (*original)(void *) = (void *)(base + 0x1d3bc0);
    original(state);
    if (is_syscall_read && (long)((unsigned long *)state)[0] > 0) {
        unsigned long *r = (unsigned long *)state;
        char *buf = (char *)r[1];
        int p = 0; buf[p++] = '6'; buf[p++] = '3';
        p = lepton_app_hex(buf, p, 0x41);
        p = lepton_app_hex(buf, p, r[1]);
        p = lepton_app_hex(buf, p, 0xff);
        p = lepton_app_hex(buf, p, 0);
        p = lepton_app_hex(buf, p, 0);
        p = lepton_app_hex(buf, p, 0);
        p = lepton_app_hex(buf, p, r[1]);
        p = lepton_app_hex(buf, p, lepton_guest_syscall_p());
        buf[p++] = '\n';
        r[0] = (unsigned long)p;
    }
}
#endif

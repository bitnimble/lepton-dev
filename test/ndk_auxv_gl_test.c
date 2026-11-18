#define LEPTON_NDK_HOST_TEST
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
int *__errno(void) { return &errno; }
int __android_log_write(int priority, const char *tag, const char *message) {
    (void)priority, (void)tag, (void)message;
    return 0;
}
#include "../patches/ndk_auxv.c"

extern void *bridge_lookup(void *, const char *);

static const unsigned char *host_glGetString(unsigned name) {
    return (const unsigned char *)(name == 0x1F03 ? "GL_OES_host_extension" : "host value");
}
void *__loader_dlsym(void *handle, const char *symbol, const void *caller) {
    (void)handle, (void)caller;
    return strcmp(symbol, "glGetString") ? 0 : (void *)host_glGetString;
}

static int profile = 1;
int __system_property_get(const char *name, char *value) {
    const char *v = "";
    if (profile && !strcmp(name, "ro.lepton.gl_vendor")) v = "Qualcomm";
    if (profile && !strcmp(name, "ro.lepton.gl_renderer")) v = "Adreno (TM) 740";
    int n = 0;
    while ((value[n] = v[n])) n++;
    return n;
}

static void expect(const char *what, const unsigned char *got, const char *want) {
    if (strcmp((const char *)got, want)) {
        fprintf(stderr, "%s: got \"%s\", want \"%s\"\n", what, got, want);
        exit(1);
    }
}

typedef const unsigned char *(*get_string)(unsigned);

int main(void) {
    get_string translated = (get_string)bridge_lookup(0, "glGetString");
    expect("translated GL_VENDOR", translated(0x1F00), "Qualcomm");
    expect("translated GL_RENDERER", translated(0x1F01), "Adreno (TM) 740");
    expect("translated GL_VERSION without a profile value", translated(0x1F02), "host value");
    expect("translated GL_EXTENSIONS", translated(0x1F03), "GL_OES_host_extension");

    get_string native = (get_string)dlsym(0, "glGetString");
    expect("native GL_VENDOR", native(0x1F00), "host value");

    if (bridge_lookup(0, "glGetStringi") != 0) { fprintf(stderr, "other symbols pass through\n"); return 1; }

    profile = 0;
    get_string unprofiled = (get_string)bridge_lookup(0, "glGetString");
    if ((void *)unprofiled != (void *)host_glGetString) {
        fprintf(stderr, "without a device profile the translator gets the host glGetString\n");
        return 1;
    }
    return 0;
}

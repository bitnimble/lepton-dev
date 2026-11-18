extern void *dlsym(void *, const char *);

void *bridge_lookup(void *handle, const char *symbol) {
    return dlsym(handle, symbol);
}

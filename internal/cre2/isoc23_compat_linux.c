typedef unsigned long size_t;
extern long strtol(const char *, char **, int) __asm__("strtol");
extern unsigned long strtoul(const char *, char **, int) __asm__("strtoul");
extern long long strtoll(const char *, char **, int) __asm__("strtoll");
extern unsigned long long strtoull(const char *, char **, int) __asm__("strtoull");
__attribute__((weak)) long __isoc23_strtol(const char *s, char **e, int b) { return strtol(s, e, b); }
__attribute__((weak)) unsigned long __isoc23_strtoul(const char *s, char **e, int b) { return strtoul(s, e, b); }
__attribute__((weak)) long long __isoc23_strtoll(const char *s, char **e, int b) { return strtoll(s, e, b); }
__attribute__((weak)) unsigned long long __isoc23_strtoull(const char *s, char **e, int b) { return strtoull(s, e, b); }

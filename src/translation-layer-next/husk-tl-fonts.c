/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Portable font VFS shared by bionic directory calls and the NDK font iterator. */
#define _DARWIN_C_SOURCE
#define _DEFAULT_SOURCE
#include "husk-tl-fonts.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

static char g_sysfonts[1024], g_extrafonts[1024];
void tl_set_system_fonts_dir(const char *dir) { snprintf(g_sysfonts, sizeof(g_sysfonts), "%s", dir ? dir : ""); }
void tl_set_extra_fonts_dir(const char *dir) { snprintf(g_extrafonts, sizeof(g_extrafonts), "%s", dir ? dir : ""); }

/* Return the path relative to an Android root, not an arbitrary prefix match.
 * Java boot sets ANDROID_ROOT to the writable app directory; Unity appends
 * /etc/fonts.xml as well as /fonts to it. Do not redirect its other data. */
static const char *relative_path(const char *path)
{
    if (!path || !g_sysfonts[0]) return NULL;
    if (!strncmp(path, "/system/", 8)) return path + 7;
    const char *root = getenv("ANDROID_ROOT");
    size_t len = root ? strlen(root) : 0;
    while (len && root[len - 1] == '/') len--;
    if (len && !strncmp(path, root, len) && path[len] == '/') return path + len;
    return NULL;
}
static const char *font_suffix(const char *path)
{
    const char *p = relative_path(path);
    return p && !strncmp(p, "/fonts", 6) && (!p[6] || p[6] == '/') ? p + 6 : NULL;
}
bool tl_fonts_is_directory(const char *path)
{
    const char *p = font_suffix(path);
    if (!p) return false;
    while (*p == '/') p++;
    return !*p;
}
const char *tl_fonts_resolve(const char *path, char *buf, size_t n)
{
    const char *suffix = font_suffix(path);
    if (suffix) {
        snprintf(buf, n, "%s/fonts%s", g_sysfonts, suffix);
        if (g_extrafonts[0] && suffix[0] == '/' && access(buf, F_OK) != 0) {
            char extra[2048];
            snprintf(extra, sizeof(extra), "%s%s", g_extrafonts, suffix);
            if (access(extra, F_OK) == 0) snprintf(buf, n, "%s", extra);
        }
        return buf;
    }
    const char *p = relative_path(path);
    if (p && (!strcmp(p, "/etc/fonts.xml") || !strcmp(p, "/etc/font_fallback.xml"))) {
        snprintf(buf, n, "%s%s", g_sysfonts, p);
        return buf;
    }
    return NULL;
}

struct tl_font_dir {
    DIR *system, *extra;
    bool reading_extra;
    char system_path[1100];
};
static bool font_file(const char *name)
{
    size_t n = strlen(name);
    return n > 4 && (!strcasecmp(name + n - 4, ".ttf") ||
                    !strcasecmp(name + n - 4, ".ttc") || !strcasecmp(name + n - 4, ".otf"));
}
tl_font_dir *tl_fonts_open(void)
{
    if (!g_sysfonts[0]) { errno = ENOENT; return NULL; }
    tl_font_dir *d = calloc(1, sizeof(*d));
    if (!d) return NULL;
    snprintf(d->system_path, sizeof(d->system_path), "%s/fonts", g_sysfonts);
    d->system = opendir(d->system_path);
    if (g_extrafonts[0] && strcmp(g_extrafonts, d->system_path)) d->extra = opendir(g_extrafonts);
    if (!d->system && !d->extra) { int e = errno; free(d); errno = e; return NULL; }
    errno = 0;
    return d;
}
struct dirent *tl_fonts_read(tl_font_dir *d)
{
    struct dirent *e;
    if (!d->reading_extra) {
        if (d->system) {
            errno = 0;
            e = readdir(d->system);
            if (e || errno) return e;
        }
        d->reading_extra = true;
    }
    if (!d->extra) return NULL;
    for (;;) {
        errno = 0;
        e = readdir(d->extra);
        if (!e) return NULL;
        /* The extra directory can be the app bundle root, not only a font folder.
         * Never expose its executable, artwork, subdirectories, or duplicate fonts. */
        if (!font_file(e->d_name)) continue;
        char path[2048]; struct stat st;
        snprintf(path, sizeof(path), "%s/%s", d->system_path, e->d_name);
        if (access(path, F_OK) == 0) continue; /* same precedence as file lookup */
        snprintf(path, sizeof(path), "%s/%s", g_extrafonts, e->d_name);
        if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        errno = 0;
        return e;
    }
}
void tl_fonts_rewind(tl_font_dir *d)
{
    if (d->system) rewinddir(d->system);
    if (d->extra) rewinddir(d->extra);
    d->reading_extra = false;
}
int tl_fonts_dirfd(tl_font_dir *d) { return dirfd(d->system ? d->system : d->extra); }
int tl_fonts_close(tl_font_dir *d)
{
    int result = 0, error = 0;
    if (d->system && closedir(d->system)) { result = -1; error = errno; }
    if (d->extra && closedir(d->extra)) { result = -1; error = errno; }
    free(d);
    if (error) errno = error;
    return result;
}

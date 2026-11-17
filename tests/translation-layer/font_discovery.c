/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Tests the production font VFS without unrelated ARM-only signal handlers. */
#define _DARWIN_C_SOURCE
#define _DEFAULT_SOURCE
#include "husk-tl-fonts.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void touch(const char *dir, const char *name)
{
    char p[2048]; snprintf(p, sizeof(p), "%s/%s", dir, name);
    FILE *f = fopen(p, "wb"); assert(f); assert(fwrite("font", 1, 4, f) == 4); fclose(f);
}
static void remove_file(const char *dir, const char *name)
{
    char p[2048]; snprintf(p, sizeof(p), "%s/%s", dir, name); assert(!unlink(p));
}
static void mapped(const char *input, const char *dir, const char *suffix)
{
    char p[2048], result[2048]; snprintf(p, sizeof(p), "%s%s", dir, suffix);
    const char *r = tl_fonts_resolve(input, result, sizeof(result));
    if (!r || strcmp(r, p)) { fprintf(stderr, "%s -> %s, expected %s\n", input, r ? r : "NULL", p); abort(); }
}
static void unmapped(const char *input)
{
    char b[2048]; assert(!tl_fonts_resolve(input, b, sizeof(b)));
}
static void check_view(tl_font_dir *d, int want_cjk, int want_latin, int want_upper)
{
    int cjk = 0, latin = 0, upper = 0, shared = 0; struct dirent *e;
    while ((e = tl_fonts_read(d))) {
        const char *n = e->d_name;
        if (!strcmp(n, ".") || !strcmp(n, "..")) continue;
        if (!strcmp(n, "NotoSansCJK-Regular.ttc")) cjk++;
        else if (!strcmp(n, "Latin.ttf")) latin++;
        else if (!strcmp(n, "Upper.OTF")) upper++;
        else if (!strcmp(n, "Shared.ttf")) shared++;
        else { fprintf(stderr, "unexpected bundle entry: %s\n", n); abort(); }
    }
    assert(!errno); /* EOF must not leak ENOENT from duplicate probing. */
    assert(cjk == want_cjk && latin == want_latin && upper == want_upper && shared == 1);
}
int main(void)
{
    char root[] = "/tmp/husk-font-discovery-XXXXXX"; assert(mkdtemp(root));
    char sys[1024], extra[1024], etc[1024], fake[2048], b[2048];
    snprintf(sys, sizeof(sys), "%s/fonts", root); assert(!mkdir(sys, 0700));
    snprintf(extra, sizeof(extra), "%s/extra", root); assert(!mkdir(extra, 0700));
    snprintf(etc, sizeof(etc), "%s/etc", root); assert(!mkdir(etc, 0700));
    touch(sys, "Latin.ttf"); touch(sys, "Shared.ttf"); touch(extra, "Shared.ttf");
    touch(extra, "NotoSansCJK-Regular.ttc"); touch(extra, "Upper.OTF");
    touch(extra, "Husk"); touch(extra, "icon.png");
    snprintf(fake, sizeof(fake), "%s/not-a-font.ttf", extra); assert(!mkdir(fake, 0700));
    touch(etc, "fonts.xml"); touch(etc, "font_fallback.xml");
    tl_set_system_fonts_dir(root); tl_set_extra_fonts_dir(extra);
    assert(!setenv("ANDROID_ROOT", "/runtime/java-data", 1));
    mapped("/system/fonts/Latin.ttf", sys, "/Latin.ttf");
    mapped("/runtime/java-data/fonts/Latin.ttf", sys, "/Latin.ttf");
    mapped("/system/fonts/Shared.ttf", sys, "/Shared.ttf");
    mapped("/system/fonts/NotoSansCJK-Regular.ttc", extra, "/NotoSansCJK-Regular.ttc");
    mapped("/runtime/java-data/fonts/NotoSansCJK-Regular.ttc", extra, "/NotoSansCJK-Regular.ttc");
    mapped("/runtime/java-data/etc/fonts.xml", etc, "/fonts.xml");
    mapped("/system/etc/fonts.xml", etc, "/fonts.xml");
    mapped("/runtime/java-data/etc/font_fallback.xml", etc, "/font_fallback.xml");
    mapped("/system/etc/font_fallback.xml", etc, "/font_fallback.xml");
    assert(!access(tl_fonts_resolve("/runtime/java-data/etc/fonts.xml", b, sizeof(b)), R_OK));
    unmapped("/runtime/java-data/fonts-backup/a.ttf");
    unmapped("/runtime/java-data-other/fonts/a.ttf");
    unmapped("/system/fonts-backup/a.ttf");
    unmapped("/runtime/java-data/etc/not-fonts.xml");
    unmapped("/runtime/java-data/files/save"); unmapped(NULL);
    assert(tl_fonts_is_directory("/system/fonts"));
    assert(tl_fonts_is_directory("/system/fonts/"));
    assert(tl_fonts_is_directory("/runtime/java-data/fonts"));
    assert(!tl_fonts_is_directory("/system/fonts/x"));
    assert(!tl_fonts_is_directory("/system/fonts-backup"));
    tl_font_dir *d = tl_fonts_open(), *other = tl_fonts_open(); assert(d && other);
    assert(tl_fonts_dirfd(d) >= 0);
    check_view(d, 1, 1, 1); check_view(other, 1, 1, 1); assert(!tl_fonts_close(other));
    tl_fonts_rewind(d); check_view(d, 1, 1, 1); assert(!tl_fonts_close(d));
    /* Missing optional downloads are normal, not an error after a successful open. */
    tl_set_extra_fonts_dir("/does-not-exist/husk-font-test");
    d = tl_fonts_open(); assert(d && !errno); check_view(d, 0, 1, 0); assert(!tl_fonts_close(d));
    tl_set_extra_fonts_dir(NULL); d = tl_fonts_open(); assert(d); check_view(d, 0, 1, 0); assert(!tl_fonts_close(d));
    tl_set_extra_fonts_dir(sys); d = tl_fonts_open(); assert(d); check_view(d, 0, 1, 0); assert(!tl_fonts_close(d));
    tl_set_extra_fonts_dir(extra);
    setenv("ANDROID_ROOT", "/runtime/java-data/", 1);
    mapped("/runtime/java-data/etc/fonts.xml", etc, "/fonts.xml");
    setenv("ANDROID_ROOT", "/system", 1); mapped("/system/etc/fonts.xml", etc, "/fonts.xml");
    unsetenv("ANDROID_ROOT"); mapped("/system/etc/fonts.xml", etc, "/fonts.xml");
    /* An absent system font directory can still enumerate the extra collection. */
    remove_file(sys, "Latin.ttf"); remove_file(sys, "Shared.ttf"); assert(!rmdir(sys));
    d = tl_fonts_open(); assert(d); check_view(d, 1, 0, 1); assert(!tl_fonts_close(d));
    tl_set_system_fonts_dir(NULL); unmapped("/system/fonts/Latin.ttf"); assert(!tl_fonts_is_directory("/system/fonts"));
    assert(!tl_fonts_open() && errno == ENOENT);
    for (size_t i = 0; i < 5; i++) {
        const char *names[] = {"Shared.ttf", "NotoSansCJK-Regular.ttc", "Upper.OTF", "Husk", "icon.png"};
        remove_file(extra, names[i]);
    }
    assert(!rmdir(fake)); assert(!rmdir(extra));
    remove_file(etc, "fonts.xml"); remove_file(etc, "font_fallback.xml"); assert(!rmdir(etc)); assert(!rmdir(root));
    puts("PASS: Android font XML paths, merged CJK discovery, lookup precedence, rewind, bundle filtering, missing directories, boundaries");
}

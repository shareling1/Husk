/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_FONTS_H
#define HUSK_TL_FONTS_H
#include <stdbool.h>
#include <stddef.h>
#include <dirent.h>
/* A single view of packaged Android fonts plus optional downloaded/bundled CJK.
 * Keep file lookup and directory discovery in agreement. No host files are copied. */
void tl_set_system_fonts_dir(const char *dir);
void tl_set_extra_fonts_dir(const char *dir);
const char *tl_fonts_resolve(const char *path, char *buf, size_t size);
bool tl_fonts_is_directory(const char *path);
typedef struct tl_font_dir tl_font_dir;
tl_font_dir *tl_fonts_open(void);
struct dirent *tl_fonts_read(tl_font_dir *dir);
void tl_fonts_rewind(tl_font_dir *dir);
int tl_fonts_dirfd(tl_font_dir *dir);
int tl_fonts_close(tl_font_dir *dir);
#endif

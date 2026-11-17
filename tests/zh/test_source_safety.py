#!/usr/bin/env python3
"""Regression checks for machine identifiers and offline-font integration."""
from pathlib import Path
import json, plistlib, re
R = Path(__file__).resolve().parents[2]
web = (R / "src/app/Husk/WebApp.swift").read_text(encoding="utf8")
for needle in ['"App": ["getInfo"', '"Keyboard": ["show"', 'capacitorEvent("App", "backButton"', '"platform": "Android"']:
    assert needle in web, needle
api = (R / "src/app/Husk/Play/PlayAPI.swift").read_text(encoding="utf8")
assert '"Email"' in api and '"Authorization"' in api
qemu = (R / "src/app/Husk/QemuRunner.swift").read_text(encoding="utf8")
for needle in ["Linux version", "init: init first stage started", "starting service 'zygote'"]:
    assert needle in qemu
fonts = (R / "src/app/Husk/SettingsTab.swift").read_text(encoding="utf8")
assert 'Bundle.main.url(forResource: "NotoSansCJK-Regular", withExtension: "ttc")' in fonts
assert 'guard !Self.isBundled else { return }' in fonts
assert '已内置 · 无需下载' in fonts
info = plistlib.loads((R / "src/app/Husk/Info.plist").read_bytes())
assert info["UIAppFonts"] == ["NotoSansCJK-Regular.ttc"]
manifest = json.loads((R / "docs/zh-cn/translation-manifest.json").read_text(encoding="utf8"))
assert len(manifest) > 1500
assert all(not (m["file"].endswith("WebApp.swift") and m["en"] in ["App", "Keyboard"]) for m in manifest)
print("PASS: protocol identifiers, boot markers, offline font wiring, and translation manifest")

io = (R / "src/translation-layer-next/husk-tl-bionic-io.c").read_text()
assert 'tl_fonts_resolve(path, buf, n)' in io
assert 'tl_fonts_is_directory(p)' in io
assert 'tl_fonts_read(g->fonts)' in io
assert 'guest_dir *d = b_opendir(path)' in io
ndk = (R / "src/translation-layer-next/husk-tl-bionic-ndk.c").read_text()
assert 'tl_font_dir *d = tl_fonts_open()' in ndk and 'tl_fonts_read(d)' in ndk
assert info["CFBundleVersion"] == "150"
print("PASS: bionic/NDK font discovery wiring and font-fix build identity")

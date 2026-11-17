#!/usr/bin/env python3
"""Stage unchanged runtime assets from official 3.4; rebuild app sources separately."""
import bz2, hashlib, json, shutil, subprocess, urllib.request, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
BUILD.mkdir(exist_ok=True)
RELEASE_SHA = "a7da6cb58b999ff29b25a61c088a49ffad4ab3b6516aaf96997093bd0b8fa752"
FONT_SHA = "b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a"
def fetch(url, target, expected):
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
        print("Downloading", url, flush=True)
        with urllib.request.urlopen(url, timeout=180) as src, target.open("wb") as dst:
            shutil.copyfileobj(src, dst)
    assert hashlib.sha256(target.read_bytes()).hexdigest() == expected, target
    print("Verified", target.name, expected, flush=True)
release = BUILD / "Husk-official-3.4.tipa"
fetch("https://github.com/Leviidev/Husk/releases/download/3.4/Husk.tipa", release, RELEASE_SHA)
original = BUILD / "official-3.4"
if not (original / "Payload/Husk.app/Husk").exists():
    with zipfile.ZipFile(release) as z:
        for item in z.infolist():
            resolved = (original / item.filename).resolve()
            assert resolved.is_relative_to(original.resolve()), item.filename
        z.extractall(original)
app = original / "Payload/Husk.app"
def copy(src, dst):
    assert src.exists(), src
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir(): shutil.copytree(src, dst, dirs_exist_ok=True)
    else: shutil.copy2(src, dst)
lib = BUILD / "ios-arm64/lib"
for name in ("libqemu-aarch64-softmmu.dylib", "libhuskps4.dylib"):
    copy(app / "Frameworks" / name, lib / name)
copy(app / "Frameworks/libANGLE-shared.dylib", BUILD / "ios-arm64/sysroot/lib/libANGLE-shared.dylib")
mvk = BUILD / "release-frameworks/MoltenVK.framework"
copy(app / "Frameworks/MoltenVK.framework", mvk)
# Executable mode is not preserved by Python's zip extraction.
(mvk / "MoltenVK").chmod(0o755)
xc = lib / "MoltenVK.xcframework"
if not xc.exists():
    subprocess.run(["xcodebuild", "-create-xcframework", "-framework", str(mvk), "-output", str(xc)], check=True)
for name in ("android-system", "java-runtime"):
    copy(app / name, BUILD / name)
for name in ("vmlinuz-virt", "initramfs-virt"):
    copy(app / name, ROOT / "guests/phase0" / name)
bios = ROOT / "third_party/build/qemu-10.0.12-utm/pc-bios"
copy(app / "pc-bios", bios)
(bios / "edk2-aarch64-code.fd.bz2").write_bytes(bz2.compress((app / "edk2-aarch64-code.fd").read_bytes()))
font = ROOT / "src/app/Husk/Resources/BundledFonts/NotoSansCJK-Regular.ttc"
fetch("https://raw.githubusercontent.com/notofonts/noto-cjk/165c01b46ea533872e002e0785ff17e44f6d97d8/Sans/OTC/NotoSansCJK-Regular.ttc", font, FONT_SHA)
from configure_cjk_fonts import configure
configure(BUILD / "android-system")
# Keep all original runtime notices alongside the source and OFL notices.
legal = ROOT / "src/app/Husk/Resources/legal"
for notice in app.rglob("*"):
    if notice.is_file() and (notice.name.startswith("LICENSE") or notice.name.startswith("NOTICE")):
        if not (legal / notice.name).exists(): copy(notice, legal / notice.name)
(BUILD / "zh-provenance.json").write_text(json.dumps({
    "upstream_source": "29abb512d81bf8cc08babcbe7f7007cb557208ef",
    "runtime_release": "3.4", "runtime_sha256": RELEASE_SHA,
    "font_commit": "165c01b46ea533872e002e0785ff17e44f6d97d8", "font_sha256": FONT_SHA,
    "strategy": "Recompile Swift/C app and Rust pairing; reuse official runtime binaries; normalize system CJK XML for pinned static OTC",
    "font_compatibility_fix": "Merged system/extra font discovery and ANDROID_ROOT font XML mapping"
}, indent=2) + "\n")
print("All runtime dependencies and bundled CJK font staged.")

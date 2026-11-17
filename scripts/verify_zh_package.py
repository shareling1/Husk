#!/usr/bin/env python3
import hashlib, io, json, plistlib, sys, zipfile
import xml.etree.ElementTree as ET
from configure_cjk_fonts import FACES, FONT
from pathlib import Path
from fontTools.ttLib import TTCollection
package = Path(sys.argv[1])
checks = []
with zipfile.ZipFile(package) as z:
    assert z.testzip() is None
    base = "Payload/Husk.app/"
    names = set(z.namelist())
    def required(name):
        assert base + name in names, name
        checks.append(name)
        return z.read(base + name)
    info = plistlib.loads(required("Info.plist"))
    assert info["HuskChineseEdition"] is True
    assert info["HuskUpstreamSource"] == "29abb512d81bf8cc08babcbe7f7007cb557208ef"
    executable = required(info["CFBundleExecutable"])
    assert b"fonts: Android discovery entries=%zu CJK-listed=%s CJK-readable=%s" in executable
    assert info["CFBundleVersion"] == "150"
    assert executable[:4] in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")
    for name in ("Frameworks/libqemu-aarch64-softmmu.dylib", "Frameworks/libANGLE-shared.dylib", "Frameworks/libhuskps4.dylib", "Frameworks/MoltenVK.framework/MoltenVK", "Frameworks/StikJIT.framework/StikJIT", "PlugIns/HuskJITHelper.appex/HuskJITHelper", "PlugIns/HuskDownloadsWidget.appex/HuskDownloadsWidget", "java-runtime/husk-framework.dex", "android-system/etc/fonts.xml", "zh-Hans.lproj/Localizable.strings", "LICENSE-NotoSansCJK.txt"):
        required(name)
    font = required("NotoSansCJK-Regular.ttc")
    assert hashlib.sha256(font).hexdigest() == "b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a"
    collection = TTCollection(io.BytesIO(font), lazy=True)
    glyphs = set()
    for face in collection.fonts:
        for cmap in face["cmap"].tables:
            if cmap.isUnicode(): glyphs.update(cmap.cmap)
    sample = "中文汉化字体游戏设置下载帮助配对简体繁體測試日本語한국어，。！？"
    assert all(ord(c) in glyphs for c in sample), "missing CJK glyphs"
    for xml_name in ("fonts.xml", "font_fallback.xml"):
        root = ET.fromstring(required("android-system/etc/" + xml_name))
        seen = set()
        for family in root.findall("family"):
            lang = family.get("lang")
            if lang not in FACES: continue
            entries = [e for e in family.findall("font") if (e.text or "").strip() == FONT]
            if not entries: continue  # other language-specific families (e.g. hentaigana)
            assert len(entries) == 2
            seen.add(lang)
            index, ps_name = FACES[lang]
            for entry in entries:
                assert (entry.text or "").strip() == FONT
                assert int(entry.get("index")) == index
                assert entry.get("postScriptName") == ps_name
                assert entry.get("weight") == "400"
                assert entry.get("supportedAxes") is None and not entry.findall("axis")
                face = collection.fonts[index]
                assert face["name"].getDebugName(6) == ps_name
                assert "fvar" not in face
                assert all(ord(c) in face.getBestCmap() for c in sample)
        assert seen == set(FACES), seen
    collection.close()
report = {"file": package.name, "sha256": hashlib.sha256(package.read_bytes()).hexdigest(), "bytes": package.stat().st_size, "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"], "commit": info.get("HuskBuildCommit"), "checks": checks, "font_glyph_sample": sample, "device_tested": False}
package.with_suffix(".verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print(json.dumps(report, ensure_ascii=False, indent=2))

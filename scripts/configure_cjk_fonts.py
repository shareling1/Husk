#!/usr/bin/env python3
"""Make Android XML describe the pinned static OTC, not Android's variable font.
No game assets are read or distributed. Applied only to staged system resources.
"""
from pathlib import Path
import xml.etree.ElementTree as ET

# Noto CJK OTC 165c01b: actual collection indices and PostScript names.
FACES = {"zh-Hans": (2, "NotoSansCJKsc-Regular"),
         "zh-Hant,zh-Bopo": (3, "NotoSansCJKtc-Regular"),
         "ja": (0, "NotoSansCJKjp-Regular"),
         "ko": (1, "NotoSansCJKkr-Regular")}
FONT = "NotoSansCJK-Regular.ttc"

def configure(system_root: Path):
    for name in ("fonts.xml", "font_fallback.xml"):
        path = system_root / "etc" / name
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        tree = ET.parse(path, parser=parser)
        found = set()
        for family in tree.getroot().findall("family"):
            lang = family.get("lang")
            if lang not in FACES:
                continue
            cjk = [f for f in family.findall("font")
                   if (f.text or "").strip() in (FONT, "NotoSerifCJK-Regular.ttc")]
            if not cjk:
                continue
            found.add(lang)
            for old in cjk:
                family.remove(old)
            index, ps_name = FACES[lang]
            attrs = {"weight": "400", "style": "normal", "index": str(index), "postScriptName": ps_name}
            ET.SubElement(family, "font", attrs).text = FONT
            # There is no bundled CJK serif face. Use the available CJK sans
            # glyphs for serif fallback too, instead of a non-existent TTC.
            ET.SubElement(family, "font", dict(attrs, fallbackFor="serif")).text = FONT
        assert found == set(FACES), (name, found)
        ET.indent(tree, space="  ")
        tree.write(path, encoding="utf-8", xml_declaration=True)
        print("Configured static CJK collection:", path)

if __name__ == "__main__":
    import sys
    configure(Path(sys.argv[1]))

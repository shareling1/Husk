#!/usr/bin/env python3
from pathlib import Path
import sys, tempfile, xml.etree.ElementTree as ET
R = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(R / "scripts"))
from configure_cjk_fonts import configure, FACES, FONT
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp); (root / "etc").mkdir()
    fixture = ET.Element("familyset")
    for lang in FACES:
        family = ET.SubElement(fixture, "family", {"lang": lang})
        for weight in (100, 400, 900):
            f = ET.SubElement(family, "font", {"weight": str(weight), "index": "0", "postScriptName": "wrong", "supportedAxes": "wght"})
            f.text = FONT
            ET.SubElement(f, "axis", {"tag": "wght", "stylevalue": str(weight)})
        ET.SubElement(family, "font", {"fallbackFor": "serif"}).text = "NotoSerifCJK-Regular.ttc"
    other = ET.SubElement(fixture, "family", {"lang": "ja"})
    ET.SubElement(other, "font").text = "NotoSerifHentaigana.ttf"
    for name in ("fonts.xml", "font_fallback.xml"):
        ET.ElementTree(fixture).write(root / "etc" / name)
    configure(root)
    before = [(root / "etc" / n).read_bytes() for n in ("fonts.xml", "font_fallback.xml")]
    configure(root)
    assert before == [(root / "etc" / n).read_bytes() for n in ("fonts.xml", "font_fallback.xml")]
    for data in before:
        tree = ET.fromstring(data)
        assert tree.findall("family")[-1].find("font").text == "NotoSerifHentaigana.ttf"
        for family in tree.findall("family")[:-1]:
            index, ps_name = FACES[family.get("lang")]
            fonts = family.findall("font"); assert len(fonts) == 2
            assert {f.get("fallbackFor") for f in fonts} == {None, "serif"}
            for f in fonts:
                assert f.text == FONT and f.get("weight") == "400" and f.get("index") == str(index)
                assert f.get("postScriptName") == ps_name
                assert not f.findall("axis") and f.get("supportedAxes") is None
print("PASS: static TTC XML indices, names, no variable axes, serif fallback, other families preserved, idempotence")

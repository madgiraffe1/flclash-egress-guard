"""Check local README images, including exact filename case on macOS."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

root = Path(sys.argv[1])
checked = 0
for name in ("README.md", "README.zh-CN.md"):
    text = (root / name).read_text(encoding="utf-8")
    sources = re.findall(r'<img\b[^>]*\bsrc="([^"]+)"', text)
    sources += re.findall(r'!\[[^\]]*\]\(([^)\s]+)', text)
    local = [s for s in sources if not re.match(r"https?://", s)]
    assert local, f"{name}: no local images"
    assert "docs/images/logo.svg" in local, f"{name}: logo reference missing"
    for source in local:
        path = root
        for part in Path(source).parts:
            assert part in {p.name for p in path.iterdir()}, f"{name}: missing or wrong case: {source}"
            path /= part
        assert path.is_file(), f"{name}: not a file: {source}"
        if path.suffix == ".svg":
            ET.parse(path)
        if path.name.startswith(("ui-", "menubar-")):
            assert (".en." in path.name) == (name == "README.md"), f"{name}: wrong language asset: {source}"
        checked += 1
    assert any(s.endswith(".gif") for s in local), f"{name}: demonstration GIF missing"
print(f"PASS: {checked} local README image references exist with exact case and correct language")

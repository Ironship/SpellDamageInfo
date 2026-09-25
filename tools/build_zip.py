"""Builds dist/SpellDamageInfo-<version>.zip: one top folder, the .toc, the files it lists, the icon and the licence.

    python tools/build_zip.py

Then opens the zip again and checks every file against the source.
"""
import re
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
toc_path = root / "SpellDamageInfo.toc"
toc = toc_path.read_text(encoding="utf-8")
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
files = ["SpellDamageInfo.toc"] + [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("##")]
# the icon the .toc names in "## IconTexture" (tools/make_icon.py exports it)
files.append("icon.tga")
# the licence, which carries the MIT notice of DoesItDie that Options.lua is adapted from
files.append("LICENSE")

dist = root / "dist"
dist.mkdir(exist_ok=True)
out = dist / f"SpellDamageInfo-{version}.zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in files:
        z.write(root / name, f"SpellDamageInfo/{name}")

with zipfile.ZipFile(out) as z:
    bad = z.testzip()
    if bad:
        sys.exit(f"corrupt member: {bad}")
    names = sorted(z.namelist())
    if names != sorted(f"SpellDamageInfo/{n}" for n in files):
        sys.exit(f"unexpected members: {names}")
    for name in files:
        if z.read(f"SpellDamageInfo/{name}") != (root / name).read_bytes():
            sys.exit(f"content differs: {name}")
print(f"{out.name}: {out.stat().st_size} bytes, {len(files)} files, verified")

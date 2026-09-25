"""Adds the descriptions /sdi dump and /sdi dump all wrote into the saved variables to
tests/fixtures/forever_client_texts.json: the text as the game client itself shows it.

    python tools/import_dump.py "<WoW>/_classic_beta_/WTF/Account/<account>/SavedVariables/SpellDamageInfo.lua" [...]

Takes the spellbook dump, the all-classes dump and the list of spells without a number. A text
already in the fixture for the same spell id and language is replaced by the newer one. Nothing
is written by hand. Needs: pip install lupa
"""
import json
import sys
from pathlib import Path

from lupa import lua51

root = Path(__file__).resolve().parent.parent
fixture = root / "tests/fixtures/forever_client_texts.json"

rows = {}
if fixture.exists():
    for r in json.loads(fixture.read_text(encoding="utf-8")):
        rows[(r["id"], r["lang"])] = r


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


added = 0
for path in sys.argv[1:]:
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(Path(path).read_text(encoding="utf-8"))
    db = rt.globals().SpellDamageInfoDB
    if db is None:
        sys.exit(f"{path}: no SpellDamageInfoDB")
    sources = []
    for key in ("dump", "dumpAll"):
        d = db[key]
        if d is not None:
            sources += [(s, d.lang, d.build) for s in lua_list(d.spells)]
    sources += [(m, m.lang, m.build) for m in lua_list(db.misses)]
    for s, lang, build in sources:
        if not isinstance(s.text, str) or not lang:
            continue
        key = (int(s.id), lang)
        if key not in rows:
            added += 1
        rows[key] = {"id": int(s.id), "lang": lang, "name": s.name, "build": str(build), "text": s.text}

out = sorted(rows.values(), key=lambda r: (r["lang"], r["id"]))
fixture.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
print(f"{fixture.name}: {len(out)} texts ({added} new)")
